#version 410 core
#include "Atmosphere.glsl"
#include "SkyLut.glsl"
#include "Fullscreen.glsl"
#stage fragment
in vec2 v_uv;
out vec4 color;
uniform int u_Mode;
uniform sampler2D u_SkyLut;
uniform vec3 u_ToSun;
uniform vec3 u_Direction;
const float SUN_INTENSITY = 20.0;

void main() {
	vec3 direction = normalize(u_Direction);
	if (u_Mode == 0) {
		color = vec4(atmosphere_radiance(direction, normalize(u_ToSun), SUN_INTENSITY), 1.0);
	} else {
		color = vec4(sky_lut_sample(u_SkyLut, direction), 1.0);
	}
}
