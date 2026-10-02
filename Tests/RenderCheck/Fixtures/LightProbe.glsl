#version 410 core
#include "Brdf.glsl"
#include "Lighting.glsl"
#include "Fullscreen.glsl"
#stage fragment
in vec2 v_uv;
out vec4 color;
uniform int u_Mode;
const float RANGE = 10.0;
const vec3 SURFACE_NORMAL = vec3(0.0, 0.0, 1.0);
const vec3 VIEW = vec3(0.0, 0.0, 1.0);

Light point_light(vec3 position) {
	return Light(LIGHT_POINT, vec3(1.0), 100.0, position, vec3(0.0), 1000.0, 0.0, 0.0, vec3(0.0), vec3(0.0));
}

// Rectangle facing -Z (toward a surface below it) with half extents 0.5 x 0.5.
Light area_light(vec3 position) {
	return Light(LIGHT_AREA, vec3(1.0), 100.0, position, vec3(0.0, 0.0, -1.0), 1000.0, 0.0, 0.0, vec3(0.0, 0.5, 0.0), vec3(0.5, 0.0, 0.0));
}

vec3 shade(Light light, vec3 position) {
	return shade_light(light, MODEL_LAMBERT, position, SURFACE_NORMAL, VIEW, vec3(1.0), 0.5, 0.0);
}

void main() {
	float t = gl_FragCoord.x / 64.0;
	if (u_Mode == 0) {
		color = vec4(attenuation_windowed(t * 2.0 * RANGE, RANGE), t * 2.0 * RANGE, 0.0, 0.0);
	} else if (u_Mode == 1) {
		float cos_angle = mix(0.2, 1.0, t);
		color = vec4(spot_cone_factor(cos_angle, 0.9, 0.7), cos_angle, 0.0, 0.0);
	} else if (u_Mode == 2) {
		float distance_to_light = mix(5.0, 40.0, t);
		vec3 center = vec3(0.0, 0.0, distance_to_light);
		color = vec4(shade(point_light(center), vec3(0.0)).r, shade(area_light(center), vec3(0.0)).r, distance_to_light, 0.0);
	} else if (u_Mode == 3) {
		color = vec4(shade(area_light(vec3(0.0, 0.0, 5.0)), vec3(0.0, 0.0, 10.0)).r, shade(area_light(vec3(0.0, 0.0, 0.3)), vec3(0.2, 0.1, 0.0)).r, 0.0, 0.0);
	} else {
		Light sun = Light(LIGHT_DIRECTIONAL, vec3(1.0), 3.0, vec3(0.0), normalize(vec3(0.0, 0.5, -1.0)), 0.0, 0.0, 0.0, vec3(0.0), vec3(0.0));
		color = vec4(shade(sun, vec3(t * 100.0, -t * 50.0, 0.0)).r, 0.0, 0.0, 0.0);
	}
}
