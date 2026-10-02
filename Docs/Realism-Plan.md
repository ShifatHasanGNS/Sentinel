# Realism plan

Goal: make the whole game look as real as procedural primitives, noise and OpenGL 4.1 allow. Same hard rules as always: no models, no image files, everything from code. Each phase ends with before/after screenshots, tests where there is logic, a benchmark (budget: 60 fps at 1080p) and a commit. Phases are ordered by visible payoff.

| Phase | Area | What gets built | Done when |
|---|---|---|---|
| R1 | Surface realism (shader) | Weathering by height and exposure (grime near the ground, rain streaks under edges, sun fading on tops); detail normal layer at a second scale; specular occlusion; wet and dust variation per object seed | Walls, vehicles and ground show large-scale variation and fine detail up close; no repeated-tile look at 10 m |
| R2 | Ground and vegetation | Grass blades as instanced tufts with wind sway; tree species (pine, broadleaf) with a branch skeleton; bush variety; ground clutter (stones, dry grass); mud and tyre tracks near paths | A walk through the open world looks like a field and a wood, not a lawn of blobs |
| R3 | Sky and atmosphere | Volumetric-looking clouds (fbm layers with lighting), sun glare, horizon haze already in; height fog; auto exposure; dawn and dusk colour accuracy | Time-of-day sweep looks plausible hour by hour |
| R4 | Buildings | Bevelled edges, trim and cornices, window frames with real recesses and glass that reflects the sky, door frames, roof overhang, gutters, vents, AC units, antennas, sandbags, numbering, stains | Close-ups read as real structures |
| R5 | Vehicles | Rounded hulls (bevel and deform), panel lines, lights and mirrors, tracks with links, treaded wheels with rims, hoses, antennas, stowage; suspension travel | Close-ups of each vehicle hold up; wheels and tracks look right while driving |
| R6 | Characters | Fuller anatomy (neck, hands with fingers, boots), gear (helmet with straps, vest, pouches, belt, backpack), faces with eyes, uniform wear | A soldier at 3 m looks like a soldier |
| R7 | Lighting and post | Soft shadows (PCSS-style), contact shadows, screen-space reflections for glass and wet ground, better SSAO, bloom tuning, subtle film grain and colour grading, lens dirt off | Screenshots look photographic at a glance |
| R8 | Motion realism | Gait refinement, weapon sway and recoil, head bob, vehicle suspension, rotor blur, muzzle smoke and dust, bullet impacts with decals, explosion smoke | Everything that moves moves believably |

Out of scope (cannot be done under the rules or the platform): scanned or photo textures, ray-traced global illumination (OpenGL 4.1 has no ray queries), audio.

Status: **R1 done** (weathering, `Shaders/Include/Weathering.glsl`). **R3 started**: procedural cloud layer with self-shadowing and silver lining (`Shaders/Include/Sky.glsl`), aerial perspective. R2 partly done (grass tufts near the camera, calmer ground colour). R4 started (window frames, mullions, sills, door canopy, dark day glass). R5 started (vehicle details). R6 started (soldier gear, face, fingers, knee pads, belts). R7 started (soft shadows: 12-tap rotated Vogel disk PCF). R8 started (smoke and dust puffs, bullet-hole decals, head bob, weapon sway). Still missing: suspension travel, rotor blur, gait refinement. Trees now branch (six branches with foliage clumps on the tips) and shrubs are clusters. Vehicle body panels are now subdivided and gently domed (`add_rounded_box`). Still missing: screen-space reflections, contact shadows, fading smoke. Benchmark after these: about 17.5 ms average on a busy machine (budget 16.7).

Tracking: this table is the status (update the row when a phase lands). Features land in `Docs/Features.md` as usual.
