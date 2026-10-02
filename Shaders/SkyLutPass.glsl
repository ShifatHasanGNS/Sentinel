#version 410 core
#include "Atmosphere.glsl"
#include "SkyLut.glsl"
#include "Fullscreen.glsl"
#stage fragment
in vec2 v_uv;
out vec4 color;
uniform vec3 u_ToSun;
uniform float u_SunIntensity;

void main() {
	color = vec4(atmosphere_radiance(sky_lut_direction(v_uv), u_ToSun, u_SunIntensity), 1.0);
}
