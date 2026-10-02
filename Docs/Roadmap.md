# Roadmap

| # | Milestone | Status |
|---|---|---|
| M0 | Reset + docs | done except skills research (to propose, not install, without approval) |
| M1 | GPU core + platform | done: `odin test Engine/GPU` (3 pure tests) and `odin run Tests/GpuCheck` (21 GL checks) pass; showroom screenshot reviewed |
| M2 | Procedural geometry | done: `odin test Engine/Procedural` (35 tests: noise, 7 primitives, mesh builder, 5 deformers); gallery screenshot reviewed. Noise tileability moved to M3 (GLSL recipes) |
| M3 | Texture recipes + materials | done: `odin run Tests/TextureCheck` (8250 checks: periodic noise, normal-from-height, sRGB round trip, exact tiling of all 8 materials, detail) and `Tests/GpuCheck` (26) pass; showroom screenshot reviewed |
| M4 | Deferred renderer | todo |
| M5 | World | todo |
| M6 | Base content | todo |
| M7 | Characters + animation | todo |
| M8 | Gameplay | todo |
| M9 | Polish | todo |

Full plan: milestone definitions and "done when" checks are in the approved plan (`~/.claude/plans/compiled-giggling-trinket.md`); copy into this file as each milestone starts.
