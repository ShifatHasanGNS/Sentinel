#version 410 core
#include "Tonemap.glsl"
#include "Fullscreen.glsl"
#stage fragment
in vec2 v_uv;
out vec4 color;
uniform sampler2D u_Hdr;
uniform sampler2D u_Bloom;
uniform float u_BloomStrength;
uniform sampler2D u_Depth;
uniform vec2 u_SunUv;
uniform vec3 u_ShaftColor; // Zero when the sun is behind the camera or below the horizon.
uniform float u_Exposure;
uniform float u_VignetteStrength;

vec3 linear_to_srgb(vec3 linear) {
	vec3 low = linear * 12.92;
	vec3 high = 1.055 * pow(linear, vec3(1.0 / 2.4)) - 0.055;
	return mix(low, high, step(vec3(0.0031308), linear));
}

// Exposure, ACES, optional vignette (smooth darkening toward the corners), then sRGB encoding for display.
const int SHAFT_SAMPLES = 24;

// Screen-space crepuscular rays. March from the pixel toward the sun's screen position; each step that lands on open sky
// (depth at the far plane) adds light, with exponential decay so near-sun samples dominate. Geometry between pixel and sun
// therefore casts visible shafts. Integration over the path approximates single scattering along the view ray.
vec3 light_shafts() {
	vec2 step_uv = (u_SunUv - v_uv) / float(SHAFT_SAMPLES) * 0.9;
	vec2 uv = v_uv + step_uv * fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));
	float sum = 0.0;
	float weight = 1.0;
	for (int i = 0; i < SHAFT_SAMPLES; i++) {
		uv += step_uv;
		sum += weight * step(1.0, texture(u_Depth, uv).r);
		weight *= 0.93;
	}
	float toward_sun = smoothstep(2.0, 0.0, length(u_SunUv - v_uv));
	return u_ShaftColor * sum / float(SHAFT_SAMPLES) * toward_sun;
}

void main() {
	vec3 radiance = (texture(u_Hdr, v_uv).rgb + u_BloomStrength * texture(u_Bloom, v_uv).rgb) * u_Exposure;
	if (u_ShaftColor != vec3(0.0)) radiance += light_shafts() * u_Exposure;
	vec2 centered = v_uv * 2.0 - 1.0;
	radiance *= 1.0 - u_VignetteStrength * smoothstep(0.4, 1.6, dot(centered, centered));
	color = vec4(linear_to_srgb(tonemap_aces(radiance)), 1.0);
}
