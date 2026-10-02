#version 410 core
#include "Noise.glsl"
#include "Brdf.glsl"
#include "Fullscreen.glsl"
#stage fragment
in vec2 v_uv;
out vec4 color;
uniform int u_Mode;
uniform int u_Model;
uniform float u_Roughness;
uniform float u_Metallic;
uniform vec3 u_Albedo;
uniform float u_ViewCosine;
uniform float u_GridSize;
const vec3 NORMAL = vec3(0.0, 0.0, 1.0);

vec3 hemisphere_direction(uint index, uint salt) {
	float z = mix(0.05, 1.0, hash_to_unit(hash_u32(index * 2u + salt)));
	float angle = 6.2831853 * hash_to_unit(hash_u32(index * 2u + salt + 977u));
	return vec3(sqrt(1.0 - z * z) * cos(angle), sqrt(1.0 - z * z) * sin(angle), z);
}

void main() {
	uint index = uint(gl_FragCoord.y) * 64u + uint(gl_FragCoord.x);
	vec3 light = hemisphere_direction(index, 0u);
	vec3 view = hemisphere_direction(index, 100000u);
	if (u_Mode == 0) {
		// rgb = f(l, v), a = red channel of f(v, l) for reciprocity.
		color = vec4(brdf_evaluate(u_Model, u_Albedo, u_Roughness, u_Metallic, NORMAL, view, light), brdf_evaluate(u_Model, u_Albedo, u_Roughness, u_Metallic, NORMAL, light, view).r);
	} else if (u_Mode == 1) {
		vec3 below = vec3(light.xy, -light.z);
		color = vec4(brdf_evaluate(u_Model, u_Albedo, u_Roughness, u_Metallic, NORMAL, view, below), 0.0);
	} else if (u_Mode == 2) {
		// Directional albedo: sum f * cos * sin over a (theta, phi) grid, theta uniform in [0, pi/2] (sin is the solid-angle Jacobian).
		float theta = 1.5707963 * (gl_FragCoord.y + 0.5) / u_GridSize;
		float angle = 6.2831853 * (gl_FragCoord.x + 0.5) / u_GridSize;
		vec3 sample_light = vec3(sin(theta) * cos(angle), sin(theta) * sin(angle), cos(theta));
		float z = cos(theta) * sin(theta);
		vec3 fixed_view = vec3(sqrt(1.0 - u_ViewCosine * u_ViewCosine), 0.0, u_ViewCosine);
		color = vec4(brdf_evaluate(u_Model, u_Albedo, u_Roughness, u_Metallic, NORMAL, fixed_view, sample_light) * z, 0.0);
	} else {
		float cosine = mix(-1.0, 1.0, (gl_FragCoord.x + 0.5) / 64.0);
		vec3 sample_light = vec3(sqrt(1.0 - cosine * cosine), 0.0, cosine);
		color = vec4(light_cosine(MODEL_SUBSURFACE, NORMAL, sample_light), light_cosine(MODEL_LAMBERT, NORMAL, sample_light), cosine, 0.0);
	}
}
