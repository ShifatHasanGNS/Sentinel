#version 410 core
#include "Noise.glsl"
#include "Surface.glsl"
// Foliage: each worley cell is one leaf, a dome with its own tone from the cell's roll, a lighter translucent rim, a dark
// gap between leaves, and the occasional yellowing leaf. Colours: A deep green, B fresh green, C yellow.
Surface recipe_surface(vec2 uv) {
	int period = int(u_CellsPerTile + 0.5);
	uint seed = uint(u_Seed);
	vec4 leaf = worley_feature(uv, period * 14, seed);
	float dome = 1.0 - smoothstep(0.1, 0.62, leaf.x);
	float rim = smoothstep(0.3, 0.55, leaf.x) * dome;
	float large_tone = warped_fbm(uv, period, 3, 0.4, seed + 5u) * 0.5 + 0.5;
	float tone = clamp(leaf.y * 0.6 + large_tone * 0.4, 0.0, 1.0);
	float yellow = step(0.93, leaf.y) * 0.7;
	vec3 color = mix(mix(u_ColorA, u_ColorB, tone), u_ColorC, yellow);
	Surface surface;
	surface.albedo = color * (0.5 + 0.5 * dome) * (1.0 + 0.35 * rim);
	surface.height = dome;
	surface.roughness = 0.5 + 0.2 * leaf.y;
	surface.metallic = 0.0;
	surface.ambient_occlusion = 0.3 + 0.7 * dome;
	return surface;
}
#include "BakeMain.glsl"
