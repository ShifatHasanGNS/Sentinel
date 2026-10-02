#version 410 core
#include "Noise.glsl"
#include "Surface.glsl"
Surface recipe_surface(vec2 uv) {
	int period = int(u_CellsPerTile + 0.5);
	uint seed = uint(u_Seed);
	float tone = fbm(uv, period, 4, seed) * 0.5 + 0.5;
	float pores = 1.0 - smoothstep(0.1, 0.3, worley(uv, period * 14, seed + 3u).x);
	float flush = smoothstep(0.55, 0.9, fbm(uv, period * 2, 3, seed + 11u) * 0.5 + 0.5);
	Surface surface;
	surface.albedo = mix(mix(u_ColorA, u_ColorB, tone), u_ColorC, flush * 0.4) * (1.0 - 0.15 * pores);
	surface.height = 0.6 + 0.2 * tone - 0.25 * pores;
	surface.roughness = 0.55;
	surface.metallic = 0.0;
	surface.ambient_occlusion = 1.0 - 0.3 * pores;
	return surface;
}
#include "BakeMain.glsl"
