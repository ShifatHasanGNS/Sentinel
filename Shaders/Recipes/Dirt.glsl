#version 410 core
#include "Noise.glsl"
#include "Surface.glsl"
Surface recipe_surface(vec2 uv) {
	int period = int(u_CellsPerTile + 0.5);
	uint seed = uint(u_Seed);
	float soil = mix(warped_fbm(uv, period, 5, 0.5, seed) * 0.5 + 0.5, billow_fbm(uv, period * 2, 4, seed + 5u), 0.35);
	float pebble = (1.0 - smoothstep(0.02, 0.32, worley(uv, period * 9, seed + 17u).x)) * 0.45; // Soft-edged stones: a hard edge reads as rings in the normal map.
	Surface surface;
	surface.albedo = mix(mix(u_ColorA, u_ColorB, soil), u_ColorC * (0.8 + 0.4 * soil), pebble);
	surface.height = soil * 0.4 + pebble * 0.6;
	surface.roughness = clamp(0.88 + 0.1 * soil - 0.1 * pebble, 0.0, 1.0);
	surface.metallic = 0.0;
	surface.ambient_occlusion = 1.0 - 0.3 * (1.0 - pebble) * (1.0 - soil);
	return surface;
}
#include "BakeMain.glsl"
