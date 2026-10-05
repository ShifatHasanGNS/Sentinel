#version 410 core
#include "Noise.glsl"
#include "Surface.glsl"
Surface recipe_surface(vec2 uv) {
	int period = int(u_CellsPerTile + 0.5);
	uint seed = uint(u_Seed);
	vec3 color = u_ColorA;
	color = warped_fbm(uv, period, 3, 0.5, seed) > 0.08 ? u_ColorB : color;
	color = warped_fbm(uv, period, 3, 0.5, seed + 101u) > 0.22 ? u_ColorC : color;
	float threads = float(period * 16);
	float weave = 0.5 + 0.5 * sin(6.2831853 * uv.x * threads) * sin(6.2831853 * uv.y * threads);
	float ripstop = 1.0 - 0.25 * (step(0.96, fract(uv.x * float(period * 4))) + step(0.96, fract(uv.y * float(period * 4)))); // Thicker thread every few, a grid of small squares.
	Surface surface;
	surface.albedo = color * (0.9 + 0.1 * weave) * ripstop;
	surface.height = 0.5 + 0.3 * weave;
	surface.roughness = 0.85;
	surface.metallic = 0.0;
	surface.ambient_occlusion = 1.0;
	return surface;
}
#include "BakeMain.glsl"
