# Features: where is it implemented?

| Feature | File : proc |
|---|---|
| Window + GL 4.1 context | `Engine/Platform/Window.odin` : `Window_Create` |
| Frame clock (capped delta) | `Engine/Platform/Clock.odin` : `Clock_Tick` |
| Keyboard / mouse polling | `Engine/Platform/Input.odin` : `Input_Update`, `Input_Key_Down` |
| GL error checking | `Engine/GPU/Debug.odin` : `GL_Check` |
| Shader source with `#include`, `#stage`, defines | `Engine/GPU/ShaderSource.odin` : `Shader_Source_Load` |
| Shader compile/link, uniforms | `Engine/GPU/Shader.odin` : `Shader_Create`, `Shader_Set` |
| Vertex/index/uniform buffers | `Engine/GPU/Buffer.odin` : `Buffer_Create` |
| Vertex arrays, instancing streams | `Engine/GPU/VertexArray.odin` : `Vertex_Array_Create` |
| Textures: 2D, array, 3D, cube, formats, mips | `Engine/GPU/Texture.odin` : `Texture_Create`, `Texture_Upload`, `Texture_Generate_Mips` |
| Texture unit allocation | `Engine/GPU/Texture.odin` : `Texture_Bind_Next` |
| Samplers, anisotropy, shadow compare (cached) | `Engine/GPU/Sampler.odin` : `Sampler_Get` |
| Extension / anisotropy capability query | `Engine/GPU/Capabilities.odin` |
| Framebuffers, MRT, resize | `Engine/GPU/Framebuffer.odin` : `Framebuffer_Create`, `Framebuffer_Resize` |
| Uniform blocks (std140) | `Engine/GPU/UniformBlock.odin` |
| Fullscreen triangle pass (bakes, post) | `Engine/GPU/FullscreenPass.odin` |
| Screenshot (BMP) | `Engine/GPU/Screenshot.odin` : `Screenshot_Save` |
| Integer hash (PCG) | `Engine/Procedural/Hash.odin` : `Hash_U32`, `Hash_Lattice_3` |
| Gradient noise, fbm | `Engine/Procedural/Noise.odin` : `Noise_Gradient_3`, `Noise_Fbm_3` |
| CPU mesh type, bounds | `Engine/Procedural/Mesh.odin` : `Mesh`, `Mesh_Bounds` |
| Primitives: box, sphere, cylinder, cone, capsule, torus, wedge (UV + tangents) | `Engine/Procedural/Primitives.odin` : `Box_Create`, `Sphere_Create`, ... |
| Merge parts under a transform (normal matrix, mirror-safe) | `Engine/Procedural/MeshBuilder.odin` : `Mesh_Append` |
| Deformers: noise displace, taper, twist, bend, bulge | `Engine/Procedural/Deform.odin` : `Mesh_Deform` |
| Upload a CPU mesh to the GPU | `Engine/Render/Mesh.odin` : `Mesh_Upload`, `Mesh_Draw` |
| Render into array-texture layers | `Engine/GPU/Framebuffer.odin` : `Framebuffer_Set_Layers` |
| Read an array layer back | `Engine/GPU/Texture.odin` : `Texture_Read_Layer` |
| Periodic gradient noise, fbm, Worley (GLSL) | `Shaders/Include/Noise.glsl` |
| Surface recipe contract + bake pass (albedo, normal+height, roughness/metal/AO) | `Shaders/Include/Surface.glsl`, `Shaders/Include/BakeMain.glsl` |
| Procedural texture bake into material arrays | `Engine/Procedural/TextureRecipe.odin` : `Texture_Set_Bake` |
| Bind a baked set to a shader | `Engine/Render/Material.odin` : `Texture_Set_Bind` |
| Triplanar sampling + normal blend (GLSL) | `Shaders/Include/Triplanar.glsl` |
| Material list + recipe table (concrete, camo, rust, sand, canvas, grass, dirt, rock) | `Game/Materials/Materials.odin` : `Materials_Bake` |
| One recipe per material | `Shaders/Recipes/*.glsl` |
| Octahedral normal encoding (G-buffer) | `Shaders/Include/Gbuffer.glsl` : `oct_encode`, `oct_decode` |
| Read the G-buffer, rebuild position from depth | `Shaders/Include/GbufferRead.glsl` : `gbuffer_read` |
| Illumination models: Lambert, Phong, Blinn-Phong, Oren-Nayar, Cook-Torrance GGX, subsurface | `Shaders/Include/Brdf.glsl` : `brdf_evaluate`, `light_cosine`; `Engine/Render/Illumination.odin` |
| Light sources: directional, point, spot, area (sampled rectangle) | `Shaders/Include/Lighting.glsl` : `shade_light`; `Engine/Render/Light.odin` |
| Sky gradient + sun disc, sky ambient | `Shaders/Include/Sky.glsl` |
| Image-based ambient (split-sum environment BRDF) | `Shaders/Include/Ambient.glsl` : `ambient_light` |
| ACES tonemap, vignette, sRGB | `Shaders/Include/Tonemap.glsl`, `Shaders/PostTonemap.glsl` |
| FXAA | `Shaders/PostFxaa.glsl` |
| Camera, frustum slices | `Engine/Render/Camera.odin`, `Engine/Render/Shadows.odin` : `Frustum_Slice_Corners` |
| Cascade splits + fit (sphere bound, texel snapping) | `Engine/Render/Shadows.odin` : `Cascade_Splits`, `Shadow_Cascades_Fit` |
| Shadow map pass + uniforms | `Engine/Render/ShadowMap.odin` : `Shadow_Map_Render`, `Shadow_Map_Bind` |
| Shadow lookup (cascade pick, normal offset, PCF) | `Shaders/Include/Shadow.glsl` : `shadow_factor` |
| Deferred frame: shadow, geometry, lighting, post | `Engine/Render/Renderer.odin` : `Renderer_Render` |
| Geometry pass (writes the G-buffer) | `Shaders/Geometry.glsl` |
| Sun + ambient + sky fullscreen pass | `Shaders/DeferredBase.glsl` |
| Local lights as additive proxy volumes | `Shaders/DeferredLight.glsl` |
| Depth-only render into an array layer | `Engine/GPU/Framebuffer.odin` : `Framebuffer_Set_Depth_Layer` |
| Showroom (materials on primitives, deformed shapes, material spheres) | `Game/Showroom/Showroom.odin`, `Game/Showroom/Gallery.odin` |
| Gallery of primitives, plain and deformed | `Game/Showroom/Gallery.odin` : `Gallery_Create` |
| Hash-based scatter (trees, rocks, bushes) with slope and plateau rules | `Engine/Procedural/Scatter.odin` : `Scatter_Chunk` |
| Terrain height, plateau blend, chunk meshes | `Engine/Procedural/Terrain.odin` : `Terrain_Height`, `Terrain_Chunk_Mesh` |
| Terrain material blend by slope and height (GLSL) | `Shaders/Include/TerrainBlend.glsl` |
| Chunk streaming set with hysteresis | `Engine/World/Chunks.odin` : `Chunk_Stream_Update` |
| Frustum culling (sphere, box) | `Engine/Render/Culling.odin` : `Frustum_From_View_Projection`, `Frustum_Intersects_Aabb` |
| Sun path, sunlight, moonlight, sky gradient, eye-adaptation exposure | `Game/Gameplay/TimeOfDay.odin` |
| Hour to sun light + sky | `Game/Gameplay/Daylight.odin` : `Daylight_For_Hours` |
| Atmosphere scattering (Rayleigh + Mie) | `Shaders/Include/Atmosphere.glsl` : `atmosphere_radiance` |
| Sky look-up table (atmosphere cached per frame) | `Engine/Render/SkyLut.odin`, `Shaders/Include/SkyLut.glsl`, `Shaders/SkyLutPass.glsl` |
| Sky, sun and moon discs, stars | `Shaders/Include/Sky.glsl` : `sky_radiance` |
| Instanced meshes + shared-instance shadow proxies | `Engine/Render/Mesh.odin` : `Mesh_Upload_Instanced`, `Mesh_Upload_Instanced_Sharing`, `Mesh_Set_Instances` |
| GPU pass timers | `Engine/GPU/Timer.odin`, `Engine/Render/Renderer.odin` : `Renderer_Pass_Milliseconds` |
| Fly camera | `Game/Sandbox/FlyCamera.odin` |
| Props built from primitives and deformers (tree, rock, bush) + shadow proxies | `Game/Sandbox/Props.odin` |
| Chunk = terrain mesh + scatter | `Game/Sandbox/WorldChunks.odin` |
| Playable layer: garrison, input mapping, demo bot, effects, view weapon, HUD | `Game/Sandbox/Play.odin` |
| Bloom (13-tap down, tent up, soft-knee threshold) | `Engine/Render/Bloom.odin` : `Bloom_Render`; `Shaders/PostBloom.glsl` |
| Screen-space ambient occlusion (hemisphere, 4x4 noise + exact blur) | `Engine/Render/Ssao.odin` : `Ssao_Render`; `Shaders/PostSsao.glsl`; applied in `Shaders/DeferredBase.glsl` |
| The open-world scene (stream, gather, day cycle) | `Game/Sandbox/Sandbox.odin` |
| Frame loop, capture, benchmark | `Source/Loop.odin` |
| Flags: `--scene`, `--time`, `--capture`, `--benchmark` | `Source/Config.odin` |
| Parts and assemblies: primitive + deformers + transform + material + emission + solid, grouped per material, collision boxes | `Engine/Procedural/Assembly.odin` : `Assembly_Build`, `Assembly_Bounds` |
| Mesh validation (normals, tangents, uv, winding) | `Engine/Procedural/MeshValidate.odin` : `Mesh_Find_Problem` |
| The 33 military objects | `Game/Catalogue/Objects.odin` (enum + dispatch), `Game/Catalogue/Buildings.odin`, `Fortifications.odin`, `Vehicles.odin`, `Props.odin` |
| Object size and collision boxes without building meshes | `Game/Catalogue/Objects.odin` : `Catalogue_Info` |
| Shadow-caster meshes (solid parts only) | `Game/Catalogue/Objects.odin` : `Catalogue_Build_Shadow` |
| Footprints, overlap test (separating axis), rotated collision boxes | `Game/Base/Footprint.odin` |
| Base plan: perimeter ring, command area, airfield, motor pool, yard, camp, gate approach | `Game/Base/Layout.odin` : `Layout_Create` |
| Base ready to draw (instanced per object kind and material) | `Game/Base/BaseScene.odin` : `Base_Scene_Create`, `Base_Scene_Items`, `Base_Scene_Shadow_Items` |
| Catalogue viewer (`--scene catalogue [--object Name]`) | `Game/Showroom/CatalogueView.odin` |
| Sandbox camera presets (`--view base|gate|yard|airfield|command`) | `Game/Sandbox/Sandbox.odin` : `camera_for_view` |
| Critically damped spring (hit reactions) | `Engine/World/Spring.odin` : `Spring_Step`, `Spring3_Step` |
| Two-bone IK with pole vector | `Game/Characters/Ik.odin` : `Two_Bone_Ik` |
| Gait: stride, cadence, foot paths without skating | `Game/Characters/Gait.odin` : `Gait_Foot`, `Gait_Cycle_Seconds` |
| Humanoid skeleton and pose solver | `Game/Characters/Skeleton.odin` : `Pose_Solve`, `Rest_Pose`, `BONES` |
| Soldier variants (palettes), body-segment part tables, frames onto the skeleton | `Game/Characters/Soldier.odin` : `Soldier_Segment_Assembly`, `Segment_Matrix`, `Weapon_Matrix` |
| A character's animation state, hit reaction | `Game/Characters/Character.odin` : `Character_Step`, `Character_Hit`, `Character_Pose` |
| Instanced rendering of any number of soldiers | `Game/Characters/CharacterRender.odin` : `Character_Renderer_Items` |
| Weapon models | `Game/Weapons/Weapons.odin` : `Weapon_Build` |
| Soldier line-up scene (`--scene soldiers`) | `Game/Showroom/SoldierLineup.odin` |
| Scene description handed to the renderer (`Draw_Item`, `Frame`, `Sky`) | `Engine/Render/Scene.odin` |
| Capsule character controller (slide, step-up, ground snap) | `Engine/World/Collision.odin` : `Controller_Step` |
| Raycasts (box, sphere, capsule, terrain), ballistic step, cone spread | `Engine/World/Raycast.odin` : `Raycast_World`, `Ballistic_Step`, `Spread_Direction` |
| Weapon behaviour (fire rate, ammo, reload, explosion falloff) | `Game/Weapons/Behavior.odin` : `Weapon_Update`, `Explosion_Falloff` |
| Health and hit-zone damage multipliers | `Game/Gameplay/Health.odin` : `Health_Apply_Damage` |
| Player movement and look | `Game/Gameplay/Player.odin` : `Player_Wish_Velocity`, `Player_Look` |
| Enemy body, hit shapes, raycast against a soldier | `Game/Gameplay/Enemy.odin` : `Enemy_Hit_Shapes`, `Enemy_Raycast` |
| Enemy AI state machine (patrol, spot, chase, shoot, dead) | `Game/Gameplay/EnemyAi.odin` : `Enemy_Ai_Update`, `Can_See` |
| Battle simulation, hitscan, projectiles, effects | `Game/Gameplay/Battle.odin` : `Battle_Update`, `Resolve_Hitscan`, `Battle_Detonate` |
| HUD quads and text (immediate mode) | `Engine/Render/Hud.odin`; `Shaders/Hud.glsl` |
| Procedural material recipes | `Shaders/Recipes/*.glsl` (one per `Surface_Material`) |
| Sun shadow depth pass | `Shaders/ShadowDepth.glsl` |
| Fullscreen triangle vertex stage | `Shaders/Include/Fullscreen.glsl` |
| Program entry, scene table, loop | `Source/Main.odin`, `Source/Loop.odin`, `Source/Config.odin` |
| BMP to PNG for screenshot review | `Tools/ToPng.sh` |
| Light shafts (screen-space radial march toward the sun) | `Shaders/PostTonemap.glsl` : `light_shafts`; `Engine/Render/Renderer.odin` : `shaft_inputs` |
| Night lights: floodlight spots, tower and guard-post lamps, door lights, faded by darkness | `Game/Base/NightLights.odin` : `Layout_Night_Lights`; used in `Game/Sandbox/Sandbox.odin` : `Sandbox_Render` |
| Player flashlight (F), a spot light at the eye | `Game/Sandbox/Play.odin` : `play_items` |
| Spot-light shadows (nearest 4 shadowed spots, depth array, normal-offset 3x3 PCF) | `Engine/Render/SpotShadows.odin` : `Spot_Shadows_Choose`, `Spot_Shadow_Matrix`; `Engine/Render/ShadowMap.odin` : `Shadow_Map_Render_Layers`; `Shaders/DeferredLight.glsl` : `spot_shadow` |
| Per-chunk prop culling (in view, or near enough to cast a shadow into view) | `Game/Sandbox/Sandbox.odin` : `collect_instances`, `chunk_matters` |
| The player's own body and held weapon | `Game/Sandbox/Play.odin` : `animate_body`, `add_held_weapon` |
| Player health regeneration | `Game/Gameplay/Battle.odin` : `regenerate_player` |
| Oriented solid boxes (exact at any heading), ray and body tests against them | `Engine/World/Solid.odin` : `Solid`, `Ray_Solid`, `Solid_From_Object_Box`; `Engine/World/Collision.odin` |
| Temporary solids (trees, rocks near the player) | `Game/Sandbox/Play.odin` : `fill_prop_solids` |
| Invisible collision boxes for thin objects (fence panel) | `Engine/Procedural/Assembly.odin` : `Part.collision_only`; `Game/Catalogue/Objects.odin` : `add_collision_box` |
| Placement and layout solids | `Game/Base/Footprint.odin` : `Placement_Solids`, `Layout_Solids` |
| Hollow buildings (walls, door openings, furniture, ceiling lamps) | `Game/Catalogue/Buildings.odin` : `add_walled_room` |
| Door specs and leaf meshes (plank, sheet, mesh gate) | `Game/Catalogue/Doors.odin` : `Catalogue_Doors`, `Door_Leaf_Build` |
| Doors in the world (open/close animation, leaf solid, nearest door, toggling a gate's leaves together) | `Game/Base/Doors.odin` |
| Door leaf drawing and shadows | `Game/Base/DoorRender.odin` |
| Interior ceiling lights | `Game/Base/InteriorLights.odin` : `Layout_Interior_Lights` |
| E to open or close a door, on-screen prompt | `Game/Sandbox/Play.odin` : `interact_with_doors` |
| Ground vehicle physics (throttle, brake, drag, bicycle steering or tracked pivot, hull-vs-solid blocking, terrain pitch and roll) | `Engine/World/GroundVehicle.odin` : `Ground_Vehicle_Step`, `hull_hits_solid`, `rectangles_overlap` |
| Articulated vehicle specs (hull, wheel mounts, turret, gun, seat, handling) | `Game/Catalogue/Vehicles.odin` : `Catalogue_Vehicle_Spec` |
| Vehicle entities: update, boarding range, exit spot, turret slew, cannon and machine gun | `Game/Vehicles/Vehicle.odin` |
| Vehicle drawing (hull, turret, gun, instanced steered and spinning wheels) | `Game/Vehicles/VehicleRender.odin` |
| Driving in play: E boards and exits, WASD drive, mouse aims, V seat or chase view, chase camera pull-in, HUD | `Game/Sandbox/Driving.odin` : `drive_vehicle`, `vehicle_camera` |
| Gun fire from vehicles, shells, running enemies over | `Game/Gameplay/Battle.odin` : `Battle_Fire_Bullet`, `Battle_Spawn_Projectile`, `Battle_Run_Over` |
| Helicopter flight model (rotor spool-up, collective climb and hover, pitch/roll/yaw, hull-vs-solid blocking, terrain touchdown and impact speed) | `Engine/World/Aircraft.odin` : `Aircraft_Step` |
| Helicopter spec (hull, main and tail rotors, seat, handling) and rotor drawing | `Game/Catalogue/Vehicles.odin` : `helicopter_spec`; `Game/Vehicles/VehicleRender.odin` |
| Flying in play (Space/Ctrl climb and descend, W/S pitch, A/D turn, Q/E strafe, hard-landing damage, altitude and rotor HUD) | `Game/Sandbox/Driving.odin` : `drive_vehicle`, `apply_hard_landing`, `draw_vehicle_hud` |
| Mission objectives state machine (enter, hack, radar, hostage, extraction) | `Game/Mission/Mission.odin` : `Mission_Update`, `Mission_Current_Objective` |
| Destructible targets (the radar dish): bullets, blasts, shells | `Game/Gameplay/Target.odin`; `Game/Gameplay/Battle.odin` : `Battle_Add_Target`, `damage_target` |
| Mission in the sandbox: hostage following, hack and rescue prompts, briefing and completion screens, extraction beacon | `Game/Sandbox/MissionPlay.odin` |
| Security cameras: sweeping cone, range and line-of-sight sight test, suspicion timer, base-wide alarm | `Game/Mission/SecurityCamera.odin` : `Camera_Sees`, `Camera_Update`, `Alarm_Raise` |
| Cameras in the world: placement on towers, HQ and guard posts, shootable, disabled by the hack, drawn sweeping; alarm alerts soldiers | `Game/Sandbox/SecurityCameras.odin` |
| Stealth numbers: visibility and noise by stance and speed | `Game/Gameplay/Stealth.odin` : `Visibility`, `Noise_Radius` |
| Crouching body (shorter, fits under beams, stands up only where clear) | `Engine/World/Collision.odin` : `Controller_Set_Crouch`, `Controller_Height` |
| Binoculars (B): 12 degree zoom, slower look, circular mask, range readout to terrain or soldiers | `Game/Sandbox/Optics.odin` : `binoculars_draw_hud`, `binocular_look_scale` |
| Tactical map (M): base footprints, soldiers, cameras, objectives, vehicles, player arrow | `Game/Sandbox/Optics.odin` : `map_draw_hud` |
| Four-corner HUD shapes | `Engine/Render/Hud.odin` : `Hud_Quad` |
| Interactions need line of sight (doors, vehicles, hack, rescue) | `Engine/World/Raycast.odin` : `Line_Of_Sight_Clear` |
| Rooms shut out sky ambient and outside lamps | `Shaders/Include/Interior.glsl`; `Game/Base/InteriorLights.odin` : `Layout_Interiors` |
| Binocular zoom (Z/X, smooth raise), map objective markers | `Game/Sandbox/Optics.odin` |
| Weathering and fine detail on surfaces | `Shaders/Include/Weathering.glsl` : `weather_surface`; used in `Shaders/Geometry.glsl` |
| Cloud layer (fbm plane, self-shadowing, silver lining) | `Shaders/Include/Sky.glsl` : `add_clouds` |
| Smoke and dust puffs, bullet-hole decals | `Game/Sandbox/Particles.odin` |
| Head bob and weapon sway | `Game/Sandbox/Play.odin` : `update_view_motion` |
| Soft shadow filter (Vogel disk PCF) | `Shaders/Include/Shadow.glsl` |
| Moving tank tracks (links on a stadium path, the two sides running opposite ways when pivoting) | `Game/Vehicles/VehicleRender.odin` : `append_track_links`; `Game/Catalogue/Vehicles.odin` : `Track_Spec` |
| Vehicle suspension (critically damped pitch and roll springs: braking noses down, turns lean out) | `Game/Vehicles/Vehicle.odin` : `step_suspension` |
| Tyre treads and wheel nuts | `Game/Catalogue/Objects.odin` : `add_wheel` |
| Screen-door (dithered) transparency for smoke | `Shaders/Geometry.glsl` : `bayer_threshold`; `Engine/Render/Scene.odin` : `Draw_Item.transparency` |
| Supplies: dropped ammunition, medkits, walk-over pickup | `Game/Gameplay/Pickup.odin`; drawn in `Game/Sandbox/MissionPlay.odin` : `pickups_items` |
| Alarm reinforcements and radioed alarms | `Game/Sandbox/SecurityCameras.odin` : `send_reinforcements` |
| Ladders and climbing (watchtower lookouts with snipers) | `Engine/World/Collision.odin` : `climb`; `Game/Catalogue/Buildings.odin` : `Catalogue_Ladders`; `Game/Base/Footprint.odin` : `Layout_Ladders` |
