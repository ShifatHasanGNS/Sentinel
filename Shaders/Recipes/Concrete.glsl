#version 410 core
#include "Noise.glsl"
#include "Surface.glsl"
Surface recipe_surface(vec2 uv) {
	int period = int(u_CellsPerTile + 0.5);
	uint seed = uint(u_Seed);
	float mottling = warped_fbm(uv, period, 5, 0.35, seed) * 0.5 + 0.5;
	float cracks = smoothstep(0.93, 0.99, ridged_fbm(uv, period, 3, seed + 29u));
	float pores = (1.0 - smoothstep(0.03, 0.09, worley(uv, period * 10, seed + 7u).x)) * 0.5;
	float fine = fbm(uv, period * 16, 3, seed + 13u);
	Surface surface;
	surface.albedo = mix(u_ColorA, u_ColorB, mottling) * (1.0 - 0.35 * pores) * (0.94 + 0.06 * fine) * (1.0 - 0.25 * cracks);
	surface.height = mottling * 0.1 - pores * 0.4 - cracks * 0.5 + 0.5;
	surface.roughness = clamp(0.82 + 0.12 * mottling + 0.06 * fine, 0.0, 1.0);
	surface.metallic = 0.0;
	surface.ambient_occlusion = 1.0 - 0.6 * pores - 0.3 * cracks;
	return surface;
}
#include "BakeMain.glsl"
