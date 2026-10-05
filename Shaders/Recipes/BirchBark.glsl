#version 410 core
#include "Noise.glsl"
#include "Surface.glsl"
// Birch: pale papery bark with dark horizontal lenticels (short dashes, ridged noise stretched across the trunk) and grey
// peeling bands. Colours: A white bark, B dark marks, C grey.
Surface recipe_surface(vec2 uv) {
	int period = int(u_CellsPerTile + 0.5);
	uint seed = uint(u_Seed);
	vec2 across = vec2(uv.x, uv.y * 6.0);
	float lines = ridged_fbm(across, period, 4, seed);
	float dashes_mask = smoothstep(0.1, 0.5, fbm(uv, period * 2, 3, seed + 5u) * 0.5 + 0.5);
	float marks = smoothstep(0.7, 0.9, lines) * dashes_mask;
	float bands = smoothstep(0.55, 0.8, warped_fbm(across, period, 3, 0.3, seed + 11u) * 0.5 + 0.5);
	float fine = fbm(uv, period * 10, 3, seed + 19u) * 0.5 + 0.5;
	Surface surface;
	surface.albedo = mix(mix(u_ColorA * (0.85 + 0.15 * fine), u_ColorC, bands * 0.5), u_ColorB, marks);
	surface.height = 0.55 - 0.3 * marks + 0.15 * fine;
	surface.roughness = 0.65 + 0.2 * marks;
	surface.metallic = 0.0;
	surface.ambient_occlusion = 1.0 - 0.5 * marks;
	return surface;
}
#include "BakeMain.glsl"
