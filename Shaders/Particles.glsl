#version 410 core
#include "Noise.glsl"
#stage vertex
layout(location = 0) in vec3 a_Center;
layout(location = 1) in vec2 a_Corner;   // -1..1 across the billboard
layout(location = 2) in vec4 a_Color;    // rgb tint (fire: unused), a = overall opacity
layout(location = 3) in vec4 a_Params;   // x = life fraction 0..1, y = seed, z = size (meters), w = rotation (radians)
uniform mat4 u_ViewProjection;
uniform vec3 u_CameraRight;
uniform vec3 u_CameraUp;
out vec2 v_corner;
out vec4 v_color;
out vec4 v_params;
out vec3 v_world;
void main() {
	float c = cos(a_Params.w), s = sin(a_Params.w);
	vec2 turned = vec2(a_Corner.x * c - a_Corner.y * s, a_Corner.x * s + a_Corner.y * c);
	vec3 world = a_Center + (u_CameraRight * turned.x + u_CameraUp * turned.y) * a_Params.z;
	v_world = world;
	v_corner = a_Corner;
	v_color = a_Color;
	v_params = a_Params;
	gl_Position = u_ViewProjection * vec4(world, 1.0);
}
#stage fragment
in vec2 v_corner;
in vec4 v_color;
in vec4 v_params;
in vec3 v_world;
out vec4 color;
uniform sampler2D u_Depth;
uniform vec2 u_ScreenSize;
uniform mat4 u_InverseViewProjection;
uniform vec3 u_CameraPosition;
uniform vec3 u_SunDirection;   // Toward the sun.
uniform vec3 u_SunLight;       // Sun radiance reaching the ground.
uniform vec3 u_SkyLight;       // Ambient.
uniform vec3 u_CameraRight;
uniform vec3 u_CameraUp;
uniform vec3 u_CameraForward;
uniform float u_Time;
#ifdef FIRE
const bool IS_FIRE = true;
#else
const bool IS_FIRE = false;
#endif

// Distance from the camera to whatever the depth buffer holds at this pixel.
float scene_distance(vec2 uv) {
	float depth = texture(u_Depth, uv).r;
	if (depth >= 1.0) return 1e5;
	vec4 clip = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
	vec4 world = u_InverseViewProjection * clip;
	return length(world.xyz / world.w - u_CameraPosition);
}

// Noise for the puff shape: three octaves of gradient noise in a window that drifts with the particle's age and seed, so every puff is
// its own cloud and each one churns as it ages. Result about 0..1.
float puff_noise(vec2 corner, float seed, float age) {
	vec2 p = corner * 2.6 + vec2(seed * 7.13, seed * 3.71) + vec2(0.0, -age * 0.8);
	return fbm(p / 64.0, 64, 4, 11u) * 0.5 + 0.5;
}

void main() {
	float radius = length(v_corner);
	if (radius > 1.0) discard;
	float age = v_params.x;
	float noise = puff_noise(v_corner, v_params.y, age);
	float contrast = clamp((noise - 0.5) * 2.2 + 0.5, 0.0, 1.0); // The raw noise sits mid-grey: stretch it so the ragged edge reads.
	// Soft disc, then erode its edge with the noise: where the noise is low the puff thins out first, giving the ragged cauliflower
	// outline of real smoke. Erosion grows with age, so the puff dissolves rather than just fading.
	float edge = 1.0 - smoothstep(0.35, 1.0, radius);
	float erosion = mix(0.45, 0.85, age);
	float density = clamp((edge - erosion * (1.0 - contrast)) / max(1.0 - erosion, 0.2), 0.0, 1.0);
	density = density * density * (3.0 - 2.0 * density);
	if (density < 0.01) discard;
	// Soft particle: fade out where the billboard is within half a meter of a surface behind it, so it never cuts a hard line through
	// the ground or a wall; and cull it outright where a surface is in front.
	vec2 uv = gl_FragCoord.xy / u_ScreenSize;
	float scene = scene_distance(uv);
	float mine = length(v_world - u_CameraPosition);
	float softness = clamp((scene - mine) / 0.6, 0.0, 1.0);
	if (softness <= 0.0) discard;
#ifdef FIRE
	// Flame: temperature falls with age and toward the rim; black-body-like ramp white -> yellow -> orange -> deep red. HDR values
	// above 1 are what the bloom pass turns into a glow.
	float heat = clamp((1.0 - age) * (1.0 - 0.75 * radius) * (0.35 + 0.95 * contrast), 0.0, 1.2);
	vec3 flame = mix(vec3(0.7, 0.08, 0.01), vec3(1.0, 0.45, 0.06), smoothstep(0.1, 0.5, heat));
	flame = mix(flame, vec3(1.0, 0.85, 0.4), smoothstep(0.5, 0.9, heat));
	flame = mix(flame, vec3(1.0, 0.93, 0.7), smoothstep(0.95, 1.25, heat));
	float intensity = v_color.a * heat * heat * 2.6;
	color = vec4(flame * intensity * density * softness, 1.0);
#else
	// Smoke: it is lit like a fluffy sphere. Fake a normal from the position on the disc (z toward the camera), then a wrapped
	// Lambert term from the sun; the sky ambient fills the shadow side and the puff's own thickness darkens its core (light cannot
	// cross dense smoke), which gives the bulging, volumetric look a flat grey disc lacks.
	vec3 normal = normalize(u_CameraRight * v_corner.x + u_CameraUp * v_corner.y - u_CameraForward * sqrt(max(1.0 - radius * radius, 0.0)));
	float wrapped = clamp(dot(normal, u_SunDirection) * 0.5 + 0.5, 0.0, 1.0);
	float thickness = density * (1.0 - 0.35 * radius);
	vec3 lit = v_color.rgb * (u_SkyLight + u_SunLight * wrapped * (1.0 - 0.5 * thickness));
	color = vec4(lit, v_color.a * density * softness);
#endif
}
