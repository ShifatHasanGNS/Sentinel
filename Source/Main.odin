// Package main — SENTINEL entry point: window, GL context, main loop, mode
// switching, and input dispatch. Ties together `Library/Engine`,
// `Library/Geometry`, `Library/Scene`, and core:math/linalg (allowed
// directly, CLAUDE.md §2 item 3 — no separate hand-written math package);
// itself stays thin (Requirements.md §7, CLAUDE.md §8/§13).
//
// This is Session 0 territory (CLAUDE.md/Plan.md roadmap "prep";
// Prompts.md Session 0) — set up first, before any project scene code
// exists. Do NOT implement project logic in this skeleton pass; this file
// only records what Session 0 needs to build.
//
// Session 0 scope:
//   1. Confirm Odin + vendor:glfw + vendor:OpenGL are available; record the
//      exact working build/run command in PROGRESS.md.
//   2. Open a GLFW window with an OpenGL 3.3+ core profile context, clear to
//      a dark colour, handle ESC to quit and window resize (viewport
//      update).
//   3. Compile one minimal shader pair from Shaders/ (see Shaders/Scene.vert
//      and Shaders/Scene.frag headers) and draw ONE throwaway triangle to
//      prove the pipeline end-to-end. Check and print shader compile/link
//      errors and GL errors (use Library/Engine/Debugger).
//      NOTE: that triangle's vertex data is allowed as a one-off pipeline
//      smoke test only — mark it with a TODO to delete once real geometry
//      (the `Library/Geometry` package, roadmap step 3) exists. It must
//      never become the seed of a "precomputed vertex table" habit
//      (CLAUDE.md §2.5).
//   4. A `--capture <frames> <path>` debug flag: render N frames, save a
//      screenshot via glReadPixels, exit. This is the project's only way for
//      Claude Code to "see" its own output (CLAUDE.md §1.2) — see Debug/.
//   5. Print startup diagnostics: shader compile logs, object count, active
//      light count (both become meaningful once `Library/Scene` is populated).
//
// Source/Input.odin (added once Inspection Mode exists, roadmap step 10):
// GLFW key/mouse callbacks, object selection, all interactive controls
// (CLAUDE.md §7's suggested key layout — Tab mode switch, P projection,
// 1/2/3 shading, C culling, Z depth test, [ ] select object, translate/
// rotate keys). Document the final key map in README.md, not just here.
//
// Source/Renderer.odin (grows alongside `Library/Engine/Renderer`, see that
// package's TODO): GL setup, per-frame uniform upload, the single shared
// draw loop used by BOTH Patrol and Inspection modes (CLAUDE.md §2 item 9 —
// never fork rendering logic per mode).
package main
