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
// Roadmap step 7 (Prompts.md Session 10, CLAUDE.md §6.1): flat/Gouraud/
// Phong shading, switchable live (Source/Main.odin, keys 1/2/3). GLSL has
// no #include and this file's two stages are compiled SEPARATELY (see the
// note above) — this project's own earlier sessions already flagged that
// "one shared lighting function, callable from either stage" would mean
// duplicating that function's TEXT into both stages when this day came,
// not a text section both stages draw from automatically. That's exactly
// what happened below: the Light struct, light_contribution,
// area_light_contribution, hash21, and compute_lighting are written out
// TWICE, once per stage, byte-for-byte identical except ONE line (the area
// light jitter seed — see area_light_contribution's own comment for why
// that one line can't be identical). Keep both copies in sync by hand if
// the lighting math ever changes.

#version 330 core

#shader vertex

// Vertex stage.
layout (location = 0) in vec3 a_Position;
layout (location = 1) in vec3 a_Normal;

uniform mat4 u_MVP;
uniform mat4 u_Model;
uniform mat3 u_NormalMatrix;

// Shading mode (CLAUDE.md §6.1) — FLAT and GOURAUD both need the full
// lighting result evaluated HERE, per vertex; PHONG needs only the raw
// normal/position (evaluated per fragment instead, in the fragment stage
// below). u_ShadingMode is the SAME uniform read in both stages.
#define SHADING_FLAT 0
#define SHADING_GOURAUD 1
#define SHADING_PHONG 2
uniform int u_ShadingMode;

// Per-object material (Scene.Material, uploaded once per draw call from
// Scene.Draw_Node) — needed here now too (not just in the fragment stage)
// since FLAT/GOURAUD evaluate the full lighting equation at this stage.
uniform vec3 u_BaseColor;
uniform float u_SpecularStrength;
uniform float u_Shininess;
uniform vec3 u_EmissionColor;

out vec3 v_WorldPosition;
out vec3 v_WorldNormal;
// FLAT's result: qualified `flat`, so the rasterizer takes only the
// PROVOKING vertex's value for an entire triangle (this build never calls
// glProvokingVertex, so OpenGL's default applies — GL_LAST_VERTEX_
// CONVENTION, the LAST vertex of each triangle in the index buffer). For
// this project's ordinary faceted geometry every vertex of one face already
// shares the same normal (Library/Geometry/Geometry.odin's per-face vertex
// duplication), so any of the 3 would give the same answer — the choice
// only matters on the "a few curved parts" this session gives smooth
// per-vertex normals (Geometry.Smooth_Cylinder_Normals), where FLAT mode
// deliberately falls back to ONE representative normal per triangle
// instead of the smooth ones, which is the whole point of comparing it
// against GOURAUD/PHONG on those exact parts.
flat out vec3 v_FlatColor;
// GOURAUD's result: default (smooth) qualifier, so the rasterizer
// interpolates all 3 vertices' values linearly across the triangle — the
// textbook definition of Gouraud shading (light the vertices, interpolate
// the COLOUR, as opposed to Phong's "interpolate the NORMAL, light the
// fragment").
out vec3 v_GouraudColor;

// ---------------------------------------------------------------------------
// Shared lighting code — VERTEX STAGE COPY. See this file's header comment.
// ---------------------------------------------------------------------------

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
// How many of u_Lights[0..u_ActiveLightCount) to actually examine this
// frame (Library/Lights.Upload sets this to how many light SLOTS it
// uploaded, not strictly a count of `enabled == true` ones — see that
// proc's own comment). light_contribution below still checks each light's
// own `enabled` flag, so a disabled light inside that range correctly
// contributes nothing rather than being silently assumed absent.
uniform int u_ActiveLightCount;

// Roadmap step 6 (CLAUDE.md §6.3) runtime controls — Source/Main.odin's
// +/- keys (sample count) and J key (jitter toggle), or --area-samples/
// --area-jitter for a --capture run. MAX_AREA_SAMPLES must match
// Library/Lights.MAX_AREA_LIGHT_SAMPLES — same "kept in sync by hand"
// situation as MAX_LIGHTS above.
#define MAX_AREA_SAMPLES 8
uniform int u_AreaLightSampleCount;
uniform bool u_AreaLightJitter;

// Global ambient term — a single scene-wide approximation of indirect/
// bounced light, NOT summed once per active light. See u_AmbientColor's
// fragment-stage copy below for the full reasoning (identical here).
uniform vec3 u_AmbientColor;
uniform float u_AmbientStrength;

uniform vec3 u_ViewPosition;

// hash21 is a cheap, fully deterministic pseudo-random function computed
// from its input ALONE — no noise texture, no lookup table (CLAUDE.md §2
// item 5's "no precomputed data" applies to a jitter pattern exactly as
// much as it does to geometry). The classic "sine-fract" shader hash.
float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// light_contribution computes ONE light's diffuse (Lambert) + specular
// (Blinn-Phong half-vector) contribution, already scaled by that light's
// own distance attenuation and (for spot lights) cone falloff.
vec3 light_contribution(Light light, vec3 normal, vec3 world_position, vec3 view_direction, vec3 base_color, float specular_strength, float shininess) {
	vec3 to_light;
	float attenuation = 1.0;

	if (light.type == LIGHT_TYPE_DIRECTIONAL) {
		to_light = normalize(-light.direction);
	} else {
		vec3 light_vector = light.position - world_position;
		float distance = length(light_vector);
		to_light = light_vector / max(distance, 0.0001);
		attenuation = 1.0 / (light.constantAttenuation + light.linearAttenuation * distance + light.quadraticAttenuation * distance * distance);
	}

	if (light.type == LIGHT_TYPE_SPOT) {
		vec3 spot_axis = normalize(light.direction);
		float cone_cos = dot(-to_light, spot_axis);
		attenuation *= smoothstep(light.outerConeCos, light.innerConeCos, cone_cos);
	}

	float diffuse_factor = max(dot(normal, to_light), 0.0);
	vec3 half_vector = normalize(to_light + view_direction);
	float specular_factor = pow(max(dot(normal, half_vector), 0.0), shininess);

	vec3 diffuse = diffuse_factor * base_color * light.color;
	vec3 specular = specular_strength * specular_factor * light.color;

	return attenuation * light.intensity * (diffuse + specular);
}

// area_light_contribution approximates a Lambertian emissive QUAD light by
// averaging N point-light-style samples spread across it — see the
// fragment stage's copy of this function for the full Monte-Carlo-sampler
// explanation (identical reasoning here). ONE difference from that copy:
// the per-pixel jitter seed. The fragment stage can key its jitter off
// gl_FragCoord (the actual screen pixel), which decorrelates neighbouring
// PIXELS; gl_FragCoord doesn't exist in the vertex stage at all, so this
// copy keys its jitter off the vertex's own world position instead, which
// decorrelates neighbouring VERTICES. Both achieve the same goal (trade
// the stratified grid's regular banding for noise) using whichever
// per-invocation identity each stage actually has access to.
vec3 area_light_contribution(Light light, vec3 normal, vec3 world_position, vec3 view_direction, vec3 base_color, float specular_strength, float shininess) {
	int sample_count = clamp(u_AreaLightSampleCount, 1, MAX_AREA_SAMPLES);
	int grid_size = int(ceil(sqrt(float(sample_count))));

	vec3 total = vec3(0.0);
	for (int i = 0; i < sample_count; i++) {
		int cell_x = i % grid_size;
		int cell_y = i / grid_size;

		float u = (float(cell_x) + 0.5) / float(grid_size);
		float v = (float(cell_y) + 0.5) / float(grid_size);

		if (u_AreaLightJitter) {
			vec2 seed = world_position.xz * 91.7 + vec2(float(i) * 13.7, float(i) * 91.3);
			u += (hash21(seed) - 0.5) / float(grid_size);
			v += (hash21(seed + 17.0) - 0.5) / float(grid_size);
		}

		float su = u * 2.0 - 1.0;
		float sv = v * 2.0 - 1.0;
		vec3 sample_position = light.position + light.areaU * su + light.areaV * sv;

		vec3 to_sample = sample_position - world_position;
		float distance = length(to_sample);
		vec3 sample_direction = to_sample / max(distance, 0.0001);

		float emitter_cosine = max(dot(-sample_direction, light.direction), 0.0);
		if (emitter_cosine <= 0.0) continue;

		float attenuation = 1.0 / (light.constantAttenuation + light.linearAttenuation * distance + light.quadraticAttenuation * distance * distance);

		float diffuse_factor = max(dot(normal, sample_direction), 0.0);
		vec3 half_vector = normalize(sample_direction + view_direction);
		float specular_factor = pow(max(dot(normal, half_vector), 0.0), shininess);

		vec3 diffuse = diffuse_factor * base_color * light.color;
		vec3 specular = specular_strength * specular_factor * light.color;

		total += attenuation * emitter_cosine * (diffuse + specular);
	}

	return light.intensity * total / float(sample_count);
}

// compute_lighting is the ONE function CLAUDE.md §6.1 requires — "callable
// from either the vertex or fragment stage." Summed here in the VERTEX
// stage for FLAT/GOURAUD; the fragment stage's identical copy is used for
// PHONG instead (see that stage's main() for the mode switch).
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
	gl_Position = u_MVP * vec4(a_Position, 1.0);
	v_WorldPosition = vec3(u_Model * vec4(a_Position, 1.0));
	// u_NormalMatrix is the inverse-transpose of u_Model's upper-left 3x3
	// (Scene.Normal_Matrix, computed CPU-side every frame from the node's
	// live world matrix — CLAUDE.md §5.3), so normals stay correct even
	// under a non-uniform scale (e.g. the watchtower roof's tilted slabs).
	v_WorldNormal = normalize(u_NormalMatrix * a_Normal);

	// Only do the (relatively expensive, N-light) lighting work here when
	// this frame's mode actually needs it — PHONG evaluates it per
	// fragment instead, and would just be throwing this away.
	if (u_ShadingMode != SHADING_PHONG) {
		vec3 lit = compute_lighting(v_WorldNormal, v_WorldPosition, u_BaseColor, u_SpecularStrength, u_Shininess, u_EmissionColor);
		v_FlatColor = lit;
		v_GouraudColor = lit;
	} else {
		v_FlatColor = vec3(0.0);
		v_GouraudColor = vec3(0.0);
	}
}

#shader fragment

// Fragment stage. Roadmap step 8 (CLAUDE.md §4/§9, Prompts.md Session 11)
// is implemented below: manual back-face culling, a back-face debug tint,
// and a hand-linearised depth-buffer visualisation — see the "Roadmap step
// 8" block further down for all of it and why it's fragment-stage-only.
// Remaining planned responsibility (CLAUDE.md §6.2; Plan.md §5.2; Prompts.md
// Session 14): the one genuinely ray-traced surface (tank periscope or jeep
// windshield) — reflection ray against uniform proxy shapes rebuilt each
// frame from live object transforms, analytic intersection, shade the hit
// with compute_lighting below.
in vec3 v_WorldPosition;
in vec3 v_WorldNormal;
flat in vec3 v_FlatColor;
in vec3 v_GouraudColor;

out vec4 FragColor;

#define SHADING_FLAT 0
#define SHADING_GOURAUD 1
#define SHADING_PHONG 2
uniform int u_ShadingMode;

// Per-object material (Scene.Material, uploaded once per draw call from
// Scene.Draw_Node) — base colour, specular strength/shininess, and an
// emission colour for parts that should read as "lit" on their own (window/
// windshield/periscope glass, the floodlight housing, the radar beacon,
// and every Library/Lights debug gizmo).
uniform vec3 u_BaseColor;
uniform float u_SpecularStrength;
uniform float u_Shininess;
uniform vec3 u_EmissionColor;

uniform vec3 u_ViewPosition;

// Global ambient term — a single scene-wide approximation of indirect/
// bounced light, NOT summed once per active light. Read literally, "ambient
// + diffuse + specular + emission, summed over all lights" (an earlier
// session's task text) would make ambient brightness scale with how many
// lights happen to be active, which has no physical meaning and would wash
// out the night scene's shadows as this project's light count grew toward
// 21. Every other renderer taught by this course's Blinn-Phong model
// treats ambient the same way: one global fill term, independent of light
// count. Uploaded once per frame from Source/Main.odin's AMBIENT_COLOR/
// AMBIENT_STRENGTH.
uniform vec3 u_AmbientColor;
uniform float u_AmbientStrength;

// ---------------------------------------------------------------------------
// Roadmap step 8 (Prompts.md Session 11, CLAUDE.md §4/§9): back-face culling
// and hidden-surface-removal demonstrations. All of this lives in the
// FRAGMENT stage only, unlike compute_lighting above (genuinely shared by
// both stages) — classifying ONE fragment as front- or back-facing needs
// the interpolated per-fragment normal/position that only exists here.
// ---------------------------------------------------------------------------

#define CULL_OFF 0
#define CULL_MANUAL 1
#define CULL_GL 2
// u_CullMode's three states, in plain language (what problem each solves,
// how, and its cost):
//   OFF    — draws every triangle, front AND back. Nothing removes a back
//            face at all; deliberately left this way so item 2 below (the
//            backface-debug tint) has something to demonstrate.
//   MANUAL — this shader decides, PER FRAGMENT, whether the triangle it
//            belongs to faces the eye or away from it (is_back_facing
//            below) and discards the ones that face away — reaching the
//            SAME final image as hardware culling. Cost: the rasterizer and
//            this fragment shader still RUN for every back-facing fragment
//            before discarding it, so none of hardware culling's actual
//            performance saving applies here — it exists to prove the two
//            methods agree, not to be faster (Source/Main.odin's triangle-
//            count log talks about the real saving GL mode gets instead).
//   GL     — Source/Main.odin calls gl.Enable(gl.CULL_FACE)/gl.CullFace
//            instead of setting this to MANUAL. The GPU's rasterizer
//            throws a back-facing triangle away, by its winding order,
//            BEFORE this fragment shader ever runs for it — this is where
//            the real ~50% saving in fragment-shader invocations for a
//            closed, roughly-convex object comes from. This shader's own
//            is_back_facing test still runs in this mode too (cheap, and
//            needed for the backface-debug tint below regardless of
//            u_CullMode), but the MANUAL discard branch is simply never hit
//            here: a back-facing fragment never arrives at all.
uniform int u_CullMode;

// Direction to the eye is NOT the same formula in both projections — this
// session's own explicit ask ("handle orthographic mode correctly"). In
// PERSPECTIVE, the eye is a single point (u_ViewPosition) a FINITE distance
// away, so every fragment's ray toward it points a slightly different way:
// normalize(u_ViewPosition - world_position), recomputed per fragment
// (compute_lighting's own view_direction, below, already does exactly
// this). In ORTHOGRAPHIC, the eye is conceptually infinitely far away along
// the camera's own forward axis, so every view ray is PARALLEL — direction
// to the eye is the SAME constant vector everywhere on screen (the negated
// camera forward), independent of world_position entirely. u_ViewDirection
// is that camera-forward vector (Library/Camera.Forward), uploaded once per
// frame from Source/Main.odin; u_IsOrthographic picks which formula below
// applies, and stays correct across a live projection toggle (key P)
// because both uniforms are re-uploaded fresh every frame, never cached.
uniform vec3 u_ViewDirection;
uniform bool u_IsOrthographic;

// Item 2's teaching aid: this fragment's colour becomes magenta instead of
// its normal shaded colour when it belongs to a back-facing triangle —
// independent of u_CullMode's own discard behaviour, so it can be turned on
// together with culling OFF and the depth test OFF (Source/Main.odin's Z
// key) to make an otherwise ambiguous jumble of overlapping front/back
// faces legible: every magenta triangle is exactly the geometry that either
// culling mode would normally have hidden.
uniform bool u_BackfaceDebug;

// Item 3: replaces this fragment's colour with a grayscale visualisation of
// its OWN depth-buffer value instead of its lit colour — see main() below
// for the hand-derived linearisation and why perspective/orthographic need
// different formulas. u_Near/u_Far mirror the Camera's own near/far planes
// (Library/Camera.Camera.near/far), uploaded once per frame — needed
// because gl_FragCoord.z alone is either a non-linear (perspective) or an
// already-linear-but-oddly-scaled (orthographic) value, not a plain world-
// space distance a grayscale image can show directly.
uniform bool u_DepthVisualization;
uniform float u_Near;
uniform float u_Far;

// ---------------------------------------------------------------------------
// Shared lighting code — FRAGMENT STAGE COPY. See this file's header
// comment; identical to the vertex stage's copy above except the jitter
// seed line inside area_light_contribution (that function's own comment
// explains why it can't be identical).
// ---------------------------------------------------------------------------

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
uniform int u_ActiveLightCount;

#define MAX_AREA_SAMPLES 8
uniform int u_AreaLightSampleCount;
uniform bool u_AreaLightJitter;

// hash21 is a cheap, fully deterministic pseudo-random function computed
// from its input ALONE — no noise texture, no lookup table. The classic
// "sine-fract" shader hash: irrational-ish magic constants inside a
// high-frequency sin() so nearby inputs decorrelate quickly, then fract()
// throws away everything but the noisy low bits.
float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// light_contribution computes ONE light's diffuse (Lambert) + specular
// (Blinn-Phong half-vector) contribution, already scaled by that light's
// own distance attenuation and (for spot lights) cone falloff — everything
// a plain point/spot/directional light needs. Diffuse tints by the
// surface's own base colour; specular does NOT (a highlight is the LIGHT's
// colour reflecting off the surface, not the surface's colour, for the
// dielectric materials used throughout this scene — the standard
// Blinn-Phong convention).
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
		// inner cosines gives a smooth falloff instead of a hard on/off
		// edge at the cone boundary.
		vec3 spot_axis = normalize(light.direction);
		float cone_cos = dot(-to_light, spot_axis);
		attenuation *= smoothstep(light.outerConeCos, light.innerConeCos, cone_cos);
	}

	float diffuse_factor = max(dot(normal, to_light), 0.0);
	vec3 half_vector = normalize(to_light + view_direction);
	float specular_factor = pow(max(dot(normal, half_vector), 0.0), shininess);

	vec3 diffuse = diffuse_factor * base_color * light.color;
	vec3 specular = specular_strength * specular_factor * light.color;

	return attenuation * light.intensity * (diffuse + specular);
}

// area_light_contribution approximates a Lambertian emissive QUAD light
// (Library/Lights.Make_Area — a barracks window) by averaging N
// point-light-style samples spread across it. This is a SIMPLIFIED,
// SINGLE-BOUNCE MONTE CARLO integrator: real Monte Carlo area-light
// sampling (and, by extension, path tracing's own direct-light step)
// estimates the light arriving at a point by drawing random samples over
// the emitter and averaging their contribution, weighted by how the
// emitter's own surface faces each sample direction — exactly what the
// loop below does. It stays "simplified" in three ways: (1) single-bounce
// only — light -> this fragment directly, never light -> another surface
// -> this fragment; (2) no per-sample visibility/shadow test — every
// sample is assumed unoccluded, since this project has no shadow map or
// general ray-cast visibility pass (CLAUDE.md §6.2's real ray casting is
// scoped to one reflective surface, not shadow testing for every
// fragment); (3) N is small and fixed per frame (1-8), traded for
// real-time speed over noise-free convergence.
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
			// pixel, so neighbouring pixels get DIFFERENT jitter even on
			// the same flat surface — trades the stratified grid's
			// regular banding for noise instead. The vertex stage's copy
			// of this function keys off world position instead, since
			// gl_FragCoord doesn't exist there (see that copy's comment).
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
		// which radiates equally in every direction.
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

	// Average over N samples — Monte Carlo's 1/N weighting — then scale by
	// the light's own intensity, same as every other light type.
	return light.intensity * total / float(sample_count);
}

// compute_lighting is the ONE function CLAUDE.md §6.1 requires — "callable
// from either the vertex or fragment stage" (Gouraud vs. Phong) — summing
// every active light's contribution plus the scene's global ambient term
// and this material's own emission. Used here for PHONG only; FLAT/GOURAUD
// use the vertex stage's identical copy instead (see that stage's main()).
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
	// --- Roadmap step 8: back-face classification, done once per fragment
	// here, shared by MANUAL culling's discard, the backface-debug tint,
	// and (implicitly) GL_CULL_FACE mode — see u_CullMode's own comment for
	// why a back-facing fragment simply never reaches this shader at all in
	// that last mode.
	vec3 normal = normalize(v_WorldNormal);
	vec3 direction_to_eye = u_IsOrthographic
		? -normalize(u_ViewDirection)
		: normalize(u_ViewPosition - v_WorldPosition);
	bool is_back_facing = dot(normal, direction_to_eye) < 0.0;

	if (u_CullMode == CULL_MANUAL && is_back_facing) {
		// Same final IMAGE as GL_CULL_FACE (this fragment never appears in
		// the framebuffer) but not the same performance cost — see
		// u_CullMode's own comment above.
		discard;
	}

	// Item 3: an alternate full-screen debug view — grayscale linearised
	// depth instead of lit colour, for every fragment that reaches this
	// point (i.e. survived the MANUAL discard above, same as any other
	// mode would draw).
	if (u_DepthVisualization) {
		// gl_FragCoord.z is WINDOW-space depth, always in [0, 1] regardless
		// of the clip-space convention the projection matrix itself uses
		// (OpenGL's default glDepthRange maps NDC z in [-1, 1] to window
		// depth in [0, 1] linearly) — undo that mapping first to recover
		// the NDC z this project's own convention actually produces
		// (Library/Camera/Camera.odin's header comment: near -> -1,
		// far -> +1).
		float depth_ndc = gl_FragCoord.z * 2.0 - 1.0;

		float linear_depth;
		if (u_IsOrthographic) {
			// Orthographic projection has NO perspective divide, so NDC z
			// is ALREADY linear in view-space distance — "linearising" it
			// here is just an affine remap back to [near, far], not the
			// perspective un-projection below.
			linear_depth = u_Near + (depth_ndc + 1.0) * 0.5 * (u_Far - u_Near);
		} else {
			// The textbook perspective depth-linearisation formula: NDC z
			// is a HYPERBOLIC function of view-space distance (the
			// projection matrix divides by w = -view_z), so this inverts
			// that specific hyperbola by hand rather than sampling a
			// second depth-texture pass — gl_FragCoord.z already IS this
			// fragment's own depth-buffer value.
			linear_depth = (2.0 * u_Near * u_Far) / (u_Far + u_Near - depth_ndc * (u_Far - u_Near));
		}

		float normalized_depth = clamp((linear_depth - u_Near) / (u_Far - u_Near), 0.0, 1.0);
		FragColor = vec4(vec3(normalized_depth), 1.0);
		return;
	}

	vec3 result;
	if (u_ShadingMode == SHADING_FLAT) {
		// v_FlatColor already IS the final colour (computed once per
		// triangle in the vertex stage, taken from the provoking vertex by
		// the `flat` qualifier) — nothing left to do per fragment.
		result = v_FlatColor;
	} else if (u_ShadingMode == SHADING_GOURAUD) {
		// v_GouraudColor is the smooth INTERPOLATION of the 3 vertices'
		// already-computed colours — also nothing left to do per fragment.
		// This is exactly where Gouraud's known failure mode shows up: if
		// a spotlight's hot centre falls INSIDE a large triangle, none of
		// its 3 corners were anywhere near bright, so interpolating
		// between 3 dim corner values can never reconstruct a bright spot
		// in the middle — see Source/Main.odin's ground-grid resolution
		// toggle (key G), built specifically to demonstrate this.
		result = v_GouraudColor;
	} else {
		// PHONG: interpolate the NORMAL (smooth `in vec3 v_WorldNormal`
		// above already did that, automatically, just by being a
		// non-flat varying) and evaluate the full lighting equation fresh
		// at every fragment — current behaviour from before this session,
		// unchanged.
		result = compute_lighting(normal, v_WorldPosition, u_BaseColor, u_SpecularStrength, u_Shininess, u_EmissionColor);
	}

	if (u_BackfaceDebug && is_back_facing) {
		// Overrides whatever shading mode just computed — see
		// u_BackfaceDebug's own comment above for when this is actually
		// visible (culling OFF; MANUAL already discarded these fragments
		// above, and GL mode never delivers them to this shader at all).
		result = vec3(1.0, 0.0, 1.0); // magenta
	}

	FragColor = vec4(result, 1.0);
}
