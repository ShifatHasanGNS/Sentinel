# Optimization log

Measured with `./SentinelFast --benchmark 300` (1080p, scripted circuit, -o:speed, busy machine, so compare ratios, not absolutes). Budget: 16.7 ms.

| Algorithm | Problem | Change | Effect |
|---|---|---|---|
| Shadow caster submission | Every terrain chunk drawn for all 3 cascades | Draw items carry a world box; each cascade culls by its own light frustum (`Frustum_Intersects_Aabb`) | Shadows 2.4 to 1.4 ms |
| Prop instances | Trees, rocks, bushes uploaded and drawn even behind the camera | Per-instance sphere test against the view frustum; kept if within 60 m (shadow reach) | Geometry vertex load down |
| Tree level of detail | 1400-triangle trees drawn at any range | Far mesh of three coarse lobes beyond 110 m | Geometry 5.9 to 4.7 ms |
| Gradient noise (GLSL) | cos/sin of a random angle per lattice corner, 4 corners per octave per pixel | 16-entry unit-gradient table indexed by hash bits (Perlin 2002) | Geometry 3.85 to 3.6 ms; sky clouds cheaper too |
| Terrain mottling | 6 noise octaves per terrain pixel | 3 octaves | Geometry 4.7 to 3.85 ms |
| SSAO | Full resolution, 12 taps per pixel | Half-resolution pass and a depth-aware (bilateral) 4x4 upsample using linearised depth | Ssao 1.5 to 1.1 ms |
| Cloud layer | 7 noise octaves per sky pixel | 3+2 octaves for the cloud, 2 for the sun-direction shading sample | Lighting 3.4 to 2.1 ms |
| Soft shadows | 12 taps per lookup, 140 m | 8 taps (rotated Vogel disk), 100 m distance | Shadows and lighting passes cheaper |
| Uniform uploads | ~9 `glProgramUniform` calls per scene item, most repeating the last item's values | Per-shader last-value cache; identical sets are skipped | CPU submit 3.4 ms down, frame 14.1 to 13.5 ms |
| Collision broad phase | Each solid test turned the body into the solid's axes (sin and cos) | Distance-squared reject first, no trigonometry | Reachability tests 2.0 to 1.0 s |
| Ray broad phase | Every ray test turned the ray into each solid's axes | Ray versus bounding sphere first | Fewer rotations per shot and sight ray |
| Enemy sight | A world raycast per soldier per frame even when the player was out of range | Skip the ray beyond the longest possible sight range | Fewer raycasts |
| Contact shadows, reflections | New features added at a cost | 8-step contact march; reflections limited to roughness under 0.25, 16 steps | Together about 0.4 ms |

Measured and left alone: terrain chunk build (0.5 ms), props and characters gather (0.3 ms), game update (1.5 ms in combat), startup (0.8 s). The main thread spends most of each frame waiting in `swapBuffers`: the remaining time is the GPU and the compositor, not the CPU.

Techniques considered and not adopted: GPU-driven culling and mesh shaders (need compute or newer GL than macOS offers), temporal anti-aliasing (needs motion vectors the G-buffer does not store), clustered or tiled light culling (the game never has more than a dozen local lights at once).
