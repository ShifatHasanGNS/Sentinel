#version 410 core
#include "Shadow.glsl"
#include "Fullscreen.glsl"
#stage fragment
in vec2 v_uv;
out vec4 color;
uniform int u_Mode;
uniform vec3 u_Points[8];
uniform vec3 u_ToLight;
uniform vec3 u_ProbeCameraPosition;
uniform vec3 u_ProbeCameraForward;

void main() {
	vec3 point;
	if (u_Mode == 0) {
		point = u_Points[int(gl_FragCoord.x)];
	} else {
		point = vec3(mix(-9.0, -5.0, gl_FragCoord.x / 64.0), 0.0, mix(5.0, 9.0, gl_FragCoord.y / 64.0));
	}
	color = vec4(shadow_factor(point, vec3(0.0, 1.0, 0.0), u_ToLight, u_ProbeCameraPosition, u_ProbeCameraForward), 0.0, 0.0, 1.0);
}
