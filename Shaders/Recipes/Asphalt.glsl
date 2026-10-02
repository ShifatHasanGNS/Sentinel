#version 410 core
#include "Noise.glsl"
#include "Surface.glsl"
Surface recipe_surface(vec2 uv) {
	int period = int(u_CellsPerTile + 0.5);
	uint seed = uint(u_Seed);
	float patches = fbm(uv, period, 4, seed) * 0.5 + 0.5;
	float aggregate = 1.0 - smoothstep(0.08, 0.2, worley(uv, period * 12, seed + 5u).x);
	vec2 cells = worley(uv, period * 3, seed + 9u);
	float cracks = 1.0 - smoothstep(0.0, 0.05, cells.y - cells.x);
	Surface surface;
	surface.albedo = mix(mix(u_ColorA, u_ColorB, patches), u_ColorC, aggregate * 0.6) * (1.0 - 0.7 * cracks);
	surface.height = patches * 0.3 + aggregate * 0.5 - cracks * 0.4 + 0.3;
	surface.roughness = 0.92;
	surface.metallic = 0.0;
	surface.ambient_occlusion = 1.0 - 0.5 * cracks;
	return surface;
}
#include "BakeMain.glsl"
