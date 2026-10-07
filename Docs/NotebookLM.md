# SENTINEL: complete study document

This document explains the whole Sentinel project in detail: what it is, why it is built the way it is, how every part works, which file does what, and how the parts connect. It is written to be read from top to bottom, or to be turned into a video lesson. Technical names are written in `code style` and are always explained in plain words next to them.

---

## Part 1. What Sentinel is

### 1.1 In one paragraph

Sentinel is a game engine and a game built together from scratch for a computer graphics course. The engine is a set of reusable code layers that open a window, talk to the graphics card, generate shapes, textures and sounds, light a scene realistically and run simple physics. The game on top is a small military infiltration mission in the spirit of the 2000 game *Project I.G.I.: I'm Going In*. The player sneaks into an enemy compound, hacks a computer, destroys a radar station, rescues a hostage and reaches an extraction point, while soldiers patrol, security cameras sweep and an alarm can call reinforcements.

### 1.2 The hard rule: everything is generated

The single most important design rule is that **no pre-made content is stored on disk**. There are no 3D model files, no image or texture files, no sound files. The only files read at run time are the shader text files (the small programs that run on the graphics card). Everything else is computed by code from a *seed*, a fixed number that makes randomness repeatable. Run it twice and you get the identical world.

Consequences of this rule, which explain many later decisions:

- A tank, a soldier or a barracks is built out of simple primitives (boxes, spheres, cylinders, cones, capsules, tori, wedges), moved and sized by transforms, then bent and roughened by *deformers* (noise bumps, twists, tapers, bends).
- A texture such as concrete or camouflage is not a picture. It is a small formula (a shader "recipe") that is rendered once at start-up into the graphics card's memory.
- A gunshot or a wind loop is not a recording. It is a mathematical waveform computed at start-up.
- Because nothing is stored, the project is tiny on disk, fully reproducible, and the rules about licensing are trivial: there are no third-party assets.

### 1.3 Technology

- Language: **Odin**, a small, fast, C-like language with manual memory control.
- Graphics: **OpenGL 4.1 core profile**. This is the highest version macOS supports. It has **no compute shaders and no shader storage buffers**, which forced a design where every "baking" or filtering job is done as a full-screen pixel (fragment) pass instead.
- Window and input: **GLFW**.
- Audio output: **miniaudio** (only the output device; every sound is synthesised in code).
- Size: about 168 Odin source files (about 20,000 lines) and 59 GLSL shader files (about 2,250 lines).

### 1.4 Where it came from

Version 1 was a course scene viewer: a night-time base with nine objects, a single 2,263-line `Main.odin`, duplicated lighting code in two shader stages and no concept of textures. It is preserved under the git tag `legacy-v1`. Version 2 (this project) was a clean-slate rewrite with a layered architecture, a deferred renderer, procedural textures and a real game.

---

## Part 2. The architecture: layers and rules

### 2.1 The layer stack

Code is organised in layers. A layer may use layers below it but **never** layers above it. This is enforced by convention and by the way packages import each other.

```
Game               content and gameplay (base, soldiers, weapons, mission, sandbox)
  Engine/Render    draws a frame (deferred lighting, shadows, sky, post effects, HUD)
    Engine/World   rules of the world (collision, rays, ladders, vehicles, aircraft)
      Engine/Procedural   makes meshes, terrain, noise, texture recipes
        Engine/GPU        thin wrappers over OpenGL (shaders, buffers, textures)
          Engine/Platform   window, keyboard and mouse, clock
Engine/Audio       mixer + synthesiser + output device (used by Game, independent of the rest)
```

Why it matters: the engine can be understood and tested without the game. For example, `Engine/World` can test "does a capsule slide along a wall" without opening a window.

### 2.2 Folder and naming conventions

- Folders and files are PascalCase (`Game/Sandbox/MissionPlay.odin`).
- One package per folder. One feature per file, named after the feature.
- Names are full words with units last: `range_meters`, `fov_degrees`, `delay_seconds`. No abbreviations.
- Procedures are short (about 40 lines at most) and do one job. The rule "put `if` in the parent and `for` in the helpers" keeps branching in one place.
- Content is *data*: an object is a table of parts, not branching builder code.
- Comments appear only where the maths is invisible in the code, and then they name the formula and say why. The theory itself lives in `Docs/Graphics-Theory.md`.
- Preconditions are asserted and every GL call is error-checked. Failures are never swallowed.

### 2.3 Documentation map

- `README.md`: what it is, how to run, controls.
- `CLAUDE.md`: rules, commands, flags, how to add things.
- `Docs/Features.md`: a table mapping every feature to `file:procedure`.
- `Docs/Graphics-Theory.md`: the maths behind the code comments.
- `Docs/Decisions.md`: short records of why each design choice was made.
- `Docs/Roadmap.md`: milestone status M0 to M15.
- `Docs/Optimization.md`: the performance log.
- `Docs/Architecture.md`, `Docs/World-Design.md`, `Docs/Realism-Plan.md`, `Docs/Study.md` (a ten-minute overview).

### 2.4 How the program runs: `Source/`

- `Main.odin` is a table of contents: initialise, loop, shut down. Any feature is reachable in three or four named calls.
- `Config.odin` holds one `Config` struct filled from the command-line flags: `--scene sandbox|showroom|catalogue|soldiers`, `--object`, `--view`, `--overlay`, `--fullscreen`, `--mission rescue|night`, `--continue`, `--autoplay`, `--briefing`, `--demo`, `--drive`, `--time`, `--capture`, `--benchmark`.
- `Loop.odin` is the heartbeat. Every frame it does **input, then update, then render**. It also owns window life: pause when focus is lost, sleep when minimised, screenshots (`--capture`) and the scripted performance test (`--benchmark`).

The flow of one frame: `Loop` polls input (`Engine/Platform`), calls the active scene's update (usually `Game/Sandbox`), which steps the game rules and gathers a list of things to draw, then hands that list to the renderer (`Engine/Render`), which draws it with the graphics card and swaps the buffers.

---

## Part 3. Platform: window, input, clock (`Engine/Platform`)

- `Window.odin` creates the window and the OpenGL 4.1 context via GLFW, handles resizing, fullscreen (F11), a minimum size (640 by 392 as measured on the real window), centring on the screen and showing the window only after loading finishes (so you never see a blank frame).
- `Input.odin` polls keys and mouse each frame. The mouse uses a **click-to-capture** model: the cursor stays free (visible, able to move and resize the window) until the first click; then it is captured for mouse-look. F9 frees or recaptures it. When the window loses focus the game pauses and frees the cursor automatically. Reason: a permanently captured cursor made the window impossible to move or resize with a trackpad.
- `Clock.odin` gives the time between frames, capped so a long pause cannot make the physics explode.

Window rules learned during testing: GLFW size limits only apply to mouse drags, not to `SetWindowSize` calls, so tests cannot assert the minimum size through code; `Tests/WindowCheck` instead checks that the game keeps rendering correctly through resize, maximise, minimise, restore and fullscreen toggles (141 checks).

---

## Part 4. GPU layer: talking to the graphics card (`Engine/GPU`)

OpenGL is a verbose, global-state API. These files wrap it so the rest of the engine never touches raw GL calls.

- `Debug.odin`: `GL_Check` after every call; any error is reported loudly.
- `ShaderSource.odin`: loads shader text and adds what OpenGL lacks: `#include` for shared code, `#stage` markers so one file can hold vertex and fragment stages, and `#define` injection. In v1 the lighting code was copy-pasted into two stages; includes remove that duplication.
- `Shader.odin`: compiles and links, caches uniform locations, and has uniform setters.
- `Buffer.odin`, `VertexArray.odin`: vertex, index and uniform buffers; vertex layouts including per-instance streams for instancing.
- `Texture.odin`: 2D, array, 3D and cube textures; formats from 8-bit to 32-bit float and depth; mipmaps; a texture-unit allocator so callers never track unit numbers. Because macOS lacks `glTexStorage` (GL 4.2), each mip level is allocated explicitly.
- `Sampler.odin`: filtering, wrapping, anisotropic filtering and shadow comparison modes, cached so identical samplers are shared.
- `Framebuffer.odin`: off-screen canvases with multiple render targets, resize, and rendering into a chosen layer of an array texture.
- `UniformBlock.odin`: std140 blocks for sharing settings.
- `FullscreenPass.odin`: draws one oversized triangle so a shader runs on every pixel; the basis for lighting, baking and post-processing without compute shaders.
- `Timer.odin`: GPU timers, so each render pass reports its cost in milliseconds.
- `Screenshot.odin`: saves the frame as a BMP (converted by `Tools/ToPng.sh`).
- `Capabilities.odin`: asks what the machine supports (for example the anisotropy limit).

---

## Part 5. Procedural generation (`Engine/Procedural`)

This is where "everything from code" becomes real.

### 5.1 Randomness and noise

- `Hash.odin`: an integer hash (PCG family). Given a position and a seed it returns a repeatable pseudo-random number. Everything "random" in the world (where a tree stands, which way a rock leans) is a hash of coordinates, never a stateful random generator, so a chunk can be rebuilt identically at any time.
- `Noise.odin`: gradient (Perlin) noise and fractal Brownian motion (fbm, several noise layers of increasing detail added together). Perlin noise blends the contributions of lattice corners using the quintic curve 6t^5 - 15t^4 + 10t^3, which has zero first and second derivatives at the cell edges, so the result is smooth across cell borders.

### 5.2 Shapes

- `Primitives.odin`: box, sphere, cylinder, cone, capsule, torus and wedge. Each emits positions, normals, tangents and texture coordinates analytically. Tangents are computed per primitive instead of from texture-coordinate derivatives because the poles of a sphere make derivative-based tangents degenerate.
- `Mesh.odin`: the CPU mesh type and its bounds.
- `MeshBuilder.odin`: appends one mesh onto another under a transform, with a proper normal matrix and mirror-safe winding.
- `Deform.odin`: noise displacement, taper, twist, bend and bulge. A deformer is a smooth position map F. Normals follow the Jacobian: a tangent maps as t' = J t but a normal must stay perpendicular, giving n' = J^-T n. This differs from "J n" under non-uniform scale and is why deformed objects stay correctly lit.
- `Assembly.odin`: the **Part** concept. A `Part` is a primitive plus deformers plus a transform plus a material (plus optional emission, a `solid` flag, and a `collision_only` flag). An assembly is a list of parts merged per material. Collision boxes come from the parts marked solid, and the same solid parts form the shadow-caster mesh, so thin wires, bars and window panes cost nothing in the shadow pass.
- `MeshValidate.odin`: `Mesh_Find_Problem` checks unit normals, tangents, UV range and winding. It lives in the engine so game code and tests share one definition of a sound mesh.

### 5.3 Terrain and scatter

- `Terrain.odin`: the height function is `base + amplitude * fbm(x, z) * smoothstep(plateau_radius, plateau_radius + blend, distance)`. The smoothstep keeps the base on a flat plateau that merges into hills without a crease. Heights use a domain-warped fbm blended with a ridged term for more natural slopes. Normals are central differences of the same function, so neighbouring chunks agree exactly along shared borders. The world is cut into 64 m chunks of 32 by 32 cells.
- `Scatter.odin`: decides where trees, rocks and bushes go, using a hash of the chunk coordinates and rules about slope and the plateau, so objects never sit on cliffs or inside the base.

### 5.4 Texture recipes

- `TextureRecipe.odin`: `Texture_Set_Bake` renders every recipe into one layer of three array textures: albedo (colour, stored sRGB), normal plus height, and roughness-metal-ambient-occlusion. Rendering goes directly into array layers, so no copies are made.
- The recipes live in `Shaders/Recipes/` (Asphalt, Bark, BirchBark, Camo, Canvas, Concrete, Dirt, Glass, Grass, Leaves, Needles, PaintedMetal, Rock, Rubber, RustedMetal, Sand, Skin, Wood). Each defines `recipe_surface`, and the shared `BakeMain.glsl` turns it into the three maps.
- Textures are **tileable by construction**: the noise lattice coordinates are wrapped modulo the period before hashing, so `f(p + period) = f(p)` exactly. Higher octaves double the frequency and the period together. `Tests/TextureCheck` verifies tiling exactly (8,318 checks) with a special probe mode that outputs `|recipe(uv) - recipe(uv + whole tiles)|`, which must be zero.
- Normal maps are derived from the height field with a Scharr 3 by 3 gradient (weights 3, 10, 3), which is more rotation-invariant than central differences. A negative Laplacian of height also gives a cavity term that darkens crevices.
- Noise upgrades used inside recipes: domain warping (fbm sampled at a point displaced by other fbm fields, which removes the grid look), ridged noise (`1 - |n|`, squared, for creases) and billow noise (`|n|`, for rounded lumps), and Worley (cellular) noise for leaves, needles and stones.
- Triplanar mapping (`Shaders/Include/Triplanar.glsl`) is used for deformed objects and terrain: project the texture along x, y and z and blend by `|n|^4`. No UVs are needed and deformation cannot stretch the texture. Projections with weight under 3% are skipped, which cut the geometry pass from 11.4 to 5.4 ms at 1440p with no visible change.

---

## Part 6. The renderer (`Engine/Render` and `Shaders/`)

### 6.1 Why deferred

Rendering is **deferred**: first every object writes its surface information (colour, normal, roughness, metalness, emission, occlusion and a "lighting model id") into several hidden images collectively called the **G-buffer**. Then lighting is computed once per screen pixel. Benefits: many lights are cheap, many illumination models can coexist (the model id is stored per pixel), and shader complexity stays bounded. Cost: no hardware MSAA, so FXAA is used for edges.

G-buffer layout: sRGB 8-bit (albedo plus model id), 16-bit float (octahedral-encoded normal, roughness, metallic), 16-bit float (emission, occlusion) and a 32-bit float depth. World position is rebuilt from depth, so it is never stored.

Octahedral normals: project the unit sphere onto an octahedron `|x|+|y|+|z| = 1`, fold the lower half outward, store two numbers. Precision is uniform with no singular direction.

### 6.2 The frame, in order (`Renderer.odin: Renderer_Render`)

1. **Sky look-up table** (`SkyLut.odin`, `SkyLutPass.glsl`): the atmosphere is expensive, so it is computed once per frame into a 192 by 128 table over azimuth and elevation, with resolution concentrated near the horizon.
2. **Shadows** (`ShadowMap.odin`, `Shadows.odin`, `SpotShadows.odin`): three cascades for the sun, plus depth maps for up to four spotlights.
3. **Geometry pass** (`Scene.odin`, `Material.odin`, `Mesh.odin`, `Geometry.glsl`): draws every item into the G-buffer. Frustum culling (`Culling.odin`) skips what the camera cannot see.
4. **Ambient occlusion** (`Ssao.odin`, `PostSsao.glsl`).
5. **Lighting** (`Light.odin`, `Illumination.odin`, `DeferredBase.glsl`, `DeferredLight.glsl`): the sun, sky ambient and emission in one full-screen pass; every point, spot and area light is an additive "proxy volume" (a sphere of the light's range drawn with front faces culled, so the camera may stand inside it).
6. **Particles** (`ParticlePass.odin`, `Particles.glsl`).
7. **Bloom** (`Bloom.odin`, `PostBloom.glsl`).
8. **Tonemap, grade, light shafts** (`PostTonemap.glsl`), then **FXAA** (`PostFxaa.glsl`).
9. **HUD** (`Hud.odin`, `Hud.glsl`): text and rectangles on top.

### 6.3 Shadows in detail

- **Cascaded shadow maps**: split the view frustum with the "practical" scheme (a 0.75 blend of logarithmic and uniform splits). Each slice is fitted with an orthographic box around its bounding sphere so the size is constant when the camera turns, and the box centre moves in whole texels so shadows do not shimmer. Three 2048 by 2048 cascades in a depth array.
- Lookup chooses the cascade by view depth, pushes the sample along the normal by a texel or two to remove "acne" (self-shadow speckles), and averages 12 hardware depth comparisons on a Vogel spiral (golden-angle disc) rotated per world position by a hash, so banding becomes fine stable noise. Farther cascades get a slightly larger filter radius because each texel covers more world.
- **Spot shadows**: a perspective depth map along the light axis (field of view is twice the outer cone angle plus 6 degrees). Perspective depth is non-linear, so instead of a fixed bias the lookup point is pushed along the normal by an amount that grows with distance and surface tilt.
- **Contact shadows**: an 8-step screen-space march toward the sun adds small-scale shadow near contact points.
- **Shadow proxies**: props (trees, rocks) have a detailed mesh for the camera and a roughly 50-triangle proxy for the shadow pass that draws the same instances. A shadow is only a silhouette, so this cut the shadow pass from 14 to 2.4 ms.

### 6.4 Illumination models (`Shaders/Include/Brdf.glsl`)

Each material picks one model, stored in the G-buffer:

- **Lambert**: diffuse `albedo / pi`.
- **Phong**: specular lobe `cos^n(R.V)` normalised by `(n+2)/2pi`.
- **Blinn-Phong**: lobe `cos^n(N.H)` normalised by `(n+8)/8pi`, using the half vector.
- **Oren-Nayar**: rough matte diffuse (cloth, concrete) with terms A and B depending on roughness and the angle between light and view around the normal.
- **Cook-Torrance (GGX)**: the physically based default. `f = diffuse + D*V*F`, where D is the GGX distribution, V the height-correlated Smith visibility and F Schlick's Fresnel `F0 + (1-F0)(1-v.h)^5`, with `a = roughness^2`. The diffuse part uses `(1-F(n.l))(1-F(n.v))`, because a white-furnace test showed the `(1-F(v.h))` form exceeds energy conservation at grazing views and the product form also keeps the BRDF reciprocal.
- **Subsurface** (skin): Cook-Torrance dielectric with a wrapped cosine `(n.l + w)/(1 + w)` so light reaches slightly past the terminator.

A valid BRDF is non-negative, reciprocal (`f(l,v) = f(v,l)`) and conserves energy (its integral against cosine is at most 1). `Tests/RenderCheck` verifies these properties with over 318,000 checks.

### 6.5 Light sources (`Lighting.glsl`, `Light.odin`)

Directional (sun and moon), point, spot and area lights (a sampled rectangle, treated as an N by N grid of Lambertian emitters). Falloff is inverse-square times the window `(1 - (d/range)^4)^2` (Karis 2013), which reaches exactly zero at the range with zero slope. Spot cones use a squared smooth ramp between the outer and inner cosines.

### 6.6 Ambient and indoor light

- Ambient is analytic, not cube-maps: a sky gradient plus the split-sum environment BRDF fit (Karis), so specular ambient is `radiance * (F0 * scale + bias)`.
- Indoors, direct light is exact (sun with shadows, lamps with shadow maps, emissive panels) but indirect light is approximated: ambient inside a room is halved and its normal is blended 60% toward up (a ceiling would otherwise face the dark ground and be black). Lamps light only the room they are in (a room box test in `Interior.glsl`). Real global illumination is impossible on this platform; this is the cheap substitute.

### 6.7 Sky, atmosphere, clouds

- `Atmosphere.glsl`: single scattering (Nishita). Along the view ray, accumulate `density * transmittance(sample to sun) * transmittance(sample to eye)`. Rayleigh scattering (molecules, proportional to 1/wavelength^4, which makes the sky blue and sunsets red) uses phase `3/16pi (1 + cos^2)`; Mie scattering (haze, strongly forward) uses the Cornette-Shanks phase. Transmittance is `exp(-integral of extinction)` (Beer-Lambert). Densities fall off exponentially with height (scale heights 8 km and 1.2 km). Because single scattering makes the horizon too yellow, 35% of a gradient colour is blended in as a multiple-scattering fill.
- `Sky.glsl`: sky colour, sun and moon discs, stars, and two cloud planes (cumulus at 1,500 m and cirrus at 7 km). Cloud density is warped fbm scrolled by wind, with the detail layer drifting faster than the shape layer so the form slowly changes; clouds are self-shadowed with a silver lining and moonlit at night.
- **Aerial perspective (fog)**: surface colour is `mix(haze, lit, T)` with `T = exp(-k d)`, `k = 0.00035` per metre (about 3 km visibility). The haze colour uses only the smooth atmosphere, not stars: an earlier bug let a horizon star colour the fog, painting a bright vertical line down every surface in its screen column at night. Fix: stars and discs belong to the sky pass alone.
- `TimeOfDay.odin` and `Daylight.odin` (in `Game/Gameplay`): sun path from latitude, declination and hour angle (east = -cos(delta) sin(h); up = sin(phi) sin(delta) + cos(phi) cos(delta) cos(h)), moonlight and the exposure curve. **Eye adaptation**: exposure multiplies radiance before tonemapping and rises as the sun sinks (`10^darkness`), so night stays readable.

### 6.8 Post-processing

- **Bloom**: the HDR image is downsampled through five half-resolution levels with a 13-tap filter (this removes flicker from tiny bright pixels), then tent-filtered and added back up. A soft-knee threshold keeps only radiance above 1.2. Bloom is added before tonemapping so the halo is tonemapped with the scene.
- **SSAO**: 12 cosine-distributed hemisphere samples, a range check to avoid darkening silhouettes, a per-pixel rotated pattern and an exact 4 by 4 blur; computed at half resolution with a depth-aware upsample. It scales only the ambient term.
- **Light shafts**: a screen-space march toward the sun counting open-sky samples with `0.93^i` weights.
- **Screen-space reflections**: reprojecting last frame's image, limited to roughness under 0.25, 16 steps.
- **Tonemap**: ACES filmic (Narkowicz fit) `x(2.51x+0.03)/(x(2.43x+0.59)+0.14)`, then split-toning grade (cool shadows, warm highlights, a gentle S curve) and a triangular-PDF dither of one 8-bit step to remove banding in dark skies.
- **FXAA** runs after tonemapping because it works on perceptual brightness.

### 6.9 Particles

`ParticlePass.odin` and `Particles.glsl` draw camera-facing quads whose shape is a soft disc eroded by four octaves of noise that drifts with age, so a puff grows ragged and dissolves rather than fading evenly. Smoke is alpha blended and sorted back to front (blending is not commutative) and lit as if each quad were a sphere. Fire is additive in HDR with a black-body ramp whose values above 1 feed the bloom. Both read scene depth: a fragment behind a surface is discarded and one within 0.6 m in front is faded (a "soft particle"), so puffs never cut hard lines through the ground. Dithered "screen-door" transparency is also used for some smoke on regular geometry.

### 6.10 Instancing, culling, performance

- Repeated props are drawn instanced from one buffer per kind. Instance counts live in a heap cell shared between an owner and its shadow proxies (an earlier pointer to the owner dangled when structs were copied).
- Frustum culling uses the Gribb-Hartmann method: each of six planes is the fourth row of the view-projection matrix plus or minus another row. A sphere is outside if farther than its radius behind any plane; a box is outside if its most-forward corner is behind a plane.
- Measured budget: 1080p, 16.7 ms for 60 fps. Final GPU time is 11.28 ms: geometry 4.43, lighting 2.76, shadows 1.56, post 1.28, SSAO 1.23, sky table 0.02. Optimisations are logged in `Docs/Optimization.md`: per-cascade shadow culling, tree level of detail beyond 110 m, a 16-entry gradient table for noise, half-resolution SSAO, fewer cloud octaves, a uniform-upload cache and a distance-squared collision reject.

---

## Part 7. World rules (`Engine/World`)

Pure logic with no drawing, so it is unit-tested (58 tests).

- `Solid.odin` and `Collision.odin`: world obstacles are **oriented boxes** (exact at any heading). The player is a **capsule controller** with slide along walls, step-up over small ledges and ground snapping. Crouching shortens the capsule so it fits under beams and stands up only where there is room. A distance-squared test rejects far solids before any rotation maths.
- `Raycast.odin`: rays against boxes, spheres, capsules and terrain; ballistic stepping for rockets, grenades and shells; cone spread for inaccurate shots; and `Line_Of_Sight_Clear`, used so that doors, vehicles, hacking and rescue all require the player to actually see the thing.
- `Chunks.odin`: streaming with hysteresis. Chunks load within radius 4 and unload beyond radius 6 so walking along a boundary never causes thrashing; at most one chunk is built per frame, nearest first, so streaming never hitches the frame (a chunk builds in about 0.5 ms).
- `Ladder.odin`: the climbing state machine: mount, eased climb at 1.1 m/s, step over at the top, step off the bottom, jump off, grab from the top with E, and a hold-off timer against instantly re-grabbing.
- `GroundVehicle.odin`: throttle, brake, drag, bicycle steering (wheeled) or pivot steering (tracked), power that fades toward top speed, hull-versus-solid blocking and terrain pitch and roll.
- `Aircraft.odin`: the helicopter flight model: rotor spool-up gating lift, collective climb and hover, pitch, roll and yaw, wall blocking while low walls are cleared, touchdown and a reported impact speed for hard-landing damage.
- `Spring.odin`: a **critically damped spring** with the exact solution `x(t) = (c1 + c2 t) e^(-wt)`; it returns fastest without overshoot and is independent of the time step. Used for hit reactions, vehicle suspension and view motion.

---

## Part 8. Audio (`Engine/Audio` and `Game/Sandbox/Sound*`)

- `Synth.odin`: builds every sound from maths: noise bursts shaped by envelopes for gunshots and explosions, filtered noise for wind and footsteps, tone pairs for beeps and the alarm, detuned oscillators for engines and rotor beats, plus thuds, crickets and bird calls (`Synth_Thud/Beep/Wind/Crickets/Bird`).
- `Mixer.odin`: up to 48 simultaneous voices with resampling (pitch shift), **equal-power panning** (left and right gains `cos` and `sin` of the pan angle, so loudness stays constant across the arc), a `tanh` soft limiter so loud explosions never clip, and looped voices closed with a crossfade at the seam so loops have no click.
- `Device.odin`: opens the speakers through miniaudio and feeds it from `Mixer_Fill`.
- `Game/Sandbox/Sound.odin`: the sound bank and `spatialize`, which turns a world position into pan and volume (direction relative to the listener, distance rolloff).
- `Game/Sandbox/SoundFeedback.odin`: watches the game each frame and fires cues on **changes** rather than every frame (a `Feedback_State` remembers the previous frame): taking a hit, dying, confirming a hit on an enemy, switching weapons, emptying a magazine, jumping and landing (volume by fall speed), hack beeps that speed up and rise in pitch with progress, toggling the flashlight, map and binoculars, boarding a vehicle, enemy footsteps within earshot (every 2.1 m walked, within 35 m) and an enemy falling. **Ambience**: wind all day, crickets that fade in with darkness, and bird calls at random places around the player in daylight. A tank cannon sounds like the launcher; other vehicle guns rattle like a rifle.
- `Tests/AudioCheck` mixes every sound offline and opens the real device (79 checks).

---

## Part 9. Content tables (`Game/Materials`, `Game/Catalogue`)

- `Game/Materials/Materials.odin`: one row per surface material, tying a name to its recipe and illumination model (`Materials_Bake` bakes all of them at start-up). Adding a material means adding a recipe file, one enum entry and one table row; a Showroom sphere appears automatically and `TextureCheck` verifies that it tiles.
- `Game/Catalogue/`: every object is a **table of parts**:
  - `Buildings.odin`: barracks, HQ, hangar, mess hall, generator shed, fuel tanks, water tower, watchtower, guard post, bunker, helipad, radio mast, radar station. Several are **hollow** with furnished interiors (bunks, tables, ceiling lamps) built by `add_walled_room`, with door openings. Watchtower ladders are declared here (`Catalogue_Ladders`).
  - `Fortifications.odin`: chain-link fence with razor wire, T-walls, Hesco barriers, sandbags, gate, checkpoint barrier. A thin fence uses an invisible collision-only box.
  - `Props.odin`: crates, barrels, pallets, tents, camouflage nets, floodlights, signs, flag.
  - `Vehicles.odin`: articulated specs (hull, wheel mounts, tracks, turret, gun, seat, handling) for jeep, cargo truck, armored carrier, tank and helicopter (main and tail rotors).
  - `Doors.odin`: door specs and leaf meshes (plank, sheet, mesh gate).
  - `Paving.odin`: roads, parade ground, walkways, apron and lawns as flat, non-solid slabs.
  - `Objects.odin`: the master `Object_Kind` enum and dispatch, `Catalogue_Info` (size and collision boxes without building meshes), `Catalogue_Build_Shadow`.
- `Catalogue_test.odin` checks each object against a realistic real-world size range (a barracks must be building-sized, a jeep car-sized), plus mesh validity, grounding, triangle budget, determinism and collision. Paving is part of the same tests because it is just more catalogue objects.

---

## Part 10. The base (`Game/Base`)

- `Layout.odin`: the plan. A fenced circular compound of radius 62 m on the plateau: the perimeter is **128 equal slots** (one watchtower slot, three gate slots, the rest fence) so it is closed by construction. The command area (HQ, three barracks at x = -44 and z of -24, -2 and 20, mess hall, generator, fuel, water tower, radar, mast, bunkers, T-walls) is north and west; the airfield (hangar, helipad with a helicopter) is east; the motor pool (jeeps, trucks, carriers, tanks under a camouflage net) is by the gate; plus a supply yard, tents, floodlights and the gate approach. Roads, a parade ground, walkways, an apron and two lawns come from `add_paving`. A fixed plan is used with seeded jitter only for loose props and parked vehicles.
- `Footprint.odin`: oriented-rectangle footprints. Overlaps are detected with the **separating axis theorem**, and the layout test fails if anything overlaps, except a helicopter on its pad and a camouflage net over what it shelters. It also converts placements into rotated collision solids and ladders.
- `BaseScene.odin`: turns the layout into GPU data: one instanced draw per object kind and material, plus shadow versions.
- `Doors.odin`, `DoorRender.odin`: hinged doors with open/close animation, a leaf collision solid, "nearest door" lookup, and a gate whose two leaves toggle together. E opens or closes a door.
- `InteriorLights.odin` and `NightLights.odin`: ceiling lamps in buildings (lighting only their own room) and floodlight spots, tower and guard-post lamps and door lights that fade with darkness.
- Tests (`Game/Base`, 19) check the layout, collisions, reachability (the player can walk from outside to every objective) and that every object blocks except a short listed few.

---

## Part 11. People and weapons (`Game/Characters`, `Game/Weapons`)

- `Skeleton.odin`: a humanoid defined by joint **positions**, not rotation hierarchies. The trunk is a rigid leaning rod; legs and arms are placed by IK. Every pose preserves every bone length, which a test sweeps over speeds, phases, aiming, crouch and lean.
- `Ik.odin`: **two-bone inverse kinematics** with a pole vector. The two bones and the root-to-target line form a triangle with sides upper, lower and `d`; the law of cosines gives the angle at the root, `cos(a) = (upper^2 + d^2 - lower^2)/(2 upper d)`. `d` is clamped to `[|upper - lower|, upper + lower]`, so an unreachable target gives a straight limb pointing at it.
- `Gait.odin`: foot paths without skating. During stance (fraction `duty` of the cycle) a foot slides back at exactly the body speed, so it stays fixed on the ground; during swing it eases forward along a raised arc. Cycle time is `T = stride / (duty * speed)`. Pelvis height is derived from the stride so planted feet are always reachable; the walking bob falls out of the same formula.
- `Soldier.odin`: body-segment part tables worn through a **palette**; five palettes give five variants (rifleman, officer, sniper, guard, enemy). Segment meshes are authored along +Y from their proximal joint and placed by a frame built from the bone direction.
- `Character.odin`: animation state, aiming and the hit reaction through the spring.
- `CharacterRender.odin`: one instanced mesh per variant, segment and material, so any number of soldiers costs the same number of draws.
- `Weapons.odin`: weapon models (rifle, sniper rifle, pistol, rocket launcher, silenced pistol, grenade).
- `Behavior.odin`: weapon stats and state. Examples: rifle 22 damage, 0.1 s between shots, 30-round magazine, 2 s reload, 300 m range, automatic; sniper 90 damage, 1.2 s, 5 rounds, 800 m; pistol 18 damage; rocket launcher 160 damage with a 5 m blast and 45 m/s projectile; grenade 120 damage with a 6 m blast; the silenced pistol (key 6) has no flash and is heard only from 9 m. `Weapon_Update` carries the fire interval exactly at any frame rate by adding the interval to the cooldown instead of resetting it.

---

## Part 12. Gameplay rules (`Game/Gameplay`, `Game/Vehicles`)

- `Player.odin`: movement and look. Walk 4 m/s, sprint 6.5 m/s, eye height 1.65 m (0.95 m crouched), 100 health.
- `Health.odin`: damage with **hit-zone multipliers** (a headshot is worth more than a limb) and regeneration of 8 per second after 5 seconds without being hit.
- `Enemy.odin`: soldier health 100, hit shapes (head, torso, limbs) and `Enemy_Raycast`. Enemies fire every 0.35 s for 4 damage, slower than the rifle so a fight is survivable, and turn at 3.5 rad/s so flanking works.
- `EnemyAi.odin`: a state machine: patrol, spot, chase, shoot, search, dead. Senses: sight up to 50 m inside a 100-degree cone, awareness of anything within 5 m from any direction, a wall or hill between eye and target blocks sight, heard shots alert enemies within 70 m. After opening fire an enemy needs 0.6 s to settle aim; it attacks within 30 m (and only gives up beyond 36 m, so the state does not flicker).
- `Stealth.odin`: visibility depends on stance and speed (crouch 0.55, standing still 0.8, walking 1.0, sprinting 1.25) and noise radius (sprint 18 m, walk 9 m, crouch-walk 3 m, shots 70 m, silenced 9 m).
- `Battle.odin`: the combat simulation: hitscan and projectiles, effects, grenade bounces (restitution, friction, fuse), explosions with distance falloff, squad shouts (a soldier who spots trouble alerts mates within 22 m), discovering bodies, running enemies over with a vehicle, regeneration.
- `Target.odin`: destructible targets (the radar dish, fuel tanks) damaged by bullets, blasts and shells.
- `Pickup.odin`: ammunition dropped by dead soldiers, medkits in buildings and dropped weapons, collected by walking over them.
- `Game/Vehicles/Vehicle.odin`: vehicle entities: boarding range and exit spot, turret slew, cannon and machine gun, suspension through critically damped pitch and roll springs (braking noses down, turns lean out). `VehicleRender.odin` draws the hull, turret, gun, instanced steered wheels and moving tank track links.

---

## Part 13. The mission (`Game/Mission`)

- `Mission.odin` is a **pure state machine**. It never touches the world. It is fed an `Observation` ("the player is within reach of the terminal and pressing E", "the radar is destroyed", "the player is on the extraction beacon") and updates its objectives. This makes it easy to unit-test (16 tests).
- Objectives for the day mission *Rescue*: enter the compound (the gate), hack the HQ computer (hold E for 2.5 s; progress drains twice as fast as it builds if you let go), destroy the radar, rescue the hostage (E near them) and reach the extraction beacon. Enter first; hack, radar and hostage in any order; extraction last. The second mission *Night Raid* replaces the hostage with blowing up two fuel tanks, starts at 21:30 and keeps its own best time.
- `SecurityCamera.odin`: sweeping cameras with a range and line-of-sight test and a suspicion timer. Seen long enough raises the base-wide alarm (`Alarm_Raise`), which calls reinforcements. Hacking the computer disables cameras. Cameras can also be shot.
- `Save.odin`: a plain-text save format with a damage-tolerant parser: checkpoints after each objective and a best-time record per mission. `--continue` resumes.

---

## Part 14. The Sandbox: where everything meets (`Game/Sandbox`)

The sandbox is the playable level and the only place where the Game layer's pieces are wired together.

- `Sandbox.odin`: owns the scene: terrain, chunk streaming, the base, the day cycle, camera presets for `--view`, the draw list and the renderer call. Prop culling per chunk (in view, or near enough to cast a shadow into view) lives here.
- `Play.odin`: the "play mode" layer: garrison of 12 soldiers, input mapping, the demo bot, effects, the held weapon and body, head bob and weapon sway, the flashlight (a spot light at the eye), the pause menu, door interaction, and the HUD. `play_items` is the function that collects every character, vehicle, door and effect into draw lists each frame.
- `MissionPlay.odin`: connects the mission to the world: places the terminal, radar dish, hostage and extraction beacon; builds the `Observation` each frame; shows hack and rescue prompts, the briefing and completion screens; moves the rescued hostage. The hostage stands in the middle barracks and, once rescued, walks behind the player (warping if left too far behind and hiding while the player is in a vehicle).
- `SecurityCameras.odin`: puts cameras on towers, the HQ and guard posts; sends reinforcements on alarm.
- `Driving.odin`: boarding with E, WASD to drive, mouse aims the turret, V toggles seat view and chase view, the helicopter controls (Space up, Ctrl down, W/S pitch, A/D turn, Q/E strafe), hard-landing damage and the altitude and rotor HUD.
- `Optics.odin`: binoculars (B, 12-degree zoom, range readout), the sniper scope (right mouse, 4x with a circular mask) and the **tactical map** (M): slate panel, metre grid, ground discs, paving, outlined and named buildings, soldiers, cameras, vehicles, objective markers with labels on dark backgrounds, the current goal pulsing with its distance, scale bar, north arrow and legend.
- `Compass.odin`: the heading strip with the objective marker. `FlyCamera.odin`: the free camera (Tab). `LadderHands.odin`: hands and sleeves gripping rungs hand over hand.
- `Particles.odin`, `Props.odin`, `Trees.odin`, `WorldChunks.odin`: smoke and dust puffs and bullet holes; props built from primitives with shadow proxies; four tree species (oak, pine, birch, cypress) with per-tree height, width, lean and tint, wind sway as a cantilever bending by height squared plus leaf flutter, and far-tree level of detail; a chunk = terrain mesh plus scatter.
- `SaveGame.odin`: writes and restores checkpoints.
- `Sound.odin` and `SoundFeedback.odin`: see Part 8.

---

## Part 15. Showroom, tools and tests

- `Game/Showroom`: `Showroom.odin` and `Gallery.odin` (a field of material spheres, primitives plain and deformed, light types), `CatalogueView.odin` (`--scene catalogue --object <Name>`), `SoldierLineup.odin` (`--scene soldiers`).
- `Tools/CheckAll.sh` runs every unit test package, every GL check and both scripted playthroughs. `Tools/ToPng.sh` converts screenshots.
- Unit tests, written next to the code as `*_test.odin`: 281 in 13 packages (GPU 3, Procedural 52, Render 14, World 58, Audio 8, Catalogue 5, Base 19, Characters 26, Weapons 11, Gameplay 55, Vehicles 11, Mission 16, Sandbox 3).
- GL checks that need a real window: `GpuCheck` (30), `TextureCheck` (8,318), `RenderCheck` (318,567), `WindowCheck` (141), `AudioCheck` (79).
- **Autoplay**: `--autoplay` runs a script that teleports through every step of a mission and prints each completed objective. `CheckAll.sh` expects 5 of 5 for both missions: a full end-to-end test.

---

## Part 16. How to play

- Move WASD, look with the mouse, Shift sprint, C crouch, Space jump, left mouse fire, R reload, keys 1 to 6 choose weapons (6 is the silenced pistol), right mouse aims (sniper scope), F flashlight, B binoculars (Z/X zoom), M tactical map, E use (doors, hacking, rescue, vehicles, ladders), Tab fly camera, F11 fullscreen, F9 free the cursor, Esc pause (then Q quits), Enter respawn.
- Vehicles: E boards, WASD drives, mouse aims the turret, V changes view, Space brakes. Helicopter: Space climb, Ctrl descend, W/S pitch, A/D turn, Q/E strafe, land to get out.
- Watchtowers hold snipers; walk to a tower's ladder and push W or press E to climb.
- The mission: get inside the compound, hack the HQ computer, destroy the radar, rescue the hostage in the middle barracks, reach the green beacon. Dead soldiers drop ammunition, medkits wait in buildings, an alarm turns out reinforcements. A briefing shows first; Enter starts; after completing, R plays again, N switches to the night mission.

---

## Part 17. Follow one event end to end

*The player presses E next to the hostage.*

1. `Input` records the key in `Engine/Platform`; `Loop` calls the sandbox update.
2. `MissionPlay` checks the player is within `HOSTAGE_REACH_METERS` of the hostage and has line of sight (`Line_Of_Sight_Clear` in `Engine/World/Raycast.odin`), and packs this into an `Observation`.
3. `Mission_Update` (pure rules) sees "in reach and interact pressed" and completes `Rescue_Hostage`, which also triggers a checkpoint save through `SaveGame`.
4. `MissionPlay` marks the hostage rescued; `update_hostage` makes the character follow the player using the same `Controller_Step` collision as the player.
5. `play_items` appends the hostage to the list of characters; `Character_Renderer_Items` batches them per variant; the renderer draws them into the G-buffer, lights them with the sun and shadows and adds bloom and tonemapping.
6. `SoundFeedback` and the HUD present the confirmation and the next objective.

The same chain (input, observation, pure rules, state change, draw list, render, sound) holds for every feature.

---

## Part 18. Important design decisions and lessons, in plain words

- **OpenGL 4.1** because it is the macOS ceiling; switching to Metal or Vulkan would mean rewriting the backend for no feature the game needs.
- **Deferred shading** for many lights and many surface models; FXAA instead of MSAA.
- **No compute shaders**, so baking and filtering use full-screen fragment passes.
- **Exact tests over statistical ones**: texture tiling is tested by direct comparison; a "seam versus neighbour" statistic gave false failures for sharp patterns.
- **Instancing with shadow proxies** because shadows only need silhouettes.
- **Hit reactions and suspension use the exact critically damped spring** so they are stable at any frame rate and never overshoot.
- **Characters as joint positions plus IK**, not rotation hierarchies, because it guarantees bone lengths and feet that never slide.
- **Pure state machines** (mission, enemy AI, ladders) separated from drawing so they can be tested without a window.
- **Paving as catalogue objects**, not painted terrain, so roads obey the same size, footprint and collision tests and the map reuses them.
- **Window cursor click-to-capture**, found necessary when a permanently captured cursor made moving or resizing the window impossible.
- **Bug stories worth remembering**:
  - The night "vertical line": the fog colour sampled the whole sky including a horizon star, so one star painted a bright column across every surface. Found by bisecting draw items, lights and effects. Fixed by giving fog only the smooth atmosphere.
  - A slice literal returned from a procedure dangled and crashed, so `Part.deformers` is a fixed inline array.
  - A pointer from a shadow proxy to its owner dangled when a struct was copied by value, so instance counts live in a shared heap cell.
  - The hostage once disappeared because a debug switch left over from the night-line investigation (`if false do ...`) kept it out of the draw list; the switch was removed.
  - A windowed-size test failed because GLFW applies limits only to mouse drags, so the test now checks robustness instead of the limit.

---

## Part 19. Key numbers to remember

- Layers: 6 engine layers plus Audio, then the Game.
- Source: 168 Odin files (about 20,000 lines), 59 GLSL files (about 2,250 lines).
- Objects: 33 military catalogue objects plus paving; 18 procedural materials; 5 soldier variants; 4 tree species; 6 weapons; 4 ground vehicles plus a helicopter.
- Rendering: 3 shadow cascades at 2048 squared, up to 4 spot shadows, 6 illumination models, G-buffer of 4 targets, GPU time 11.28 ms at 1080p (budget 16.7 ms).
- World: 64 m chunks, base radius 62 m, 128 perimeter slots, 12 enemy soldiers.
- Audio: 48 mixer voices, all sounds synthesised.
- Verification: 281 unit tests, 30 + 8,318 + 318,567 + 141 + 79 GL and audio checks, two scripted playthroughs each completing 5 of 5 objectives.
- Deliverables: report (27 pages), Equation Guide (7 pages), slides (10 pages and a PPTX) under `Docs/Deliverables`.
