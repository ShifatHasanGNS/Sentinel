#version 410 core
#include "Noise.glsl"
#include "Surface.glsl"
// Conifer foliage: one needle per worley cell, a thin streak along a random direction (the cell's roll) with a pale tip,
// over a dark shadowed mass. Colours: A shadow green, B needle green, C pale tip.
Surface recipe_surface(vec2 uv) {
	int period = int(u_CellsPerTile + 0.5);
	uint seed = uint(u_Seed);
	vec4 feature = worley_feature(uv, period * 22, seed);
	float angle = feature.y * 6.2831853;
	vec2 direction = vec2(cos(angle), sin(angle));
	float along = dot(feature.zw, direction);
	float across = dot(feature.zw, vec2(-direction.y, direction.x));
	float body = (1.0 - smoothstep(0.02, 0.1, abs(across))) * (1.0 - smoothstep(0.35, 0.6, abs(along)));
	float tip = body * smoothstep(0.2, 0.5, along);
	float mass = warped_fbm(uv, period, 4, 0.5, seed + 7u) * 0.5 + 0.5;
	vec3 color = mix(u_ColorA, u_ColorB, body * (0.6 + 0.4 * mass));
	Surface surface;
	surface.albedo = mix(color, u_ColorC, tip * 0.5) * (0.7 + 0.3 * mass);
	surface.height = body;
	surface.roughness = 0.55;
	surface.metallic = 0.0;
	surface.ambient_occlusion = 0.3 + 0.7 * body;
	return surface;
}
#include "BakeMain.glsl"
