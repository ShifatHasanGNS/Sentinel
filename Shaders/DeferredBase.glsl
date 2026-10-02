#version 410 core
#include "Gbuffer.glsl"
#include "Brdf.glsl"
#include "Lighting.glsl"
#include "GbufferRead.glsl"
#include "Sky.glsl"
#include "Ambient.glsl"
#include "Fullscreen.glsl"
#stage fragment
in vec2 v_uv;
out vec4 color;
uniform Light u_Sun;

// Fullscreen pass: sky where nothing was drawn, otherwise sun + sky ambient + emission.
void main() {
	Gbuffer_Sample surface = gbuffer_read(v_uv);
	if (surface.depth >= 1.0) {
		color = vec4(sky_radiance(normalize(surface.position - u_CameraPosition)), 1.0);
		return;
	}
	vec3 view = normalize(u_CameraPosition - surface.position);
	vec3 sun = shade_light(u_Sun, surface.model, surface.position, surface.normal, view, surface.albedo, surface.roughness, surface.metallic);
	vec3 ambient = ambient_light(surface.albedo, surface.roughness, surface.metallic, surface.normal, view, surface.ambient_occlusion);
	color = vec4(sun + ambient + surface.emission, 1.0);
}
