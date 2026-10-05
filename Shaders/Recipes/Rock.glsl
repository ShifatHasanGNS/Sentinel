#version 410 core
#include "Noise.glsl"
#include "Surface.glsl"
Surface recipe_surface(vec2 uv) {
	int period = int(u_CellsPerTile + 0.5);
	uint seed = uint(u_Seed);
	vec2 cells = worley(uv, period * 2, seed);
	float plate = smoothstep(0.0, 0.12, cells.y - cells.x);
	float strata = mix(warped_fbm(uv, period, 5, 0.6, seed + 23u) * 0.5 + 0.5, ridged_fbm(uv, period * 2, 4, seed + 41u), 0.4);
	Surface surface;
	surface.albedo = mix(u_ColorB, u_ColorA, plate) * (0.75 + 0.5 * strata);
	surface.height = plate * 0.7 + strata * 0.3;
	surface.roughness = clamp(0.72 + 0.2 * strata + 0.08 * (1.0 - plate), 0.0, 1.0);
	surface.metallic = 0.0;
	surface.ambient_occlusion = 0.5 + 0.5 * plate;
	return surface;
}
#include "BakeMain.glsl"
