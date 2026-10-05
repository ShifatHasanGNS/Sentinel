#version 410 core
#include "Noise.glsl"
#include "Surface.glsl"
Surface recipe_surface(vec2 uv) {
	int period = int(u_CellsPerTile + 0.5);
	uint seed = uint(u_Seed);
	float streaks = fbm(vec2(uv.x * 5.0, uv.y), period, 4, seed + 41u);
	float rust = smoothstep(0.0, 0.35, warped_fbm(uv, period, 5, 0.45, seed) + 0.3 * streaks + (u_Detail - 0.5));
	float pits = (1.0 - smoothstep(0.05, 0.2, worley(uv, period * 14, seed + 5u).x)) * rust;
	float rust_tone = fbm(uv, period * 2, 3, seed + 13u) * 0.5 + 0.5;
	float fine = fbm(uv, period * 8, 2, seed + 29u);
	Surface surface;
	surface.albedo = mix(u_ColorA * (0.9 + 0.1 * fine), mix(u_ColorB, u_ColorC, rust_tone), rust) * (1.0 - 0.4 * pits);
	surface.height = 0.5 + 0.3 * rust * fine - 0.25 * pits;
	surface.roughness = clamp(mix(0.35, 0.85, rust) + 0.1 * fine, 0.0, 1.0);
	surface.metallic = 1.0 - rust;
	surface.ambient_occlusion = 1.0 - 0.3 * rust;
	return surface;
}
#include "BakeMain.glsl"
