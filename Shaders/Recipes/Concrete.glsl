#version 410 core
#include "Noise.glsl"
#include "Surface.glsl"
Surface recipe_surface(vec2 uv) {
	int period = int(u_CellsPerTile + 0.5);
	uint seed = uint(u_Seed);
	float mottling = fbm(uv, period, 5, seed) * 0.5 + 0.5;
	float pores = 1.0 - smoothstep(0.05, 0.16, worley(uv, period * 6, seed + 7u).x);
	Surface surface;
	surface.albedo = mix(u_ColorA, u_ColorB, mottling) * (1.0 - 0.5 * pores);
	surface.height = mottling * 0.6 - pores * 0.4 + 0.4;
	surface.roughness = 0.9;
	surface.metallic = 0.0;
	surface.ambient_occlusion = 1.0 - 0.6 * pores;
	return surface;
}
#include "BakeMain.glsl"
