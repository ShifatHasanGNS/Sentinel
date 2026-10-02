#version 410 core
#include "Noise.glsl"
#include "Surface.glsl"
Surface recipe_surface(vec2 uv) {
	int period = int(u_CellsPerTile + 0.5);
	uint seed = uint(u_Seed);
	float planks = float(period * 2);
	float plank_id = mod(floor(uv.x * planks), planks); // Wrapped, so the tint repeats with the tile.
	float tint = hash_to_unit(hash_u32(uint(plank_id) ^ seed));
	float rings = 0.5 + 0.5 * sin(6.2831853 * (uv.x * planks * 3.0 + 3.0 * fbm(uv, period, 3, seed + 3u)));
	float fibre = fbm(uv, period * 24, 3, seed + 9u) * 0.5 + 0.5;
	float grain = mix(rings, fibre, 0.55) * 0.6 + 0.2; // Low-contrast rings under fine fibres, not stripes.
	float edge = min(fract(uv.x * planks), 1.0 - fract(uv.x * planks));
	float seam = 1.0 - smoothstep(0.0, 0.03, edge);
	Surface surface;
	surface.albedo = mix(mix(u_ColorB, u_ColorA, grain), u_ColorC, tint * 0.5) * (1.0 - 0.7 * seam);
	surface.height = 0.55 + 0.25 * grain - 0.4 * seam;
	surface.roughness = 0.75;
	surface.metallic = 0.0;
	surface.ambient_occlusion = 1.0 - 0.5 * seam;
	return surface;
}
#include "BakeMain.glsl"
