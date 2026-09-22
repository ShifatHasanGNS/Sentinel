// Scene.glsl — combined vertex+fragment shader source (Library/Engine/Shader.New splits on "#shader" markers).

#version 330 core

#shader vertex

// Vertex stage.
layout (location = 0) in vec3 a_Position;
layout (location = 1) in vec3 a_Normal;

uniform mat4 u_MVP;
uniform mat4 u_Model;
uniform mat3 u_NormalMatrix;

// Flat/Gouraud evaluate lighting here per vertex; Phong does it per fragment instead.
#define SHADING_FLAT 0
#define SHADING_GOURAUD 1
#define SHADING_PHONG 2
uniform int u_ShadingMode;

uniform vec3 u_BaseColor;
uniform float u_SpecularStrength;
uniform float u_Shininess;
uniform vec3 u_EmissionColor;

out vec3 v_WorldPosition;
out vec3 v_WorldNormal;
flat out vec3 v_FlatColor;  // one colour per triangle (provoking vertex)
out vec3 v_GouraudColor;    // smooth-interpolated per-vertex colour

// --- Shared lighting code — VERTEX STAGE COPY ---

#define MAX_LIGHTS 32 // must match Library/Lights.MAX_LIGHTS

#define LIGHT_TYPE_DIRECTIONAL 0
#define LIGHT_TYPE_POINT 1
#define LIGHT_TYPE_SPOT 2
#define LIGHT_TYPE_AREA 3

struct Light {
	int type;
	vec3 position;
	vec3 direction;
	vec3 areaU;
	vec3 areaV;
	vec3 color;
	float intensity;
	float constantAttenuation;
	float linearAttenuation;
	float quadraticAttenuation;
	float innerConeCos;
	float outerConeCos;
	bool enabled;
};

uniform Light u_Lights[MAX_LIGHTS];
uniform int u_ActiveLightCount;

#define MAX_AREA_SAMPLES 8 // must match Library/Lights.MAX_AREA_LIGHT_SAMPLES
uniform int u_AreaLightSampleCount;
uniform bool u_AreaLightJitter;

uniform vec3 u_AmbientColor;
uniform float u_AmbientStrength;

uniform vec3 u_ViewPosition;

// sine-fract hash, no texture/lookup table
float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// one light's Lambert diffuse + Blinn-Phong specular, with attenuation/cone falloff
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

// Monte-Carlo area-light sample: averages N point-style samples across the quad (jitter seed keyed off world position here; fragment copy uses gl_FragCoord instead)
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

// ambient + all active lights + emission
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
	v_WorldNormal = normalize(u_NormalMatrix * a_Normal);

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

// Fragment stage.
in vec3 v_WorldPosition;
in vec3 v_WorldNormal;
flat in vec3 v_FlatColor;
in vec3 v_GouraudColor;

out vec4 FragColor;

#define SHADING_FLAT 0
#define SHADING_GOURAUD 1
#define SHADING_PHONG 2
uniform int u_ShadingMode;

uniform vec3 u_BaseColor;
uniform float u_SpecularStrength;
uniform float u_Shininess;
uniform vec3 u_EmissionColor;

// [PROGRESS-DEMO] Temporary, branch-only (`progress_objects`) toggle: when
// true, main() below returns a fragment's own flat u_BaseColor immediately,
// before ANY lighting, shading-mode, reflection, or polish-pass code runs
// — a plain, unlit view of the procedural geometry/transforms only, for a
// progress check that precedes the illumination-model section of the
// syllabus. Not present on `main`; delete this whole branch to remove it
// rather than trying to hand-revert it. See Source/Main.odin's
// DEFAULT_OBJECTS_ONLY_MODE for where this is forced on.
uniform bool u_ObjectsOnlyMode;

uniform vec3 u_ViewPosition;

// global ambient fill term, independent of light count
uniform vec3 u_AmbientColor;
uniform float u_AmbientStrength;

// --- Roadmap step 8: back-face culling / hidden-surface-removal debug views ---

#define CULL_OFF 0
#define CULL_MANUAL 1
#define CULL_GL 2
// OFF: draws everything. MANUAL: shader discards back-facing fragments itself (same image as GL, no perf win). GL: hardware culls before the fragment shader runs (the real ~50% saving).
uniform int u_CullMode;

// perspective: per-fragment direction to eye. orthographic: one constant direction (camera forward) for the whole screen.
uniform vec3 u_ViewDirection;
uniform bool u_IsOrthographic;

// tints back-facing fragments magenta, independent of culling
uniform bool u_BackfaceDebug;

// grayscale linearised depth-buffer view instead of lit colour
uniform bool u_DepthVisualization;
uniform float u_Near;
uniform float u_Far;

// --- Roadmap step 11: ray-traced reflection off proxy shapes ---

uniform bool u_IsReflectiveSurface;
uniform bool u_RayTracedReflectionEnabled;
uniform vec3 u_SkyColor; // reflection-miss colour, matches CLEAR_COLOR

#define PROXY_SPHERE 0
#define PROXY_BOX 1
#define PROXY_CYLINDER 2
#define MAX_PROXIES 16

// mirrors Source/Reflection.odin's Proxy struct
struct Proxy {
	int type;
	vec3 center;
	mat4 inverseWorld;
	vec3 halfExtents;
	vec3 color;
};

uniform Proxy u_Proxies[MAX_PROXIES];
uniform int u_ProxyCount;

// --- Polish pass toggles ---

uniform bool u_TonemappingEnabled;
uniform bool u_VignetteEnabled;
uniform vec2 u_Resolution;
uniform bool u_FogEnabled;
uniform bool u_IsGround;
uniform bool u_IsSky;
uniform float u_Time;

// --- Shared lighting code — FRAGMENT STAGE COPY ---

#define MAX_LIGHTS 32 // must match Library/Lights.MAX_LIGHTS

#define LIGHT_TYPE_DIRECTIONAL 0
#define LIGHT_TYPE_POINT 1
#define LIGHT_TYPE_SPOT 2
#define LIGHT_TYPE_AREA 3

struct Light {
	int type;
	vec3 position;
	vec3 direction;
	vec3 areaU;
	vec3 areaV;
	vec3 color;
	float intensity;
	float constantAttenuation;
	float linearAttenuation;
	float quadraticAttenuation;
	float innerConeCos;
	float outerConeCos;
	bool enabled;
};

uniform Light u_Lights[MAX_LIGHTS];
uniform int u_ActiveLightCount;

#define MAX_AREA_SAMPLES 8
uniform int u_AreaLightSampleCount;
uniform bool u_AreaLightJitter;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// specular does NOT tint by surface colour — a highlight is the light's own colour
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

// simplified single-bounce Monte Carlo area light: no shadow test, small fixed N (1-8)
vec3 area_light_contribution(Light light, vec3 normal, vec3 world_position, vec3 view_direction, vec3 base_color, float specular_strength, float shininess) {
	int sample_count = clamp(u_AreaLightSampleCount, 1, MAX_AREA_SAMPLES);
	int grid_size = int(ceil(sqrt(float(sample_count)))); // stratified grid sized to sample_count

	vec3 total = vec3(0.0);
	for (int i = 0; i < sample_count; i++) {
		int cell_x = i % grid_size;
		int cell_y = i / grid_size;

		float u = (float(cell_x) + 0.5) / float(grid_size);
		float v = (float(cell_y) + 0.5) / float(grid_size);

		if (u_AreaLightJitter) {
			// per-pixel jitter via gl_FragCoord
			vec2 seed = gl_FragCoord.xy + vec2(float(i) * 13.7, float(i) * 91.3);
			u += (hash21(seed) - 0.5) / float(grid_size);
			v += (hash21(seed + 17.0) - 0.5) / float(grid_size);
		}

		float su = u * 2.0 - 1.0;
		float sv = v * 2.0 - 1.0;
		vec3 sample_position = light.position + light.areaU * su + light.areaV * sv;

		vec3 to_sample = sample_position - world_position;
		float distance = length(to_sample);
		vec3 sample_direction = to_sample / max(distance, 0.0001);

		// emitter's own cosine falloff (flat emissive surface, not omnidirectional)
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

// Ray tracing: primary ray = implicit (this fragment). Secondary ray = reflect() below. Intersection tests = analytic, against small proxy array. Shading at hit = compute_lighting again.

float intersect_sphere(vec3 ray_origin, vec3 ray_dir, vec3 center, float radius) {
	vec3 oc = ray_origin - center;
	float b = dot(oc, ray_dir);
	float c = dot(oc, oc) - radius*radius;
	float discriminant = b*b - c;
	if (discriminant < 0.0) return -1.0;

	float sqrt_disc = sqrt(discriminant);
	float t0 = -b - sqrt_disc;
	float t1 = -b + sqrt_disc;
	if (t0 > 0.001) return t0;
	if (t1 > 0.001) return t1;
	return -1.0;
}

// slab method, in the proxy's own local space
float intersect_box_local(vec3 local_origin, vec3 local_dir, vec3 half_extents) {
	vec3 inv_dir = 1.0 / local_dir;
	vec3 t0s = (-half_extents - local_origin) * inv_dir;
	vec3 t1s = (half_extents - local_origin) * inv_dir;
	vec3 t_smaller = min(t0s, t1s);
	vec3 t_bigger = max(t0s, t1s);

	float t_min = max(max(t_smaller.x, t_smaller.y), t_smaller.z);
	float t_max = min(min(t_bigger.x, t_bigger.y), t_bigger.z);
	if (t_min > t_max || t_max < 0.001) return -1.0;
	return t_min > 0.001 ? t_min : t_max;
}

// capped cylinder around local Y axis
float intersect_cylinder_local(vec3 local_origin, vec3 local_dir, vec3 half_extents) {
	float radius = half_extents.x;
	float half_height = half_extents.y;
	float best_t = -1.0;

	float a = local_dir.x*local_dir.x + local_dir.z*local_dir.z;
	if (a > 1e-6) {
		float b = 2.0 * (local_origin.x*local_dir.x + local_origin.z*local_dir.z);
		float c = local_origin.x*local_origin.x + local_origin.z*local_origin.z - radius*radius;
		float discriminant = b*b - 4.0*a*c;
		if (discriminant >= 0.0) {
			float sqrt_disc = sqrt(discriminant);
			float t0 = (-b - sqrt_disc) / (2.0*a);
			float t1 = (-b + sqrt_disc) / (2.0*a);
			if (t0 > 0.001) {
				float y = local_origin.y + t0*local_dir.y;
				if (abs(y) <= half_height) best_t = t0;
			}
			if (best_t < 0.0 && t1 > 0.001) {
				float y = local_origin.y + t1*local_dir.y;
				if (abs(y) <= half_height) best_t = t1;
			}
		}
	}

	if (abs(local_dir.y) > 1e-6) {
		float t_top = (half_height - local_origin.y) / local_dir.y;
		if (t_top > 0.001) {
			vec2 p = local_origin.xz + t_top*local_dir.xz;
			if (dot(p, p) <= radius*radius && (best_t < 0.0 || t_top < best_t)) best_t = t_top;
		}
		float t_bottom = (-half_height - local_origin.y) / local_dir.y;
		if (t_bottom > 0.001) {
			vec2 p = local_origin.xz + t_bottom*local_dir.xz;
			if (dot(p, p) <= radius*radius && (best_t < 0.0 || t_bottom < best_t)) best_t = t_bottom;
		}
	}

	return best_t;
}

#define PROXY_SPECULAR_STRENGTH 0.2
#define PROXY_SHININESS 12.0

// casts the reflection ray against every proxy, shades the nearest hit, plus a hard shadow ray toward the moonlight
vec3 trace_reflection(vec3 ray_origin, vec3 ray_dir) {
	float best_t = 1e30;
	int best_index = -1;

	for (int i = 0; i < u_ProxyCount; i++) {
		Proxy proxy = u_Proxies[i];
		float t = -1.0;

		if (proxy.type == PROXY_SPHERE) {
			t = intersect_sphere(ray_origin, ray_dir, proxy.center, proxy.halfExtents.x);
		} else {
			vec3 local_origin = (proxy.inverseWorld * vec4(ray_origin, 1.0)).xyz;
			vec3 local_dir = (proxy.inverseWorld * vec4(ray_dir, 0.0)).xyz;
			t = proxy.type == PROXY_BOX
				? intersect_box_local(local_origin, local_dir, proxy.halfExtents)
				: intersect_cylinder_local(local_origin, local_dir, proxy.halfExtents);
			// local-space t -> world-space t (inverseWorld may carry a scale)
			if (t > 0.0) t /= length(local_dir);
		}

		if (t > 0.001 && t < best_t) {
			best_t = t;
			best_index = i;
		}
	}

	if (best_index < 0) return u_SkyColor;

	Proxy hit_proxy = u_Proxies[best_index];
	vec3 hit_point = ray_origin + ray_dir * best_t;

	vec3 normal;
	if (hit_proxy.type == PROXY_SPHERE) {
		normal = normalize(hit_point - hit_proxy.center);
	} else {
		vec3 local_hit = (hit_proxy.inverseWorld * vec4(hit_point, 1.0)).xyz;
		vec3 normal_local;
		if (hit_proxy.type == PROXY_BOX) {
			vec3 ratio = abs(local_hit / hit_proxy.halfExtents);
			if (ratio.x > ratio.y && ratio.x > ratio.z) normal_local = vec3(sign(local_hit.x), 0.0, 0.0);
			else if (ratio.y > ratio.z) normal_local = vec3(0.0, sign(local_hit.y), 0.0);
			else normal_local = vec3(0.0, 0.0, sign(local_hit.z));
		} else {
			float half_height = hit_proxy.halfExtents.y;
			normal_local = abs(local_hit.y) >= half_height - 0.01
				? vec3(0.0, sign(local_hit.y), 0.0)
				: normalize(vec3(local_hit.x, 0.0, local_hit.z));
		}
		normal = normalize((transpose(hit_proxy.inverseWorld) * vec4(normal_local, 0.0)).xyz);
	}

	// shadow ray toward the one directional light (moonlight)
	float shadow_factor = 1.0;
	vec3 to_moonlight = vec3(0.0);
	bool has_moonlight = false;
	for (int i = 0; i < min(u_ActiveLightCount, MAX_LIGHTS); i++) {
		if (u_Lights[i].enabled && u_Lights[i].type == LIGHT_TYPE_DIRECTIONAL) {
			to_moonlight = -normalize(u_Lights[i].direction);
			has_moonlight = true;
			break;
		}
	}
	if (has_moonlight) {
		vec3 shadow_origin = hit_point + normal * 0.02;
		for (int i = 0; i < u_ProxyCount; i++) {
			if (i == best_index) continue;
			Proxy proxy = u_Proxies[i];
			float t;
			if (proxy.type == PROXY_SPHERE) {
				t = intersect_sphere(shadow_origin, to_moonlight, proxy.center, proxy.halfExtents.x);
			} else {
				vec3 lo = (proxy.inverseWorld * vec4(shadow_origin, 1.0)).xyz;
				vec3 ld = (proxy.inverseWorld * vec4(to_moonlight, 0.0)).xyz;
				t = proxy.type == PROXY_BOX ? intersect_box_local(lo, ld, proxy.halfExtents) : intersect_cylinder_local(lo, ld, proxy.halfExtents);
			}
			if (t > 0.001) {
				shadow_factor = 0.35;
				break;
			}
		}
	}

	vec3 shaded = compute_lighting(normal, hit_point, hit_proxy.color, PROXY_SPECULAR_STRENGTH, PROXY_SHININESS, vec3(0.0));
	return shaded * shadow_factor;
}

// --- Polish pass helpers ---

float hash31(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 45.164))) * 43758.5453);
}

// bilinear value noise, smoothstep-weighted
float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));
	vec2 weight = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, weight.x), mix(c, d, weight.x), weight.y);
}

// coarse patch + fine speckle noise, tints ground colour
vec3 apply_ground_detail(vec3 color, vec3 world_position) {
	float coarse = value_noise(world_position.xz * 0.12);
	float fine = value_noise(world_position.xz * 1.3);
	float pattern = coarse * 0.65 + fine * 0.35;
	return color * mix(0.82, 1.18, pattern);
}

// exponential distance fog toward sky colour
vec3 apply_fog(vec3 color, float distance_from_camera) {
	const float FOG_DENSITY = 0.035;
	const float FOG_MAX_OPACITY = 0.85;
	float fog_factor = (1.0 - exp(-distance_from_camera * FOG_DENSITY)) * FOG_MAX_OPACITY;
	return mix(color, u_SkyColor, fog_factor);
}

// screen-space corner darkening
vec3 apply_vignette(vec3 color) {
	vec2 uv = gl_FragCoord.xy / u_Resolution;
	float dist = length(uv - vec2(0.5)) * 1.4;
	float vignette = 1.0 - smoothstep(0.5, 1.05, dist);
	return color * mix(0.55, 1.0, vignette);
}

// Reinhard tonemap + 2.2 gamma — the one place this shader leaves linear colour space
vec3 apply_tonemap_gamma(vec3 color) {
	vec3 mapped = color / (color + vec3(1.0));
	return pow(mapped, vec3(1.0 / 2.2));
}

// night-sky gradient + sparse procedural starfield, pure function of direction/time
vec3 sky_color(vec3 direction, float time) {
	float up = clamp(direction.y, -1.0, 1.0);
	vec3 zenith = u_SkyColor * 0.25;
	vec3 nadir = u_SkyColor * 0.4;
	vec3 gradient = up >= 0.0
		? mix(u_SkyColor, zenith, pow(up, 0.7))
		: mix(u_SkyColor, nadir, pow(-up, 0.7));

	// one hashed point per grid cell, not the whole cell, so stars stay a constant angular size
	vec3 stars = vec3(0.0);
	if (up > 0.02) {
		float grid = 140.0;
		vec3 cell = floor(direction * grid);
		float exists = hash31(cell);
		if (exists > 0.997) {
			vec3 jitter = vec3(hash31(cell + vec3(3.1)), hash31(cell + vec3(7.7)), hash31(cell + vec3(11.3))) - 0.5;
			vec3 star_direction = normalize((cell + 0.5 + jitter*0.6) / grid);
			float angular_distance = length(direction - star_direction);
			float star_radius = 0.0035;
			float star_mask = 1.0 - smoothstep(0.0, star_radius, angular_distance);

			float brightness = hash31(cell + vec3(17.0));
			float twinkle = 0.6 + 0.4 * sin(time * 2.0 + brightness * 6.2831853);
			float fade = smoothstep(0.02, 0.2, up);
			stars = vec3(brightness * twinkle * fade * star_mask);
		}
	}

	return gradient + stars;
}

void main() {
	// [PROGRESS-DEMO] Branch-only early exit — see u_ObjectsOnlyMode's own
	// comment above. Deliberately the VERY FIRST thing in main(), before
	// even u_DepthVisualization: nothing below this line (lighting, shading
	// mode, ray-traced reflection, ground/fog/vignette/sky/tonemap) ever
	// runs while this is on, which is the whole point — a flat, unlit view
	// of whatever geometry/transforms the rest of the pipeline produced.
	if (u_ObjectsOnlyMode) {
		FragColor = vec4(u_BaseColor, 1.0);
		return;
	}

	// depth-visualisation debug view, checked before the sky branch so it applies uniformly
	if (u_DepthVisualization) {
		float depth_ndc = gl_FragCoord.z * 2.0 - 1.0;

		float linear_depth;
		if (u_IsOrthographic) {
			linear_depth = u_Near + (depth_ndc + 1.0) * 0.5 * (u_Far - u_Near);
		} else {
			linear_depth = (2.0 * u_Near * u_Far) / (u_Far + u_Near - depth_ndc * (u_Far - u_Near));
		}

		float normalized_depth = clamp((linear_depth - u_Near) / (u_Far - u_Near), 0.0, 1.0);
		FragColor = vec4(vec3(normalized_depth), 1.0);
		return;
	}

	// sky dome: entirely separate shading path, skips scene lighting
	if (u_IsSky) {
		vec3 direction = normalize(v_WorldPosition - u_ViewPosition);
		vec3 sky_result = sky_color(direction, u_Time);
		if (u_VignetteEnabled) sky_result = apply_vignette(sky_result);
		if (u_TonemappingEnabled) sky_result = apply_tonemap_gamma(sky_result);
		FragColor = vec4(sky_result, 1.0);
		return;
	}

	vec3 normal = normalize(v_WorldNormal);
	vec3 direction_to_eye = u_IsOrthographic
		? -normalize(u_ViewDirection)
		: normalize(u_ViewPosition - v_WorldPosition);
	bool is_back_facing = dot(normal, direction_to_eye) < 0.0;

	if (u_CullMode == CULL_MANUAL && is_back_facing) {
		discard;
	}

	vec3 result;
	if (u_ShadingMode == SHADING_FLAT) {
		result = v_FlatColor;
	} else if (u_ShadingMode == SHADING_GOURAUD) {
		result = v_GouraudColor;
	} else {
		result = compute_lighting(normal, v_WorldPosition, u_BaseColor, u_SpecularStrength, u_Shininess, u_EmissionColor);
	}

	if (u_IsReflectiveSurface && u_RayTracedReflectionEnabled) {
		vec3 incident = normalize(v_WorldPosition - u_ViewPosition);
		vec3 reflect_direction = reflect(incident, normal);
		vec3 reflect_origin = v_WorldPosition + normal * 0.02;
		vec3 reflected_color = trace_reflection(reflect_origin, reflect_direction);

		// Fresnel-Schlick blend: more reflective at grazing angles
		float base_reflectance = 0.15;
		float grazing = pow(1.0 - max(dot(normal, -incident), 0.0), 5.0);
		float fresnel = base_reflectance + (1.0 - base_reflectance) * grazing;

		result = mix(result, reflected_color, fresnel);
	}

	if (u_BackfaceDebug && is_back_facing) {
		result = vec3(1.0, 0.0, 1.0); // magenta
	}

	if (u_IsGround) {
		result = apply_ground_detail(result, v_WorldPosition);
	}
	if (u_FogEnabled) {
		float fog_distance = length(v_WorldPosition - u_ViewPosition);
		result = apply_fog(result, fog_distance);
	}
	if (u_VignetteEnabled) {
		result = apply_vignette(result);
	}
	if (u_TonemappingEnabled) {
		result = apply_tonemap_gamma(result);
	}

	FragColor = vec4(result, 1.0);
}
