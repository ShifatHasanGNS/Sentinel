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
│   └── Scene/              # SENTINEL-specific: hierarchy, objects, lights, camera
│                           #   (package split still tentative, see Library/Scene/Transform.odin)
├── Source/                 # main package: window, main loop, mode switching, input
├── Shaders/                 # hand-written GLSL (Scene.vert / Scene.frag)
└── Debug/                   # self-verification: --capture screenshot tooling
```

## Build / run

Not yet confirmed. Session 0 will record the exact working command here,
expected to be close to:

```sh
odin run Source -out:Sentinel
```

## Controls

To be filled in starting Session 2 (camera) and finalized in Session 13
(Inspection Mode) and Session 16 (final docs pass).

## Syllabus coverage

See `CLAUDE.md` §4 for the full topic-to-implementation mapping. A final
version of this table, with evidence, belongs in this README by Session 16.

## Photon mapping

SENTINEL implements ray tracing (§6.2) and a path-tracing-style sampled area
light (§6.3) in the renderer, but treats photon mapping as a documentation-
only topic (§6.4) since it is fundamentally a batch/offline technique. That
write-up is added in Session 16 and lives in this README or `REPORT.md`.
