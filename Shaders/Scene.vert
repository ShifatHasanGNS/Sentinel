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
// Session 0 status: this file is loaded on its own via
// vendor:OpenGL's gl.load_shaders_file(vert_path, frag_path) — NOT through
// Library/Engine/Shader.New, which instead expects ONE combined file holding
// both "#shader vertex"/"#shader fragment" sections (see that package's
// load_shaders_from). That mismatch between a two-file layout (this file +
// Scene.frag) and Shader.New's one-file-two-markers contract is real and
// still open — Session 1b must resolve it (e.g. give Shader.New a
// two-file variant) before Engine.Shader can be used for this pair. Until
// then, plain vendor:OpenGL calls are the correct, non-hacky way to compile
// this smoke-test pipeline.

#version 330 core

// Session 1/2 will add model/view/projection uniforms here once
// core:math/linalg is in use; for this smoke test the triangle is already
// in clip space, so position passes straight through.
layout (location = 0) in vec3 a_Position;

void main() {
	gl_Position = vec4(a_Position, 1.0);
}
