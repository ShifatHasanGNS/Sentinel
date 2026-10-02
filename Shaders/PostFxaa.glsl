#version 410 core
#include "Fullscreen.glsl"
#stage fragment
in vec2 v_uv;
out vec4 color;
uniform sampler2D u_Ldr;
uniform vec2 u_ScreenSize;

float luma(vec3 rgb) {
	return dot(rgb, vec3(0.299, 0.587, 0.114));
}

// FXAA (Lottes): estimate the local edge direction from the luma of the four diagonal neighbours, then average samples
// taken along that direction. Where the neighbourhood is flat the direction is zero and the pixel is unchanged.
void main() {
	vec2 texel = 1.0 / u_ScreenSize;
	vec3 middle = texture(u_Ldr, v_uv).rgb;
	float luma_nw = luma(texture(u_Ldr, v_uv + vec2(-1.0, -1.0) * texel).rgb);
	float luma_ne = luma(texture(u_Ldr, v_uv + vec2(1.0, -1.0) * texel).rgb);
	float luma_sw = luma(texture(u_Ldr, v_uv + vec2(-1.0, 1.0) * texel).rgb);
	float luma_se = luma(texture(u_Ldr, v_uv + vec2(1.0, 1.0) * texel).rgb);
	float luma_m = luma(middle);
	float luma_min = min(luma_m, min(min(luma_nw, luma_ne), min(luma_sw, luma_se)));
	float luma_max = max(luma_m, max(max(luma_nw, luma_ne), max(luma_sw, luma_se)));
	vec2 direction = vec2(-((luma_nw + luma_ne) - (luma_sw + luma_se)), (luma_nw + luma_sw) - (luma_ne + luma_se));
	float reduce = max((luma_nw + luma_ne + luma_sw + luma_se) * 0.25 * (1.0 / 8.0), 1.0 / 128.0);
	direction = clamp(direction / (min(abs(direction.x), abs(direction.y)) + reduce), -8.0, 8.0) * texel;
	vec3 narrow = 0.5 * (texture(u_Ldr, v_uv + direction * (1.0 / 3.0 - 0.5)).rgb + texture(u_Ldr, v_uv + direction * (2.0 / 3.0 - 0.5)).rgb);
	vec3 wide = narrow * 0.5 + 0.25 * (texture(u_Ldr, v_uv + direction * -0.5).rgb + texture(u_Ldr, v_uv + direction * 0.5).rgb);
	float luma_wide = luma(wide);
	color = vec4((luma_wide < luma_min || luma_wide > luma_max) ? narrow : wide, 1.0);
}
