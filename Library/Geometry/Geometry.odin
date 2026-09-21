// Package Geometry — theme-agnostic procedural primitive/mesh generation.
//
// Must know nothing about the military-base theme (no "watchtower", "jeep",
// etc. in this package) — CLAUDE.md §13.1, Requirements.md §7. Consumed by
// SENTINEL-specific scene code, but importable and testable independently.
//
// Hard constraints that apply directly to this package (CLAUDE.md §2 items
// 5-8; instructor constraints, some added/updated):
//   - No precomputed/literal vertex tables, and nothing formed at compile
//     time. Every generator builds its vertices at runtime from parameters
//     using loops/formulas — never a hardcoded array of numbers.
//   - ONLY THREE direct mesh generators are allowed in this whole project:
//     Cube, Tetrahedron, and Plane (CLAUDE.md §2 item 6, instructor hard
//     constraint). There is no cylinder()/cone()/wedge() generator that
//     emits its own bespoke vertex data — every other shape (a "cylinder"
//     tower leg, a "cone" roof, a wedge ramp, a whole composite object) is
//     assembled at runtime by combining multiple Cube/Tetrahedron/Plane
//     instances via matrix transforms, using the mesh-combining/instancing
//     helper below. If a session's plan calls for a "cylinder generator,"
//     that's now a composition built from this package's three primitives
//     plus a runtime transform loop in the calling code, not a new
//     generator added here.
//   - No imported models or assets — everything is procedural, and only
//     from the three primitives above.
//   - Low-poly / faceted look: flat faces, low instance counts per
//     composition (roughly 6-10 segments/instances for a "cylinder"-style
//     ring). Duplicate vertices per face so each face gets its own normal
//     (needed later for the flat/Gouraud/Phong comparison in roadmap step 7).
//   - Fix ONE triangle winding convention (CCW = front is the suggested
//     default) and make every generator obey it consistently — a winding
//     bug here silently breaks back-face culling and lighting later.
//
// Planned contents (Session 3, CLAUDE.md roadmap step 3 / Prompts.md Session 3):
//   Mesh        — vertices (position + normal [+ colour/material index]),
//                 indices or triangle list, GL buffer handles, plus
//                 upload/draw/destroy procs (built on top of the
//                 `Library/Engine` package's
//                 VertexBuffer/IndexBuffer/VertexArray/Shader).
//   cube(w, h, d)        — 8 corners computed via a runtime loop over sign
//                          combinations (±1 in x/y/z), not a literal list.
//   tetrahedron(size)    — 4 vertices from a standard tetrahedron
//                          parametrization formula, not copied-in numbers.
//   plane(w, h)          — a basic flat quad (or other simple 2D polygon),
//                          vertices computed from w/h at runtime.
//   combine / append_mesh(dst, src, transform: linalg.Matrix4f32) —
//                 the mesh-combining/instancing helper that is the ONLY way
//                 composite or curved-looking shapes come into existence:
//                 callers loop at runtime, computing a transform per
//                 instance (e.g. a rotation per ring segment for a
//                 "cylinder," a taper + rotation for a "cone") and append a
//                 transformed cube/tetrahedron/plane each time. Uses
//                 core:math/linalg directly (allowed, CLAUDE.md §2 item 3 —
//                 no hand-written math package here).
//
// Verification plan (do not skip): for every generator, a test that each
// triangle's geometric normal (from winding) agrees with its stored normal,
// and that normals point outward from the mesh centre for closed meshes.
// Plus a temporary "gallery" view showing the three base primitives and at
// least one runtime-composed shape (e.g. a box-ring "cylinder"), with
// back-face culling ON, so wrong winding shows up as visibly missing faces.
package Geometry
