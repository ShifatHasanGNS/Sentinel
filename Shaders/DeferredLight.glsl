#version 410 core
#include "Gbuffer.glsl"
#include "Brdf.glsl"
#include "Lighting.glsl"
#include "GbufferRead.glsl"
#include "Interior.glsl"
#stage vertex
layout(location = 0) in vec3 a_Position;
uniform mat4 u_Model;
uniform mat4 u_ViewProjection;
void main() {
	gl_Position = u_ViewProjection * u_Model * vec4(a_Position, 1.0);
}
#stage fragment
out vec4 color;
uniform Light u_Light;
uniform vec2 u_ScreenSize;
uniform sampler2DArrayShadow u_SpotShadows;
uniform float u_SpotShadowSize;
uniform int u_LightRoom; // Room the lamp is in, or -1 outside.
uniform int u_ShadowSlot; // Depth layer for this light, or -1 when it casts no shadow.
uniform mat4 u_SpotMatrix;
uniform float u_SpotTexelPerMeter;

// Same recipe as the sun's cascades: push the lookup along the normal by a texel or two (scaled by distance, because a
// perspective texel grows with depth), then 3x3 hardware-compared taps. The compare bias is small since the offset does the work.
float spot_shadow(vec3 position, vec3 normal) {
	vec3 to_light = normalize(u_Light.position - position);
	float tilt = 1.0 - clamp(dot(normal, to_light), 0.0, 1.0);
	float texel_meters = length(u_Light.position - position) * u_SpotTexelPerMeter;
	vec4 clip = u_SpotMatrix * vec4(position + normal * texel_meters * (1.5 + 2.5 * tilt), 1.0);
	vec3 coordinates = clip.xyz / clip.w * 0.5 + 0.5;
	if (clip.w <= 0.0 || coordinates.x < 0.0 || coordinates.x > 1.0 || coordinates.y < 0.0 || coordinates.y > 1.0 || coordinates.z > 1.0) return 1.0;
	float lit = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 tap = coordinates.xy + vec2(x, y) / u_SpotShadowSize;
			lit += texture(u_SpotShadows, vec4(tap, float(u_ShadowSlot), coordinates.z - 0.0002));
		}
	}
	return lit / 9.0;
}

// Drawn once per local light over a proxy sphere of radius `range`, additively blended onto the lit scene.
void main() {
	Gbuffer_Sample surface = gbuffer_read(gl_FragCoord.xy / u_ScreenSize);
	if (surface.depth >= 1.0) discard;
	// A lamp lights its own room (or the outdoors) and nothing across a wall.
	if (interior_index(surface.position) != u_LightRoom) discard;
	vec3 view = normalize(u_CameraPosition - surface.position);
	vec3 radiance = shade_light(u_Light, surface.model, surface.position, surface.normal, view, surface.albedo, surface.roughness, surface.metallic);
	if (u_ShadowSlot >= 0) radiance *= spot_shadow(surface.position, surface.normal);
	color = vec4(radiance, 1.0);
}
