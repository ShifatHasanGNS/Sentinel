#version 410 core
#include "Tonemap.glsl"
#include "Fullscreen.glsl"
#stage fragment
in vec2 v_uv;
out vec4 color;
uniform sampler2D u_Hdr;
uniform sampler2D u_Bloom;
uniform float u_BloomStrength;
uniform float u_Exposure;
uniform float u_VignetteStrength;

vec3 linear_to_srgb(vec3 linear) {
	vec3 low = linear * 12.92;
	vec3 high = 1.055 * pow(linear, vec3(1.0 / 2.4)) - 0.055;
	return mix(low, high, step(vec3(0.0031308), linear));
}

// Exposure, ACES, optional vignette (smooth darkening toward the corners), then sRGB encoding for display.
void main() {
	vec3 radiance = (texture(u_Hdr, v_uv).rgb + u_BloomStrength * texture(u_Bloom, v_uv).rgb) * u_Exposure;
	vec2 centered = v_uv * 2.0 - 1.0;
	radiance *= 1.0 - u_VignetteStrength * smoothstep(0.4, 1.6, dot(centered, centered));
	color = vec4(linear_to_srgb(tonemap_aces(radiance)), 1.0);
}
