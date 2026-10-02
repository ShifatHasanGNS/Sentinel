#version 410 core
#include "Fullscreen.glsl"
#stage fragment
in vec2 v_uv;
out vec4 color;
uniform sampler2D u_Source;
uniform vec2 u_TexelSize; // Of the source texture.
uniform float u_Threshold;

float luma(vec3 rgb) {
	return dot(rgb, vec3(0.2126, 0.7152, 0.0722));
}

#ifdef DOWNSAMPLE
// 13-tap filter: five overlapping 2x2 box groups with weights 0.5 (centre group) and 0.125 (four corner groups). It removes the
// flicker a plain 2x2 box leaves on small bright pixels. The first level also applies a soft-knee threshold so only radiance
// above u_Threshold blooms.
vec3 tap(vec2 offset) {
	return texture(u_Source, v_uv + offset * u_TexelSize).rgb;
}

void main() {
	vec3 result = tap(vec2(0, 0)) * 0.125;
	result += (tap(vec2(-2, 2)) + tap(vec2(2, 2)) + tap(vec2(-2, -2)) + tap(vec2(2, -2))) * 0.03125;
	result += (tap(vec2(0, 2)) + tap(vec2(-2, 0)) + tap(vec2(2, 0)) + tap(vec2(0, -2))) * 0.0625;
	result += (tap(vec2(-1, 1)) + tap(vec2(1, 1)) + tap(vec2(-1, -1)) + tap(vec2(1, -1))) * 0.125;
	if (u_Threshold > 0.0) {
		float knee = u_Threshold * 0.5;
		float soft = clamp(luma(result) - u_Threshold + knee, 0.0, 2.0 * knee);
		soft = soft * soft / (4.0 * knee + 1e-4);
		result *= max(soft, luma(result) - u_Threshold) / max(luma(result), 1e-4);
	}
	color = vec4(result, 1.0);
}
#else
// 3x3 tent filter (weights 1 2 1 / 2 4 2 / 1 2 1 over 16), added onto the next larger level by blending.
void main() {
	vec3 sum = vec3(0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			float weight = float((2 - abs(x)) * (2 - abs(y)));
			sum += texture(u_Source, v_uv + vec2(x, y) * u_TexelSize).rgb * weight;
		}
	}
	color = vec4(sum / 16.0, 1.0);
}
#endif
