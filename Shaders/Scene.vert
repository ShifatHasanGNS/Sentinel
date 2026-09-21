// Scene.vert — SENTINEL's single shared vertex shader.
//
// Placeholder only (project skeleton stage — see CLAUDE.md §9 roadmap and
// Prompts.md session prompts for build order). No shading logic implemented
// yet; Session 0 needs only a trivial pass-through pair to prove the
// pipeline with one throwaway triangle (see Source/Main.odin).
//
// Planned responsibilities, added incrementally:
//   - Session 0: minimal pass-through (position -> gl_Position), no
//     uniforms, to smoke-test compile/link/draw.
//   - Session 1/2: apply model/view/projection matrices uploaded from
//     core:math/linalg on the CPU side (allowed directly, CLAUDE.md §2 item
//     3); GLSL's own mat4 type is fine here, it's just a uniform.
//   - Session 7 (lighting): must expose the SAME lighting-calculation
//     function used by Scene.frag (CLAUDE.md §6.1) so Gouraud shading can
//     call it here while Phong calls it from the fragment stage — the
//     flat/Gouraud/Phong toggle (roadmap step 7 / Session 10) switches which
//     stage evaluates it, not the math itself.
//   - Session 10: flat-shading needs either per-face normals or the `flat`
//     interpolation qualifier with a documented provoking-vertex
//     convention — decide and note it here.
//
// #shader vertex
// (Library/Engine/Shader's loader splits this file on "#shader vertex" /
// "#shader fragment" markers per Requirements.md §7 / the provided
// Engine.zip Shader package — see Library/Engine/Shader/Shader.odin.)
