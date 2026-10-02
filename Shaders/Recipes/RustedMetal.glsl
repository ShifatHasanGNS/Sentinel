#version 410 core
#include "Noise.glsl"
#include "Surface.glsl"
Surface recipe_surface(vec2 uv) {
	int period = int(u_CellsPerTile + 0.5);
	uint seed = uint(u_Seed);
	float rust = smoothstep(0.0, 0.35, fbm(uv, period, 5, seed) + (u_Detail - 0.5));
	float rust_tone = fbm(uv, period * 2, 3, seed + 13u) * 0.5 + 0.5;
	float fine = fbm(uv, period * 8, 2, seed + 29u);
	Surface surface;
	surface.albedo = mix(u_ColorA * (0.9 + 0.1 * fine), mix(u_ColorB, u_ColorC, rust_tone), rust);
	surface.height = 0.5 + 0.3 * rust * fine;
	surface.roughness = mix(0.35, 0.9, rust);
	surface.metallic = 1.0 - rust;
	surface.ambient_occlusion = 1.0 - 0.3 * rust;
	return surface;
}
#include "BakeMain.glsl"
