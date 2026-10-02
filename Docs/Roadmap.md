# Roadmap

| # | Milestone | Status |
|---|---|---|
| M0 | Reset + docs | done except skills research (to propose, not install, without approval) |
| M1 | GPU core + platform | done: `odin test Engine/GPU` (3 pure tests) and `odin run Tests/GpuCheck` (21 GL checks) pass; showroom screenshot reviewed |
| M2 | Procedural geometry | done: `odin test Engine/Procedural` (35 tests: noise, 7 primitives, mesh builder, 5 deformers); gallery screenshot reviewed. Noise tileability moved to M3 (GLSL recipes) |
| M3 | Texture recipes + materials | done: `odin run Tests/TextureCheck` (8250 checks: periodic noise, normal-from-height, sRGB round trip, exact tiling of all 8 materials, detail) and `Tests/GpuCheck` (26) pass; showroom screenshot reviewed |
| M4 | Deferred renderer | done except spot-light shadows, point-light shadows, anisotropic GGX and bloom (see Decisions): `odin run Tests/RenderCheck` (308k checks: normals, tonemap, 6 illumination models, falloff and light shapes, sun shadows incl. acne), `odin test Engine/Render` (4 cascade tests), GpuCheck (30); showroom screenshot reviewed |
| M5 | World | done: terrain/scatter/culling/streaming/time-of-day/instancing tested (`odin test Engine/Procedural` 45, `Engine/World` 4, `Engine/Render` 7, `Game/Gameplay` 7; RenderCheck 318k incl. atmosphere, instancing, sky LUT). Benchmark (1080p, 1:1, -o:speed, ~1 km circuit): avg 10.3 ms, p99 15.5 ms, worst 30 ms |
| M6 | Base content | done: `odin test Game/Catalogue` (5: validity, size ranges, grounding, budget, determinism, collision, shadow subset), `Game/Base` (7: layout), `Engine/Procedural` (52); base on the plateau, 1080p benchmark avg 12.1 ms, p99 18.9 ms |
| M7 | Characters + animation | done: `odin test Game/Characters` (26: IK, gait, skeleton, soldier), `Game/Weapons` (3), `Engine/World` (11, incl. spring); line-up screenshot reviewed |
| M8 | Gameplay | todo |
| M9 | Polish | todo |

Full plan: milestone definitions and "done when" checks are in the approved plan (`~/.claude/plans/compiled-giggling-trinket.md`); copy into this file as each milestone starts.
