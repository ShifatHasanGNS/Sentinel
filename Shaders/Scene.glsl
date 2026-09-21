// Scene.glsl — SENTINEL's single shared vertex+fragment shader source.
//
// Combined into ONE file (rather than the separate Scene.vert/Scene.frag
// used through Session 1) because Library/Engine/Shader.New expects
// exactly this format: one file with "#shader vertex"/"#shader fragment"
// section markers and a single #version directive shared by both stages
// (see that package's load_shaders_from). Session 0 flagged this mismatch
// and deliberately deferred the merge to Session 1b (Engine integration) —
// see PROGRESS.md open item 8. This file is that merge.
//
// NOTE for anyone editing this file: Shader.New's parser strips every line
// starting with "//" (and every blank line) before handing the remainder to
// glCompileShader, so none of these comments reach the GPU or affect
// compilation — they exist purely for readers of this file on disk. Block
// comments (/* */) would NOT be stripped and are valid GLSL, but this
// project sticks to "//" everywhere else, so keep using it here too.
//
// The #version line below MUST stay before the first "#shader" marker: the
// parser only captures the FIRST #version it sees (before any "#shader"
// switches it into a per-stage body), then prepends that same line to BOTH
// compiled stages. A #version placed after "#shader vertex" would instead
// be read as a second, illegal #version inside the vertex body.

#version 330 core

#shader vertex

// Vertex stage. Planned responsibilities, added incrementally:
//   - Session 1 (done): apply one combined model-view-projection matrix
//     built from core:math/linalg on the CPU side (Source/Main.odin).
//   - Session 7 (lighting): must expose the SAME lighting-calculation
//     function used by the fragment stage below (CLAUDE.md §6.1), so
//     Gouraud shading can call it here while Phong calls it from the
//     fragment stage — the flat/Gouraud/Phong toggle (roadmap step 7)
//     switches which stage evaluates it, not the math itself.
//   - Session 10: flat shading needs either per-face normals or the `flat`
//     interpolation qualifier with a documented provoking-vertex
//     convention — decide and note it here.
layout (location = 0) in vec3 a_Position;

uniform mat4 u_MVP;

void main() {
	gl_Position = u_MVP * vec4(a_Position, 1.0);
}

#shader fragment

// Fragment stage. Planned responsibilities, added incrementally (CLAUDE.md
// §6, §9; Plan.md §5, §9; Prompts.md Sessions 7-11):
//   - Session 7: full local illumination model — ambient + diffuse
//     (Lambert) + specular (Blinn-Phong half-vector) + emission, summed
//     over a fixed-max uniform array of lights (point/spot/directional
//     first), with per-type attenuation/cone handling. The lighting
//     calculation must live in ONE function callable from either this
//     stage (Phong shading) or the vertex stage above (Gouraud shading).
//   - Session 9: an AREA light type — per-fragment N-sample averaging over
//     a window quad passed in as a runtime-computed uniform (no
//     precomputed sample tables/textures, no LTC lookup texture).
//   - Session 10: flat/Gouraud/Phong mode uniform switching which stage's
//     lighting result is used.
//   - Session 11: manual back-face culling test (dot(normal, view dir)) as
//     an alternative to GL_CULL_FACE, toggleable and compared; a debug mode
//     that colours back faces to make the effect visible; a hand-written
//     depth-buffer linearisation for a depth-visualisation toggle.
//   - Session 14: the one genuinely ray-traced surface (tank periscope or
//     jeep windshield) — reflection ray against uniform proxy shapes
//     rebuilt each frame from live object transforms, analytic
//     intersection, shade the hit with the same lighting function above.
out vec4 FragColor;

// Session 3 (roadmap step 3): one flat, per-draw-call colour, uploaded
// once per object from Source/Main.odin's draw loop (Scene.Node.Color).
// Still "unlit" per CLAUDE.md's roadmap-step-3 scope — this is a colour
// PARAMETER, not a lighting calculation; it exists so a capture of 9
// overlapping objects is legible instead of one uniform hardcoded orange.
// Replaced by the real material/lighting result at roadmap step 4.
uniform vec3 u_Color;

void main() {
	FragColor = vec4(u_Color, 1.0);
}
