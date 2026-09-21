# SENTINEL — _"One Watchtower, Many Eyes."_

A real-time, night-time Forward Operating Base (FOB) renderer for a
university Computer Graphics course, written in **Odin** with **OpenGL +
GLSL** and **GLFW**. Vector/matrix math uses Odin's own `core:math/linalg`;
no scene-graph library, no precomputed geometry/light-position data —
everything else is generated at runtime.

This repository is currently a **project skeleton**: folder/package layout,
stub files, and the reused `Library/Engine/` GL wrapper (audited and usable
as provided — see `Library/Engine/Shader/Shader.odin`). No project geometry,
scene, or rendering logic has been implemented yet. Implementation follows
the session plan in `Prompts.md`, in order, one session at a time.

Note: `CLAUDE.md` §8/§13 sketch `Engine/`, `Geometry/`, and `Scene/` as
top-level siblings of `Source/`. This repo instead nests them one level
deeper under `Library/`, so the split is "executable (`Source/`) vs. library
code (`Library/*`)" rather than a flat list of packages at the root — a
deliberate, user-requested deviation from that suggested layout, not a
silent one. There is no `Math` package: `core:math/linalg` is allowed
directly (CLAUDE.md §2 item 3, updated from the project's original
hand-written-math constraint — see PROGRESS.md). Folder and Odin file names
throughout this repo use PascalCase, also by request.

## Start here

1. Read `CLAUDE.md` first — it is the authoritative guide for any coding
   assistant working in this repo, and states the hard constraints (§2) that
   override everything else.
2. Read `Requirements.md` (instructor + syllabus constraints) and `Plan.md`
   (design rationale) — source-of-truth documents `CLAUDE.md` defers to.
3. Read `PROGRESS.md` for the current session-to-session status (empty/fresh
   right now — this is session 0's job to fill in).
4. Follow `Prompts.md` session by session, starting with **Session 0**.

## Repository layout

```
Sentinel/
├── CLAUDE.md            # assistant instructions + hard constraints (read first)
├── Requirements.md      # instructor + syllabus constraints
├── Plan.md               # design plan and rationale
├── Prompts.md            # paste-ready per-session prompts, in build order
├── PROGRESS.md           # session-to-session handoff log (fill in as you go)
├── Library/               # library code, never built directly — consumed by Source/
│   ├── Engine/             # theme-agnostic OpenGL wrapper (from Engine.zip, audited)
│   │   ├── Shader/           # compile/link, uniform upload (core:math/linalg, as provided)
│   │   ├── VertexBuffer/
│   │   ├── IndexBuffer/
│   │   ├── VertexArray/
│   │   ├── VertexBufferLayout/
│   │   ├── Renderer/
│   │   └── Debugger/
│   ├── Geometry/           # theme-agnostic procedural mesh generators (box, cylinder, ...)
│   ├── Scene/              # SENTINEL-specific: transform hierarchy + the 9 objects
│   ├── Camera/             # SENTINEL-specific: free-fly + Patrol-Mode camera, projections
│   └── Lights/             # SENTINEL-specific: light structs, runtime placement/animation
├── Source/                 # main package: window, main loop, mode switching, input
├── Shaders/                 # hand-written GLSL (Scene.vert / Scene.frag)
└── Debug/                   # self-verification: --capture screenshot tooling
```

## Build / run

Confirmed on macOS (Apple Silicon) with the local Odin dev toolchain (see
`PROGRESS.md` "Environment" for exact versions):

```sh
odin build Source -out:Sentinel && ./Sentinel
# or, build-and-run in one step (note the `--` before program args):
odin run Source -out:Sentinel -- --capture 5 Debug/Captures/session0.bmp
```

`--capture <frames> <path>` renders that many frames, saves a screenshot,
and exits — see `Debug/README.md`.

## Controls

Free-fly camera controls, added this session (roadmap step 2). Object
selection/translate/rotate and the remaining Inspection Mode toggles
(shading mode, culling, depth-test, wireframe) arrive in roadmap step 10 and
will be added to this table then, not replace it.

| Key / input      | Action                                                    |
| ---------------- | ---------------------------------------------------------- |
| `W` / `S`        | Move forward / backward (along the camera's full look direction, including pitch) |
| `A` / `D`        | Strafe left / right                                        |
| `Q` / `E`        | Move down / up (world space, independent of look direction) |
| Mouse             | Look (cursor is captured — move the mouse to turn/pitch)    |
| `Shift` (either)  | Sprint (multiplies move speed)                              |
| `P`               | Toggle perspective / orthographic projection                |
| Scroll wheel      | Zoom the orthographic volume (only while in orthographic projection) |
| `Esc`             | Quit                                                         |

CLI flags for `--capture` runs (see `Debug/README.md`):

| Flag                         | Effect                                                                 |
| ----------------------------- | ----------------------------------------------------------------------- |
| `--capture <frames> <path>`   | Render `frames` frames, save a screenshot to `path`, then exit          |
| `--projection <perspective\|orthographic>` | Starting projection mode (default `perspective`) |

Interactive input (mouse look, WASD/QE movement, `P`, scroll) is
intentionally disabled during a `--capture` run so captured frames stay
reproducible regardless of the real system cursor/keyboard state —
`--projection` is the supported way to change what a capture run looks at.

## Syllabus coverage

See `CLAUDE.md` §4 for the full topic-to-implementation mapping. A final
version of this table, with evidence, belongs in this README by Session 16.

## Photon mapping

SENTINEL implements ray tracing (§6.2) and a path-tracing-style sampled area
light (§6.3) in the renderer, but treats photon mapping as a documentation-
only topic (§6.4) since it is fundamentally a batch/offline technique. That
write-up is added in Session 16 and lives in this README or `REPORT.md`.
