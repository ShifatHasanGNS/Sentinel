#version 410 core
#include "Noise.glsl"
#include "Surface.glsl"
// Rough bark: deep vertical fissures (ridged noise squeezed along the trunk by multiplying uv.x by a whole number, which keeps
// the tile seamless), broken by cross-cracks, with lichen-grey on the ridges. Colours: A fissure, B ridge, C lichen.
Surface recipe_surface(vec2 uv) {
	int period = int(u_CellsPerTile + 0.5);
	uint seed = uint(u_Seed);
	vec2 stretched = vec2(uv.x * 4.0, uv.y);
	float ridge = ridged_fbm(stretched, period, 5, seed);
	float plates = smoothstep(0.35, 0.75, ridge);
	float cross_cracks = smoothstep(0.55, 0.8, fbm(vec2(uv.x, uv.y * 3.0), period * 2, 3, seed + 17u) * 0.5 + 0.5);
	float lichen = smoothstep(0.62, 0.85, warped_fbm(uv, period, 4, 0.5, seed + 23u) * 0.5 + 0.5) * plates;
	float fine = fbm(stretched, period * 6, 3, seed + 29u) * 0.5 + 0.5;
	float relief = plates * (1.0 - 0.5 * cross_cracks);
	Surface surface;
	surface.albedo = mix(mix(u_ColorA, u_ColorB, relief * (0.7 + 0.3 * fine)), u_ColorC, lichen * 0.5);
	surface.height = relief * 0.8 + fine * 0.2;
	surface.roughness = 0.9 - 0.1 * lichen;
	surface.metallic = 0.0;
	surface.ambient_occlusion = 0.35 + 0.65 * relief;
	return surface;
}
#include "BakeMain.glsl"
