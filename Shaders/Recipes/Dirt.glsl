#version 410 core
#include "Noise.glsl"
#include "Surface.glsl"
Surface recipe_surface(vec2 uv) {
	int period = int(u_CellsPerTile + 0.5);
	uint seed = uint(u_Seed);
	float soil = fbm(uv, period, 5, seed) * 0.5 + 0.5;
	float pebble = (1.0 - smoothstep(0.12, 0.2, worley(uv, period * 7, seed + 17u).x)) * 0.6;
	Surface surface;
	surface.albedo = mix(mix(u_ColorA, u_ColorB, soil), u_ColorC * (0.8 + 0.4 * soil), pebble);
	surface.height = soil * 0.4 + pebble * 0.6;
	surface.roughness = 0.95;
	surface.metallic = 0.0;
	surface.ambient_occlusion = 1.0 - 0.3 * (1.0 - pebble) * (1.0 - soil);
	return surface;
}
#include "BakeMain.glsl"
