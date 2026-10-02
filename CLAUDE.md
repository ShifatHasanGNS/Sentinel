# SENTINEL — procedural game engine + open-world military FPS

Note: Use 'craft' skill and all other necessary skills. and, Never add Claude as any contributor in Git/GitHub.

Odin + OpenGL 4.1 core (macOS ceiling: no compute, no SSBO) + GLFW. Everything is generated at runtime.

## Hard constraints

1. No pre-saved 3D models, no image/texture files, no precomputed data on disk. Meshes and textures come from code and a seed. Only shader sources are read from disk.
2. Characters and objects are built from primitives (spheres allowed) plus transforms plus noise deformers.
3. Engine packages never import `Game`. Dependencies point down: `Game` > `Engine/Render` > `Engine/World` > `Engine/Procedural` > `Engine/GPU` > `Engine/Platform`.

## Layout

`Engine/{Platform,GPU,Procedural,Render,World}`, `Game/{Materials,Catalogue,Base,Characters,Weapons,Gameplay,Sandbox,Showroom}`, `Shaders/{Include,Recipes}`, `Source/Main.odin`, `Tools/`, `Docs/`.
Folders and files are PascalCase. One package per folder. One feature per file, named after the feature.
`Docs/Features.md` maps every feature to file:proc. Update it in the same change that adds the feature.

## Readability rules

- `Source/Main.odin` is a table of contents: init, loop { input, update, render }, shutdown. Any feature is reachable in 3-4 named calls.
- Procs are at most ~40 lines and do one job. `if` in the parent, `for` in the helpers.
- Content is data: a `Part{primitive, transform, deformers, material}` table, not branching builder code.
- One `Config` struct and few CLI flags. No per-feature flag procs.
- Full-word names, units last (`range_meters`, `fov_degrees`). No abbreviations. No lookups by name string.
- Comments only where the math is invisible in the code: name the formula, say why. Theory lives in `Docs/Graphics-Theory.md`.
- Assert preconditions. Check every GL error. Never swallow a failure.

## Commands

- Build/run: `odin run Source -out:Sentinel` (fly: WASD, mouse, Space/Ctrl or E/Q for up/down, Shift to boost, Esc quits). For speed numbers build with `-o:speed`.
- Flags: `--scene sandbox|showroom|catalogue|soldiers`, `--object <Name>` (catalogue close-up), `--view base|gate|yard|airfield|command` (sandbox camera), `--demo` (sandbox: a bot plays and fires at the nearest enemy), `--time <hours>` (fixed hour; omit to run the day cycle), `--capture <frames> <path>`, `--benchmark <frames>` (1080p, scripted circuit, prints frame and per-pass GPU times).
- Pure tests: `odin test Engine/GPU`, `Engine/Procedural`, `Engine/Render`, `Engine/World`, `Game/Gameplay`, `Game/Catalogue`, `Game/Base`, `Game/Characters`, `Game/Weapons` (one `odin test <package>` each), run from the repo root (fixtures use root-relative paths)
- GL checks (need a window, main thread): `odin run Tests/GpuCheck -out:GpuCheck`, `odin run Tests/TextureCheck -out:TextureCheck`, `odin run Tests/RenderCheck -out:RenderCheck`
- Screenshot self-check: `odin run Source -out:SentinelDebug -- --capture <frames> Captures/x.bmp`, then `Tools/ToPng.sh Captures/x.bmp` and view the PNG.

## Adding things

- New material: `Shaders/Recipes/<Name>.glsl` (define `recipe_surface`, include `BakeMain.glsl` last), one `Surface_Material` entry and one table row in `Game/Materials/Materials.odin`, plus a Showroom sphere (automatic). `TextureCheck` then verifies it tiles.
- New object: an `Object_Kind` entry, a parts proc in `Game/Catalogue/*.odin`, a real-world size range in `Catalogue_test.odin` (the tests then check it), and a placement in `Game/Base/Layout.odin` if it belongs in the base.
- New light type or illumination model: `Shaders/Include/Lighting.glsl` / `Brdf.glsl`, the matching enum in `Engine/Render`, a probe check in `Tests/RenderCheck`, plus a Showroom cell.

## Status and history

`Docs/Roadmap.md` has milestone status (M0-M9). v1 (course scene viewer) is the git tag `legacy-v1`; harvest from it with `git show legacy-v1:<path>`.

## Playing
Sandbox starts in Play mode: WASD move, mouse look, Space jump, Shift sprint, left mouse fire, R reload, 1-5 weapons, Enter respawn, Tab toggles the fly camera. `--view` starts in fly mode.
