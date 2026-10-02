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
#include "Interior.glsl"
#include "Fullscreen.glsl"
#stage fragment
in vec2 v_uv;
out vec4 color;
uniform Light u_Sun;
uniform vec3 u_CameraForward;
uniform bool u_SunShadows;
const float FOG_DENSITY_PER_METER = 0.00035;
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
	// Indirect light in a room (a one-bounce radiosity stand-in): daylight enters by the windows and door and bounces between the
	// walls until it comes from everywhere, so the ambient is a fraction of the sky's and its direction is blended toward up
	// (floor and walls light the ceiling), where outdoors a ceiling would face the dark ground.
	float room_scale = interior_ambient_scale(surface.position);
	float in_room = clamp((1.0 - room_scale) / (1.0 - INTERIOR_AMBIENT_FRACTION), 0.0, 1.0);
	vec3 bounce_normal = normalize(mix(surface.normal, vec3(0.0, 1.0, 0.0), 0.6 * in_room));
	occlusion *= room_scale;
	vec3 ambient = ambient_light(surface.albedo, surface.roughness, surface.metallic, bounce_normal, view, occlusion);
	vec3 lit = sun + ambient + surface.emission;
	// Aerial perspective: with distance d the surface's light is extinguished by exp(-k d) and the air in front adds its own
	// in-scattered sky light, so far hills fade to the sky behind them (Beer-Lambert, one constant density).
	float distance_meters = length(surface.position - u_CameraPosition);
	float transmittance = exp(-FOG_DENSITY_PER_METER * distance_meters);
	vec3 haze = sky_radiance(normalize(vec3(view.x, 0.0, view.z) * -1.0 + vec3(0.0, 0.02, 0.0)));
	color = vec4(mix(haze, lit, transmittance), 1.0);
}
