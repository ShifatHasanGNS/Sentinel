// Package Camera — free-fly + Patrol-Mode path camera and projection
// toggle. Split out from `Library/Scene` into its own package per the
// user's Session 0 decision on CLAUDE.md §11 item 7 (was previously
// tentative — see PROGRESS.md).
//
// Roadmap step 2 (CLAUDE.md §9; Prompts.md Session 2), extended in Session
// 12 (Patrol Mode) and Session 13 (Inspection Mode).
//
// Planned Camera struct: position, yaw, pitch, fov, near, far, and a
// projection mode (Perspective | Orthographic). Uses
// `linalg.matrix4_look_at`, `linalg.matrix4_perspective`, and
// `linalg.matrix4_orthographic` directly (core:math/linalg is allowed —
// CLAUDE.md §2 item 3, updated) to build its view/projection matrices.
//
// Inspection Mode (interactive): free-fly controls — WASD move, mouse-look
// (cursor captured), Q/E down/up, Shift to move faster, delta-time-scaled
// movement, clamped pitch. Projection toggle on a dedicated key; scroll
// wheel adjusts the orthographic volume size so it frames roughly the same
// view as perspective at the current distance (CLAUDE.md §7, Requirements.md
// §3).
//
// Patrol Mode (automatic): the camera instead follows a smooth closed path
// around the outside of the perimeter fence, computed by a formula (e.g. an
// ellipse/superellipse or smoothed polar curve with slight height bobbing),
// always looking toward the base centre or a slowly drifting target — never
// a stored list of waypoints (CLAUDE.md §2.5, §7; Plan.md §4).
//
// Both modes must drive the SAME underlying Camera/view-projection code path
// (CLAUDE.md §2 item 9) — only what feeds the camera's transform differs. Mode
// switching must not desync state: Patrol -> Inspection keeps the current
// camera pose; Inspection -> Patrol resumes without a jarring jump (blend
// back onto the path, or restart from the nearest path point).
package Camera
