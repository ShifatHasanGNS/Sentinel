#version 410 core
#include "Gbuffer.glsl"
#include "Fullscreen.glsl"
#stage fragment
in vec2 v_uv;
out vec4 color;
uniform int u_Mode;
uniform sampler2D u_Encoded;

vec3 probe_normal() {
	int index = int(gl_FragCoord.y) * 64 + int(gl_FragCoord.x);
	if (index < 6) {
		vec3 axes[6] = vec3[6](vec3(1, 0, 0), vec3(-1, 0, 0), vec3(0, 1, 0), vec3(0, -1, 0), vec3(0, 0, 1), vec3(0, 0, -1));
		return axes[index];
	}
	float z = 1.0 - 2.0 * (float(index) + 0.5) / 4096.0;
	float radius = sqrt(1.0 - z * z);
	float angle = float(index) * 2.399963;
	return vec3(radius * cos(angle), radius * sin(angle), z);
}

void main() {
	vec3 normal = probe_normal();
	if (u_Mode == 0) {
		color = vec4(oct_encode(normal), 0.0, 0.0);
	} else {
		vec3 decoded = oct_decode(texelFetch(u_Encoded, ivec2(gl_FragCoord.xy), 0).xy);
		color = vec4(dot(normal, decoded), length(decoded), 0.0, 0.0);
	}
}
