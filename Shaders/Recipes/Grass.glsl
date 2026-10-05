#version 410 core
#include "Noise.glsl"
#include "Surface.glsl"
// Turf seen from above: blade tips as small rounded domes (a worley field), fine strands between them, warped clumps of two
// greens, warm dry patches, and the odd bright speck of a flower. Colours: A shade, B sunlit, C dry.
Surface recipe_surface(vec2 uv) {
	int period = int(u_CellsPerTile + 0.5);
	uint seed = uint(u_Seed);
	float clump = warped_fbm(uv, period, 4, 0.5, seed) * 0.5 + 0.5;
	float tips = 1.0 - smoothstep(0.0, 0.55, worley(uv, period * 36, seed + 5u).x);
	float strands = fbm(uv, period * 48, 2, seed + 7u) * 0.5 + 0.5;
	float dry = smoothstep(0.55, 0.78, warped_fbm(uv, period, 3, 0.4, seed + 9u) * 0.5 + 0.5);
	float speck_roll = hash_to_unit(hash_cell(ivec2(floor(uv * float(period * 60))), period * 60, seed + 33u));
	float speck = step(0.994, speck_roll);
	vec3 green = mix(u_ColorA, u_ColorB, clump * 0.55 + strands * 0.2 + tips * 0.25);
	vec3 color = mix(green, u_ColorC, dry * 0.6);
	Surface surface;
	surface.albedo = mix(color * (0.6 + 0.4 * tips), vec3(0.75, 0.7, 0.35), speck * 0.8);
	surface.height = tips * 0.7 + strands * 0.3;
	surface.roughness = 0.7 + 0.2 * strands;
	surface.metallic = 0.0;
	surface.ambient_occlusion = 0.5 + 0.5 * tips;
	return surface;
}
#include "BakeMain.glsl"
