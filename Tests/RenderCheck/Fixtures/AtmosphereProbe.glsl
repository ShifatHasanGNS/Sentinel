#version 410 core
#include "Atmosphere.glsl"
#include "Fullscreen.glsl"
#stage fragment
in vec2 v_uv;
out vec4 color;
uniform int u_Mode;
uniform vec3 u_ToSun;
uniform vec3 u_Direction;
const float SUN_INTENSITY = 20.0;

void main() {
	vec3 direction = u_Direction;
	if (u_Mode == 1) {
		// Sweep: azimuth across x, elevation from -30 to 90 degrees across y.
		float azimuth = 6.2831853 * gl_FragCoord.x / 64.0;
		float elevation = radians(mix(-30.0, 90.0, gl_FragCoord.y / 32.0));
		direction = vec3(cos(elevation) * cos(azimuth), sin(elevation), cos(elevation) * sin(azimuth));
	}
	color = vec4(atmosphere_radiance(normalize(direction), normalize(u_ToSun), SUN_INTENSITY), 1.0);
}
