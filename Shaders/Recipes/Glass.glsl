#version 410 core
#include "Noise.glsl"
#include "Surface.glsl"
Surface recipe_surface(vec2 uv) {
	int period = int(u_CellsPerTile + 0.5);
	uint seed = uint(u_Seed);
	float grime = fbm(uv, period * 2, 4, seed) * 0.5 + 0.5;
	float streaks = fbm(uv * vec2(1.0, 1.0), period * 4, 2, seed + 7u) * 0.5 + 0.5;
	Surface surface;
	// Glass shows almost nothing of itself: what you see is its reflection. Grime is a faint haze, not a pattern.
	surface.albedo = mix(u_ColorA, u_ColorB, 0.25 * smoothstep(0.5, 0.9, grime * 0.6 + streaks * 0.5));
	surface.height = 0.5 + 0.02 * grime; // Flat: float glass has no bumps to speak of.
	surface.roughness = mix(0.05, 0.14, smoothstep(0.5, 0.9, grime));
	surface.metallic = 0.0;
	surface.ambient_occlusion = 1.0;
	return surface;
}
#include "BakeMain.glsl"
