#version 410 core
#include "Noise.glsl"
#include "Gbuffer.glsl"
#include "Brdf.glsl"
#include "Lighting.glsl"
#include "GbufferRead.glsl"
#include "SkyLut.glsl"
#include "Sky.glsl"
#include "Ambient.glsl"
#include "Shadow.glsl"
#include "Fullscreen.glsl"
#stage fragment
in vec2 v_uv;
out vec4 color;
uniform Light u_Sun;
uniform vec3 u_CameraForward;
uniform bool u_SunShadows;
uniform sampler2D u_Ssao;
uniform bool u_SsaoEnabled;

// Fullscreen pass: sky where nothing was drawn, otherwise sun + sky ambient + emission.
void main() {
	Gbuffer_Sample surface = gbuffer_read(v_uv);
	if (surface.depth >= 1.0) {
		color = vec4(sky_radiance(normalize(surface.position - u_CameraPosition)), 1.0);
		return;
	}
	vec3 view = normalize(u_CameraPosition - surface.position);
	vec3 sun = shade_light(u_Sun, surface.model, surface.position, surface.normal, view, surface.albedo, surface.roughness, surface.metallic);
	if (u_SunShadows) sun *= shadow_factor(surface.position, surface.normal, -u_Sun.direction, u_CameraPosition, u_CameraForward);
	// Occlusion only dims light that arrives from the sky; direct sun is handled by shadow maps.
	float occlusion = surface.ambient_occlusion * (u_SsaoEnabled ? texture(u_Ssao, v_uv).r : 1.0);
	vec3 ambient = ambient_light(surface.albedo, surface.roughness, surface.metallic, surface.normal, view, occlusion);
	color = vec4(sun + ambient + surface.emission, 1.0);
}
