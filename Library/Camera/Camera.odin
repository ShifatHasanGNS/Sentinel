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

// -----------------------------------------------------------------------
// Math & coordinate conventions (CLAUDE.md §1.2/§10, roadmap step 1,
// Session 1). This project doesn't hand-derive its math — core:math/linalg
// does — but linalg still has real conventions baked into how its procs
// behave, and every session from here on assumes them. Recorded once, here,
// so nobody re-derives or contradicts them later. Confirmed empirically
// against this project's installed Odin toolchain (see
// Library/Camera/Camera_test.odin and PROGRESS.md), not assumed from docs.
//
// - COORDINATE SYSTEM: right-handed, +X right, +Y up, and in VIEW space the
//   camera looks down -Z (confirmed: matrix4_look_at(eye=(0,0,5),
//   target=origin, up=+Y) puts the origin at view-space z = -5). This is
//   `matrix4_look_at` and `matrix4_perspective`'s default `flip_z_axis =
//   true` behaviour; SENTINEL never overrides that default, so every
//   view/projection matrix in the project agrees with each other and with
//   plain OpenGL's own long-standing convention — nothing about clip space
//   or NDC needs re-deriving once a linalg matrix reaches the GPU.
//
// - VECTOR CONVENTION: vectors are COLUMNS, transformed on the right of a
//   matrix (`p' = M * p`, i.e. `la.mul(M, p)`). Composing transforms
//   therefore reads right-to-left in code but "first this, then that" in
//   effect: `mvp := la.mul(proj, la.mul(view, model))` means "apply `model`
//   first, then `view`, then `proj`" to a point on the right. This matches
//   what `matrix4_translate`/`matrix4_rotate`/`matrix4_scale` themselves
//   already produce — a row-vector convention would silently invert every
//   composition order in the project.
//
// - MATRIX STORAGE / GLSL MAPPING: `Matrix4f32` stores COLUMN-MAJOR in
//   memory — confirmed by reading `la.to_ptr(&m)` back as a flat float
//   array after building a translation matrix: the translation lands in the
//   LAST four floats, i.e. the last COLUMN, exactly where GLSL's own
//   column-major `mat4` expects it. This is why
//   `Library/Engine/Shader.SetUniformMatrix4f32` calls
//   `gl.UniformMatrix4fv(..., transpose = false, la.to_ptr(mat))` — no
//   transpose is ever needed between a linalg matrix and a GLSL uniform,
//   and no future session should add one "just in case".
//
// - ANGLE UNITS: radians everywhere inside linalg (`matrix4_rotate`,
//   `matrix4_perspective`'s fovy, etc.). SENTINEL keeps all angle STATE
//   (yaw/pitch, sweep angles, FOV) in radians internally, converting to/from
//   degrees only at the edges people actually read (an on-screen readout, a
//   CLI flag) with `math.to_radians`/`math.to_degrees` — so no proc in this
//   project is ever silently handed the wrong unit.
//
// - ROTATION DIRECTION: positive angles follow the RIGHT-HAND RULE around
//   the given axis (point the right thumb along the axis; the fingers curl
//   toward positive rotation) — confirmed empirically: rotating (1,0,0) by
//   +90 degrees about (0,1,0) with `matrix4_rotate` yields (0,0,-1), i.e.
//   +X sweeps toward -Z, exactly the right-hand rule applied to +Y in this
//   right-handed system. Every hierarchy rotation later (tower-head sweep,
//   turret spin, radar rotation) uses this same sense, so "positive angle"
//   always means the same physical direction everywhere in the project.
//
// - CLIP-SPACE DEPTH RANGE: `matrix4_perspective`'s default maps view-space
//   near to NDC z = -1 and far to NDC z = +1 (OpenGL's traditional [-1, 1]
//   clip volume, not Direct3D's [0, 1]) — confirmed empirically. SENTINEL
//   never calls `gl.ClipControl`, so this is the depth range the GPU
//   actually uses; the depth-buffer visualisation planned for roadmap step
//   8 must remap from THIS range, not [0, 1].
// -----------------------------------------------------------------------
