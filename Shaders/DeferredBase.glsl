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
uniform mat4 u_ViewProjection;

// Contact shadows: shadow maps are too coarse to darken the last few centimetres where a boot, wheel or crate meets the ground. March
// a short ray (40 cm, 8 steps) toward the sun through the depth buffer; if any step lands behind the visible surface by less than a
// thickness, something small blocks the sun right there.
float contact_shadow(vec3 position, vec3 normal, vec3 to_sun) {
	const int STEPS = 8;
	const float LENGTH_METERS = 0.4;
	const float THICKNESS_METERS = 0.25;
	float jitter = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));
	vec3 origin = position + normal * 0.02;
	float distance_to_camera = length(position - u_CameraPosition);
	if (distance_to_camera > 60.0) return 1.0;
	for (int i = 1; i <= STEPS; i++) {
		vec3 sample_position = origin + to_sun * LENGTH_METERS * (float(i) - jitter) / float(STEPS);
		vec4 clip = u_ViewProjection * vec4(sample_position, 1.0);
		vec2 uv = clip.xy / clip.w * 0.5 + 0.5;
		if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return 1.0;
		float visible_depth = texture(u_GDepth, uv).r;
		if (visible_depth >= 1.0) continue;
		float visible_distance = length(world_position_from_depth(uv, visible_depth) - u_CameraPosition);
		float sample_distance = length(sample_position - u_CameraPosition);
		float behind = sample_distance - visible_distance;
		if (behind > 0.02 && behind < THICKNESS_METERS) return smoothstep(40.0, 60.0, distance_to_camera); // Fully shadowed up close, fading out by 60 m.
	}
	return 1.0;
}
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
	if (u_SunShadows) sun *= contact_shadow(surface.position, surface.normal, -u_Sun.direction);
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
