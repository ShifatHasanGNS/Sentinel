# Sentinel: a quick study guide

A ten-minute read. It explains what each group of files does, in plain words with the technical names in brackets, and how the groups talk to each other. For the exact `file:proc` of any feature, see `Docs/Features.md`; for the maths, `Docs/Graphics-Theory.md`.

## 1. The big idea

Sentinel is a small game engine plus a game, and **nothing is loaded from disk except shader text**. There are no 3D models, no pictures, no sound files. Every shape, texture and sound is computed by code from a number called a _seed_, so the same seed always gives the same world.

The code is stacked in layers. A layer may use the layers below it, never above:

```
Game              the mission, soldiers, weapons, base layout
  Engine/Render   draws a frame (lights, shadows, sky, post effects)
    Engine/World  physics-like rules: collision, ladders, vehicles
      Engine/Procedural  makes meshes, terrain, noise, textures
        Engine/GPU       thin wrappers over OpenGL
          Engine/Platform  window, keyboard/mouse, clock
```

`Engine/Audio` sits beside the stack and is used by the Game. This rule keeps the engine reusable: it never knows the game exists.

## 2. How the program runs (`Source/`)

- **Main.odin**: a table of contents. Start up, loop, shut down.
- **Config.odin**: one settings struct filled from the command-line flags (`--scene`, `--view`, `--mission`...).
- **Loop.odin**: the heartbeat. Every frame it does _input, then update, then render_. It also handles window life: pausing when you click away, sleeping when minimised.

Everything else is reached from here in three or four calls.

## 3. Window, input, clock (`Engine/Platform`)

- **Window**: opens the window through GLFW, handles resizing, fullscreen (F11), minimum size, centring.
- **Input**: reads keys and mouse. The mouse is "captured" (hidden, endless turning) only after you click; F9 or losing focus frees it so you can move or resize the window.
- **Clock**: the time between frames, so movement does not depend on speed.

## 4. Talking to the graphics card (`Engine/GPU`)

OpenGL is clumsy to use directly, so these files wrap it:

- **Shader / ShaderSource**: loads shader text, supports `#include` (OpenGL lacks it) and reports compile errors loudly.
- **Buffer / VertexArray**: send vertex data to the card.
- **Texture / Sampler / Framebuffer**: images, how they are filtered, and off-screen canvases to draw into.
- **UniformBlock**: batches of settings shared by shaders.
- **FullscreenPass**: draws one big triangle so a shader runs on every pixel (used for lighting and effects).
- **Timer, Debug, Screenshot, Capabilities**: GPU timings per pass, error checking after every GL call, saving a picture, and asking what the machine supports.

macOS stops at OpenGL 4.1: no compute shaders. So every "bake" or filter is done as a full-screen pixel pass.

## 5. Making things from nothing (`Engine/Procedural`)

- **Hash / Noise**: deterministic randomness. Noise is smooth randomness (hills, clouds, grain).
- **Primitives**: spheres, boxes, cylinders, cones and so on, each with correct normals and texture coordinates.
- **Deform**: bends, twists, tapers and noise bumps applied to a primitive.
- **MeshBuilder / Mesh / MeshValidate**: glue pieces into one mesh, and a checker that rejects bad meshes (flipped faces, bad normals).
- **Assembly**: combines parts into one object.
- **Terrain**: a height map from noise, cut into chunks, with a flat plateau for the base.
- **Scatter**: where trees, rocks and bushes go (decided by a hash of the position, so it is repeatable).
- **TextureRecipe**: a texture is a small shader (a "recipe") rendered once at startup into colour, normal and roughness maps. The recipes live in `Shaders/Recipes` (Concrete, Camo, Bark...). They are built to tile with no seam, which `Tests/TextureCheck` proves.

## 6. Drawing a frame (`Engine/Render` + `Shaders/`)

The renderer is **deferred**: first draw every object's surface data (colour, normal, roughness) into several hidden images (the _G-buffer_), then light the whole screen in one pass. This makes many lights cheap.

Order of a frame (`Renderer.odin`):

1. **Shadows** (`ShadowMap`, `Shadows`, `SpotShadows`): render the scene from the sun's point of view in three zoom levels (cascades), plus a few spotlights.
2. **Geometry** (`Scene`, `Material`, `Mesh`): fill the G-buffer. `Culling` skips what the camera cannot see.
3. **Ambient occlusion** (`Ssao`): darkens creases and corners.
4. **Lighting** (`Light`, `Illumination`, shaders `DeferredBase` and `DeferredLight`): sun, sky light, and each lamp as a glowing sphere volume. Six surface models (Lambert, Phong, Blinn-Phong, Oren-Nayar, Cook-Torrance, skin) are chosen per material. Sky colour comes from `SkyLut`, a small table of atmosphere scattering.
5. **Particles** (`ParticlePass`): sparks, smoke, tracers.
6. **Post** (`Bloom`, then tonemap and FXAA shaders): glow, turn bright HDR values into screen colours, smooth jagged edges.
7. **HUD** (`Hud`): flat text and rectangles on top.

Shared shader maths lives in `Shaders/Include` (Brdf, Lighting, Noise, Sky, Atmosphere, TerrainBlend...), included by the big shaders.

## 7. Rules of the world (`Engine/World`)

Pure logic, no drawing:

- **Solid / Collision / Raycast**: boxes (also turned ones) that block you, and rays for bullets and line of sight.
- **Chunks**: loads terrain chunks around the player.
- **Ladder**: the climbing state machine. **GroundVehicle** and **Aircraft**: how cars, tanks and the helicopter accelerate, steer, lift and land. **Spring**: a smooth damped motion used for hit reactions.

## 8. Sound (`Engine/Audio` + `Game/Sandbox/Sound*`)

- **Synth**: builds each sound from maths (noise bursts for gunshots, sine tones for beeps, filtered noise for wind).
- **Mixer**: plays up to 48 sounds at once, positions them left or right by direction and volume by distance, and limits peaks so it never clips.
- **Device**: opens the speakers through miniaudio.
- `Sound.odin` creates the sound bank; `SoundFeedback.odin` watches the game each frame and fires the right cue when something _changes_ (you got hit, you landed, a soldier died), and keeps wind, crickets and birds going.

## 9. Looks of the game objects (`Game/Materials`, `Game/Catalogue`)

- **Materials**: one table row per surface (concrete, camo, rust...) tying a name to its recipe and light model.
- **Catalogue**: every object is a _table of parts_ (shape, size, bends, material), not code. `Buildings`, `Fortifications`, `Props`, `Vehicles`, `Doors`, `Paving` (roads, lawns) and `Objects` (the master list) hold the tables. Its tests check each object has a realistic real-world size.

## 10. The base (`Game/Base`)

- **Layout**: the plan: fence ring, gate, barracks row, HQ, hangar, helipad, motor pool, roads and lawns, each as a position and rotation.
- **Footprint**: the floor outline of each placement; tests ensure nothing overlaps.
- **BaseScene**: turns the layout into meshes, instanced collision, doors and lights.
- **Doors / DoorRender**: hinged doors that open with E. **InteriorLights / NightLights**: lamps inside buildings and floodlights at night.

## 11. People and weapons (`Game/Characters`, `Game/Weapons`)

- **Skeleton, Ik, Gait**: a soldier is joint _positions_; legs and arms are placed by two-bone inverse kinematics and a walking cycle that keeps feet planted.
- **Soldier / Character / CharacterRender**: body-part tables worn in five colour variants; all soldiers of a variant draw in one batch.
- **Weapons / Behavior**: stats (damage, rate, magazine) and firing behaviour for the rifle, pistol, sniper, launcher and so on.

## 12. Gameplay rules (`Game/Gameplay`, `Game/Vehicles`)

- **Player, Health, Pickup**: movement state, damage and regeneration, ammo and medkit pickups.
- **Enemy / EnemyAi / Stealth**: soldiers patrol, see within a cone, hear shots, chase and shoot; crouching and standing still make you harder to spot.
- **Battle / Target**: bullets, hits, destructible targets.
- **TimeOfDay / Daylight**: sun position over the day.
- **Vehicles**: boarding, turret aim and gunfire, run-over damage, plus `VehicleRender` to draw them.

## 13. The mission (`Game/Mission`)

- **Mission**: a small state machine: get inside, hack the HQ computer, destroy the radar, rescue the hostage, reach the beacon. It only receives _observations_ ("player is near the terminal and pressing E") and answers with progress, so it is easy to test.
- **SecurityCamera**: cameras that spot you and raise the alarm. **Save**: checkpoint data.

## 14. Gluing it all together (`Game/Sandbox`)

The Sandbox is the playable level and the place where all layers meet.

- **Sandbox / Play**: the owner of everything; each frame it updates the player, enemies, vehicles, mission and effects, and builds the list of things to draw.
- **MissionPlay**: connects the mission rules to the world (terminal, radar, hostage, extraction beacon, briefing screen, messages). The hostage is placed in the middle barracks and follows you once rescued.
- **Driving, FlyCamera, LadderHands, Compass**: vehicle control, the free camera, hands on ladder rungs, the heading strip.
- **Optics**: binoculars, scope and the tactical map. **Particles, Props, Trees, WorldChunks, SecurityCameras**: effects, scattered props, tree meshes, terrain chunk streaming, camera objects.
- **SaveGame**: writes and restores checkpoints. **Sound / SoundFeedback**: see section 8.

## 15. Other scenes and tools

- **Game/Showroom**: gallery of materials and lights, a catalogue viewer, a soldier line-up (`--scene showroom|catalogue|soldiers`).
- **Tests/**: `GpuCheck`, `TextureCheck` (every material tiles exactly), `RenderCheck` (lighting maths), `WindowCheck` (resize and minimise), `AudioCheck` (every sound plays). Plain unit tests sit beside the code in `*_test.odin`.
- **Tools/CheckAll.sh** runs every test and both automatic playthroughs; **ToPng.sh** converts screenshots.

## 16. Follow one event end to end

_You press E next to the hostage._

1. `Input` records the key. `Loop` calls the Sandbox update.
2. `MissionPlay` sees you are within reach and in line of sight, and passes an observation to `Mission`.
3. `Mission` marks "rescue hostage" done. `MissionPlay` flags the hostage as rescued, so `update_hostage` makes them walk behind you.
4. `Play` adds the hostage character to the draw list; `CharacterRender` batches it; `Renderer` draws it into the G-buffer, lights and shades it.
5. `SoundFeedback` and the HUD show the objective tick and a message.

That path (input, rules, state, drawing, sound) is the same for every feature in the game.
