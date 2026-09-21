// Scene.glsl — SENTINEL's single shared vertex+fragment shader source.
//
// Combined into ONE file (rather than separate Scene.vert/Scene.frag)
// because Library/Engine/Shader.New expects exactly this format: one file
// with "#shader vertex"/"#shader fragment" section markers and a single
// #version directive shared by both stages (see that package's
// load_shaders_from). See PROGRESS.md's "Session 1b" section for the full
// history of why the two-file layout was merged.
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
// Roadmap step 4 (CLAUDE.md §9; Prompts.md Session 7): replaced Session 5's
// single hardcoded directional light (shade_with_placeholder_light) with
// the real thing — a fixed-max uniform ARRAY of lights (Library/Lights.
// Light mirrors the `Light` struct below field-for-field), each with a
// type (directional/point/spot/area-placeholder), summed in ONE lighting
// function (compute_lighting) per CLAUDE.md §6.1's "one function, callable
// from either stage" requirement — kept as a single function exactly as
// Session 5 set it up to make this swap mechanical rather than a rewrite.
// compute_lighting currently lives only in the fragment stage (Phong,
// roadmap step 4's ask); roadmap step 7's flat/Gouraud/Phong toggle will
// need to duplicate this same function's text into the vertex stage too —
// GLSL has no #include, and Shader.New's parser assigns each line to
// whichever stage was last selected by a #shader marker, so "shared code"
// in this single-file format means "written once, copied verbatim" when
// that day comes, not a text section both stages draw from automatically.

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

// Fragment stage. Remaining planned responsibilities (CLAUDE.md §6, §9;
// Plan.md §5, §9; Prompts.md Sessions 10-14):
//   - Session 10: flat/Gouraud/Phong mode uniform switching which stage's
//     lighting result is used.
//   - Session 11: manual back-face culling test (dot(normal, view dir)) as
//     an alternative to GL_CULL_FACE, toggleable and compared; a debug mode
//     that colours back faces to make the effect visible; a hand-written
//     depth-buffer linearisation for a depth-visualisation toggle.
//   - Session 14: the one genuinely ray-traced surface (tank periscope or
//     jeep windshield) — reflection ray against uniform proxy shapes
//     rebuilt each frame from live object transforms, analytic
//     intersection, shade the hit with compute_lighting below.
in vec3 v_WorldPosition;
in vec3 v_WorldNormal;

out vec4 FragColor;

// Per-object material (Scene.Material, uploaded once per draw call from
// Scene.Draw_Node) — base colour, specular strength/shininess, and an
// emission colour for parts that should read as "lit" on their own (window/
// windshield/periscope glass, the floodlight housing, the radar beacon,
// and now every Library/Lights debug gizmo).
uniform vec3 u_BaseColor;
uniform float u_SpecularStrength;
uniform float u_Shininess;
uniform vec3 u_EmissionColor;

uniform vec3 u_ViewPosition;

// Global ambient term — a single scene-wide approximation of indirect/
// bounced light, NOT summed once per active light. Read literally, "ambient
// + diffuse + specular + emission, summed over all lights" (this session's
// task text) would make ambient brightness scale with how many lights
// happen to be active, which has no physical meaning and would wash out
// the night scene's shadows as roadmap step 5 adds ~20 more lights on top
// of this session's temporary rig. Every other renderer taught by this
// course's Blinn-Phong model treats ambient the same way: one global fill
// term, independent of light count. Uploaded once per frame from
// Source/Main.odin's AMBIENT_COLOR/AMBIENT_STRENGTH (a cool, dim, "night
// sky fill" tint — the same colour Session 5's single hardcoded directional
// light used for its own ambient term, kept for visual continuity).
uniform vec3 u_AmbientColor;
uniform float u_AmbientStrength;

// MAX_LIGHTS must match Library/Lights/Lights.odin's MAX_LIGHTS constant —
// GLSL has no way to share a compile-time constant with Odin across the
// language boundary, so these two "32"s are kept in sync by hand. If one
// changes, change the other.
#define MAX_LIGHTS 32

#define LIGHT_TYPE_DIRECTIONAL 0
#define LIGHT_TYPE_POINT 1
#define LIGHT_TYPE_SPOT 2
#define LIGHT_TYPE_AREA 3

// Mirrors Library/Lights.Light field-for-field (see that file for what each
// field means and how it's computed). Not a UBO/SSBO block — each field is
// uploaded through its own named uniform ("u_Lights[i].position", etc, see
// Lights.Upload), so there's no std140 layout to match byte-for-byte, only
// matching field names/types/order for readability.
struct Light {
	int type;
	vec3 position;             // world-space; meaningful for point/spot/area
	vec3 direction;            // world-space, normalized; meaningful for directional/spot/area (area: the quad's own outward normal)
	vec3 areaU;                // world-space U half-extent vector; area only
	vec3 areaV;                // world-space V half-extent vector; area only
	vec3 color;
	float intensity;
	float constantAttenuation;
	float linearAttenuation;
	float quadraticAttenuation;
	float innerConeCos;        // cos(inner angle) — full strength inside this
	float outerConeCos;        // cos(outer angle) — zero contribution outside this
	bool enabled;
};

uniform Light u_Lights[MAX_LIGHTS];

// Roadmap step 6 (CLAUDE.md §6.3) runtime controls — Source/Main.odin's
// +/- keys (sample count) and J key (jitter toggle), or --area-samples/
// --area-jitter for a --capture run. MAX_AREA_SAMPLES must match
// Library/Lights.MAX_AREA_LIGHT_SAMPLES — same "kept in sync by hand"
// situation as MAX_LIGHTS above.
#define MAX_AREA_SAMPLES 8
uniform int u_AreaLightSampleCount;
uniform bool u_AreaLightJitter;
// How many of u_Lights[0..u_ActiveLightCount) to actually examine this
// frame (Library/Lights.Upload sets this to how many light SLOTS it
// uploaded, not strictly a count of `enabled == true` ones — see that
// proc's own comment). light_contribution below still checks each light's
// own `enabled` flag, so a disabled light inside that range correctly
// contributes nothing rather than being silently assumed absent.
uniform int u_ActiveLightCount;

// light_contribution computes ONE light's diffuse (Lambert) + specular
// (Blinn-Phong half-vector) contribution, already scaled by that light's
// own distance attenuation and (for spot lights) cone falloff — everything
// this session's task asked for except the ambient/emission terms, which
// are scene-wide rather than per-light (see u_AmbientColor's comment
// above).
vec3 light_contribution(Light light, vec3 normal, vec3 world_position, vec3 view_direction, vec3 base_color, float specular_strength, float shininess) {
	vec3 to_light;
	float attenuation = 1.0;

	if (light.type == LIGHT_TYPE_DIRECTIONAL) {
		// `direction` is the direction the light TRAVELS (sky -> ground), so
		// the vector FROM the surface TOWARD the light source is its
		// negation. No distance falloff — a directional light is
		// infinitely far away by definition.
		to_light = normalize(-light.direction);
	} else {
		// Point and spot both attenuate by distance from a world-space
		// `position` — the standard constant/linear/quadratic falloff
		// (Library/Lights.Point_Attenuation_For_Range derives the three
		// coefficients from one "range" parameter instead of hand-picking
		// them per light, CLAUDE.md §2 item 5).
		vec3 light_vector = light.position - world_position;
		float distance = length(light_vector);
		to_light = light_vector / max(distance, 0.0001);
		attenuation = 1.0 / (light.constantAttenuation + light.linearAttenuation * distance + light.quadraticAttenuation * distance * distance);
	}

	if (light.type == LIGHT_TYPE_SPOT) {
		// Narrow the point-light falloff above into a cone: `direction` is
		// the direction the spotlight AIMS (light -> scene), so comparing
		// it against -to_light (the light-to-fragment vector) gives the
		// angle off the spot's own axis. smoothstep between the outer and
		// inner cosines gives the "smooth falloff" this session's task
		// asked for, instead of a hard on/off edge at the cone boundary.
		vec3 spot_axis = normalize(light.direction);
		float cone_cos = dot(-to_light, spot_axis);
		attenuation *= smoothstep(light.outerConeCos, light.innerConeCos, cone_cos);
	}

	float diffuse_factor = max(dot(normal, to_light), 0.0);
	vec3 half_vector = normalize(to_light + view_direction);
	float specular_factor = pow(max(dot(normal, half_vector), 0.0), shininess);

	// Diffuse tints by the surface's own base colour; specular does NOT
	// (a highlight is the LIGHT's colour reflecting off the surface, not
	// the surface's colour, for the dielectric materials used throughout
	// this scene — the standard Blinn-Phong convention).
	vec3 diffuse = diffuse_factor * base_color * light.color;
	vec3 specular = specular_strength * specular_factor * light.color;

	return attenuation * light.intensity * (diffuse + specular);
}

// hash21 is a cheap, fully deterministic pseudo-random function computed
// from its input ALONE — no noise texture, no lookup table (CLAUDE.md §2
// item 5's "no precomputed data" applies to a jitter pattern exactly as
// much as it does to geometry). The classic "sine-fract" shader hash:
// irrational-ish magic constants inside a high-frequency sin() so nearby
// inputs decorrelate quickly, then fract() throws away everything but the
// noisy low bits.
float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// area_light_contribution approximates a Lambertian emissive QUAD light
// (Library/Lights.Make_Area — a barracks window) by averaging N
// point-light-style samples spread across it. This is a SIMPLIFIED,
// SINGLE-BOUNCE MONTE CARLO integrator: real Monte Carlo area-light
// sampling (and, by extension, path tracing's own direct-light step)
// estimates the light arriving at a point by drawing random samples over
// the emitter and averaging their contribution, weighted by how the
// emitter's own surface faces each sample direction — exactly what the
// loop below does. It stays "simplified" in three ways worth being
// explicit about: (1) single-bounce only — light -> this fragment
// directly, never light -> some other surface -> this fragment, which is
// what "path" tracing actually chases across multiple bounces; (2) no
// per-sample VISIBILITY/shadow test — every sample is assumed unoccluded,
// since this project has no shadow map or general ray-cast visibility
// pass (CLAUDE.md §6.2 adds real ray casting, but scoped to one
// reflective surface, not shadow testing for every fragment); (3) N is
// small and fixed per frame (1-8, not thousands), traded for real-time
// speed over noise-free convergence — a genuine offline Monte Carlo
// renderer would use far more samples and average across many frames.
vec3 area_light_contribution(Light light, vec3 normal, vec3 world_position, vec3 view_direction, vec3 base_color, float specular_strength, float shininess) {
	int sample_count = clamp(u_AreaLightSampleCount, 1, MAX_AREA_SAMPLES);

	// A square-ish stratified grid sized to fit sample_count cells (e.g.
	// N=8 -> a 3x3 grid, using the first 8 of its 9 cells): one sample per
	// cell spreads samples across the WHOLE quad instead of clumping,
	// without requiring sample_count to be a perfect square. Computed from
	// sample_count every call, not a stored table.
	int grid_size = int(ceil(sqrt(float(sample_count))));

	vec3 total = vec3(0.0);
	for (int i = 0; i < sample_count; i++) {
		int cell_x = i % grid_size;
		int cell_y = i / grid_size;

		float u = (float(cell_x) + 0.5) / float(grid_size);
		float v = (float(cell_y) + 0.5) / float(grid_size);

		if (u_AreaLightJitter) {
			// Per-PIXEL jitter — keyed off gl_FragCoord, the actual screen
			// pixel, not world position, so neighbouring pixels get
			// DIFFERENT jitter even on the same flat surface — trades the
			// stratified grid's regular banding for noise instead, the
			// classic Monte Carlo tradeoff and exactly why a real path
			// tracer jitters its own sample pattern per pixel.
			vec2 seed = gl_FragCoord.xy + vec2(float(i) * 13.7, float(i) * 91.3);
			u += (hash21(seed) - 0.5) / float(grid_size);
			v += (hash21(seed + 17.0) - 0.5) / float(grid_size);
		}

		// Map [0,1] cell coordinates to the quad's own [-1,1] local
		// coordinates, then to a world-space point via its U/V axes.
		float su = u * 2.0 - 1.0;
		float sv = v * 2.0 - 1.0;
		vec3 sample_position = light.position + light.areaU * su + light.areaV * sv;

		vec3 to_sample = sample_position - world_position;
		float distance = length(to_sample);
		vec3 sample_direction = to_sample / max(distance, 0.0001);

		// The emitter's OWN cosine falloff: a flat emissive surface (a lit
		// window) radiates strongest straight out along its own normal and
		// tapers to nothing at a glancing angle — unlike a point light,
		// which radiates equally in every direction. This is the
		// "weighting by the emitter's cosine at the sample" this session's
		// task asks for.
		float emitter_cosine = max(dot(-sample_direction, light.direction), 0.0);
		if (emitter_cosine <= 0.0) continue; // fragment is behind/edge-on to the window; this sample contributes nothing

		float attenuation = 1.0 / (light.constantAttenuation + light.linearAttenuation * distance + light.quadraticAttenuation * distance * distance);

		float diffuse_factor = max(dot(normal, sample_direction), 0.0);
		vec3 half_vector = normalize(sample_direction + view_direction);
		float specular_factor = pow(max(dot(normal, half_vector), 0.0), shininess);

		vec3 diffuse = diffuse_factor * base_color * light.color;
		vec3 specular = specular_strength * specular_factor * light.color;

		total += attenuation * emitter_cosine * (diffuse + specular);
	}

	// Average over N samples — Monte Carlo's 1/N weighting, this session's
	// task asks for explicitly — then scale by the light's own intensity,
	// same as every other light type.
	return light.intensity * total / float(sample_count);
}

// compute_lighting is the ONE function CLAUDE.md §6.1 requires — "callable
// from either the vertex or fragment stage" (Gouraud vs. Phong, roadmap
// step 7) — summing every active light's contribution plus the scene's
// global ambient term and this material's own emission.
vec3 compute_lighting(vec3 normal, vec3 world_position, vec3 base_color, float specular_strength, float shininess, vec3 emission_color) {
	vec3 view_direction = normalize(u_ViewPosition - world_position);
	vec3 ambient = u_AmbientStrength * u_AmbientColor * base_color;

	vec3 lit = vec3(0.0);
	int light_count = min(u_ActiveLightCount, MAX_LIGHTS);
	for (int i = 0; i < light_count; i++) {
		if (!u_Lights[i].enabled) continue;
		if (u_Lights[i].type == LIGHT_TYPE_AREA) {
			lit += area_light_contribution(u_Lights[i], normal, world_position, view_direction, base_color, specular_strength, shininess);
		} else {
			lit += light_contribution(u_Lights[i], normal, world_position, view_direction, base_color, specular_strength, shininess);
		}
	}

	return ambient + lit + emission_color;
}

void main() {
	vec3 normal = normalize(v_WorldNormal);
	vec3 result = compute_lighting(normal, v_WorldPosition, u_BaseColor, u_SpecularStrength, u_Shininess, u_EmissionColor);
	FragColor = vec4(result, 1.0);
}
