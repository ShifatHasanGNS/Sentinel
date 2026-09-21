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
//
// Session 5 (Prompts.md): added a_Normal + a temporary, hardcoded-in-shader
// single directional light (ambient + Lambert diffuse + Blinn-Phong
// specular + emission) so shapes read with real depth instead of flat
// silhouettes, per that session's "simple directional shading" ask. This
// is NOT roadmap step 4's real system (CLAUDE.md §6.1): that one uploads a
// fixed-max ARRAY of point/spot/directional/area lights as a uniform
// block/array with a live count, computed fresh from Scene node world
// transforms every frame (CLAUDE.md §2 item 10), with the lighting
// function shared between this stage (Phong) and the vertex stage
// (Gouraud) per the flat/Gouraud/Phong toggle (roadmap step 7). Kept
// deliberately small and self-contained here so step 4 can replace the
// whole light block below without touching anything else in this file.

#version 330 core

#shader vertex

// Vertex stage.
layout (location = 0) in vec3 a_Position;
layout (location = 1) in vec3 a_Normal;

uniform mat4 u_MVP;
uniform mat4 u_Model;
uniform mat3 u_NormalMatrix;

out vec3 v_WorldPosition;
out vec3 v_WorldNormal;

void main() {
	gl_Position = u_MVP * vec4(a_Position, 1.0);
	v_WorldPosition = vec3(u_Model * vec4(a_Position, 1.0));
	// u_NormalMatrix is the inverse-transpose of u_Model's upper-left 3x3
	// (Scene.Normal_Matrix, computed CPU-side every frame from the node's
	// live world matrix — CLAUDE.md §5.3), so normals stay correct even
	// under a non-uniform scale (e.g. the watchtower roof's squashed
	// tetrahedron, Library/Scene/Objects.odin's build_watchtower).
	v_WorldNormal = normalize(u_NormalMatrix * a_Normal);
}

#shader fragment

// Fragment stage. Planned responsibilities, added incrementally (CLAUDE.md
// §6, §9; Plan.md §5, §9; Prompts.md Sessions 7-11):
//   - Session 7 (roadmap step 4): replace the single hardcoded light below
//     with the full local illumination model over a fixed-max uniform
//     array of lights (point/spot/directional first), with per-type
//     attenuation/cone handling. The lighting calculation must live in ONE
//     function callable from either this stage (Phong shading) or the
//     vertex stage above (Gouraud shading) — the single-light function
//     below is already written that way on purpose, to make that move
//     mechanical rather than a rewrite.
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
in vec3 v_WorldPosition;
in vec3 v_WorldNormal;

out vec4 FragColor;

// Per-object material (Scene.Material, uploaded once per draw call from
// Source/Main.odin's draw loop) — base colour, specular strength/
// shininess, and an emission colour for parts that should read as "lit"
// even under this placeholder single-light model (window/windshield/
// periscope glass, the floodlight housing, the radar beacon).
uniform vec3 u_BaseColor;
uniform float u_SpecularStrength;
uniform float u_Shininess;
uniform vec3 u_EmissionColor;

uniform vec3 u_ViewPosition;

// shade_with_placeholder_light computes ambient + Lambert diffuse +
// Blinn-Phong specular for ONE fixed, hardcoded directional light (a cool
// "moonlight" stand-in for CLAUDE.md §5.2's real moonlight, which arrives
// with the rest of the real light rig at roadmap step 5) plus the
// material's own emission. Deliberately a single self-contained function
// (not inlined into main) so promoting it to loop over a real light array
// at roadmap step 4 is a mechanical change in ONE place.
vec3 shade_with_placeholder_light(vec3 normal, vec3 world_position, vec3 base_color, float specular_strength, float shininess, vec3 emission_color) {
	vec3 light_direction = normalize(vec3(-0.4, -1.0, -0.3));
	vec3 light_color = vec3(0.55, 0.6, 0.75);
	float ambient_strength = 0.25;

	vec3 ambient = ambient_strength * light_color;

	float diffuse_factor = max(dot(normal, -light_direction), 0.0);
	vec3 diffuse = diffuse_factor * light_color;

	vec3 view_direction = normalize(u_ViewPosition - world_position);
	vec3 half_vector = normalize(-light_direction + view_direction);
	float specular_factor = pow(max(dot(normal, half_vector), 0.0), shininess);
	vec3 specular = specular_strength * specular_factor * light_color;

	return (ambient + diffuse + specular) * base_color + emission_color;
}

void main() {
	vec3 normal = normalize(v_WorldNormal);
	vec3 result = shade_with_placeholder_light(normal, v_WorldPosition, u_BaseColor, u_SpecularStrength, u_Shininess, u_EmissionColor);
	FragColor = vec4(result, 1.0);
}
