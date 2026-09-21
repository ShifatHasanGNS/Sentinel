// Scene.frag — SENTINEL's single shared fragment shader.
//
// Placeholder only (project skeleton stage). No shading logic implemented
// yet. See Scene.vert for the shared vertex-shader plan; this file mirrors
// its build-order notes for the fragment stage.
//
// Planned responsibilities, added incrementally (CLAUDE.md §6, §9; Plan.md
// §5, §9; Prompts.md Sessions 7-11):
//   - Session 0: solid dark colour output, no lighting, to prove the
//     pipeline (paired with Scene.vert's pass-through).
//   - Session 7: full local illumination model — ambient + diffuse
//     (Lambert) + specular (Blinn-Phong half-vector) + emission, summed
//     over a fixed-max uniform array of lights (point/spot/directional
//     first), with per-type attenuation/cone handling. The lighting
//     calculation must live in ONE function callable from either this stage
//     (Phong shading) or Scene.vert (Gouraud shading) — CLAUDE.md §6.1.
//   - Session 9: an AREA light type — per-fragment N-sample averaging over
//     a window quad passed in as a runtime-computed uniform (no precomputed
//     sample tables/textures, no LTC lookup texture — CLAUDE.md §2.5, §6.3).
//   - Session 10: flat/Gouraud/Phong mode uniform switching which stage's
//     lighting result is used.
//   - Session 11: manual back-face culling test (dot(normal, view dir)) as
//     an alternative to GL_CULL_FACE, toggleable and compared; a debug mode
//     that colours back faces to make the effect visible; a hand-written
//     depth-buffer linearisation for a depth-visualisation toggle.
//   - Session 14: the one genuinely ray-traced surface (tank periscope or
//     jeep windshield, CLAUDE.md §6.2) — reflection ray against uniform
//     proxy shapes (sphere/box/cylinder) rebuilt each frame from live
//     object transforms, analytic intersection, shade the hit with the same
//     lighting function used above.
//
// #shader fragment
