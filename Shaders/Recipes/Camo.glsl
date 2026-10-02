#version 410 core
#include "Noise.glsl"
#include "Surface.glsl"
Surface recipe_surface(vec2 uv) {
	int period = int(u_CellsPerTile + 0.5);
	uint seed = uint(u_Seed);
	vec3 color = u_ColorA;
	color = fbm(uv, period, 3, seed) > 0.08 ? u_ColorB : color;
	color = fbm(uv, period, 3, seed + 101u) > 0.22 ? u_ColorC : color;
	float threads = float(period * 16);
	float weave = 0.5 + 0.5 * sin(6.2831853 * uv.x * threads) * sin(6.2831853 * uv.y * threads);
	Surface surface;
	surface.albedo = color * (0.9 + 0.1 * weave);
	surface.height = 0.5 + 0.3 * weave;
	surface.roughness = 0.85;
	surface.metallic = 0.0;
	surface.ambient_occlusion = 1.0;
	return surface;
}
#include "BakeMain.glsl"
