#version 410 core
#include "Noise.glsl"
#stage vertex
out vec2 v_uv;
void main() {
	vec2 corner = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
	v_uv = corner;
	gl_Position = vec4(corner * 2.0 - 1.0, 0.0, 1.0);
}
#stage fragment
in vec2 v_uv;
out vec4 color;
uniform int u_Mode;
const int PERIOD = 8;
const uint SEED = 5u;
void main() {
	vec2 sample_position = v_uv * 7.31 + vec2(3.7, -2.2);
	if (u_Mode == 0) {
		float value = gradient_noise(sample_position, PERIOD, SEED);
		float shifted = gradient_noise(sample_position + vec2(2.0 * PERIOD, -PERIOD), PERIOD, SEED);
		color = vec4(value, shifted, gradient_noise(sample_position, PERIOD, SEED + 1u), 0.0);
	} else if (u_Mode == 1) {
		color = vec4(fbm(v_uv, PERIOD, 4, SEED), fbm(v_uv + vec2(1.0, -3.0), PERIOD, 4, SEED), 0.0, 0.0);
	} else if (u_Mode == 2) {
		color = vec4(worley(v_uv, PERIOD, SEED).x, worley(v_uv + vec2(2.0, -1.0), PERIOD, SEED).x, worley(v_uv, PERIOD, SEED).y, 0.0);
	} else {
		color = vec4(gradient_noise(floor(v_uv * 8.0), PERIOD, SEED), 0.0, 0.0, 0.0);
	}
}
