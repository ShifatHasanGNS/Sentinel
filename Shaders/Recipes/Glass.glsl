#version 410 core
#include "Noise.glsl"
#include "Surface.glsl"
Surface recipe_surface(vec2 uv) {
	int period = int(u_CellsPerTile + 0.5);
	uint seed = uint(u_Seed);
	float grime = fbm(uv, period * 2, 4, seed) * 0.5 + 0.5;
	float streaks = fbm(uv * vec2(1.0, 1.0), period * 4, 2, seed + 7u) * 0.5 + 0.5;
	Surface surface;
	surface.albedo = mix(u_ColorA, u_ColorB, smoothstep(0.35, 0.8, grime * 0.6 + streaks * 0.5));
	surface.height = 0.5 + 0.15 * grime;
	surface.roughness = mix(0.06, 0.3, smoothstep(0.5, 0.9, grime));
	surface.metallic = 0.0;
	surface.ambient_occlusion = 1.0;
	return surface;
}
#include "BakeMain.glsl"
