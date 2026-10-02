#version 410 core
#include "Noise.glsl"
#include "Surface.glsl"
Surface recipe_surface(vec2 uv) {
	int period = int(u_CellsPerTile + 0.5);
	uint seed = uint(u_Seed);
	float clump = fbm(uv, period, 4, seed) * 0.5 + 0.5;
	float blades = gradient_noise(uv * float(period * 24), period * 24, seed + 5u) * 0.5 + 0.5;
	float dry = smoothstep(0.55, 0.8, fbm(uv, period, 3, seed + 9u) * 0.5 + 0.5);
	vec3 green = mix(u_ColorA, u_ColorB, clump * 0.6 + blades * 0.4);
	Surface surface;
	surface.albedo = mix(green, u_ColorC, dry * 0.6);
	surface.height = blades;
	surface.roughness = 0.85;
	surface.metallic = 0.0;
	surface.ambient_occlusion = 0.6 + 0.4 * blades;
	return surface;
}
#include "BakeMain.glsl"
