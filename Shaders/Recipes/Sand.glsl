#version 410 core
#include "Noise.glsl"
#include "Surface.glsl"
Surface recipe_surface(vec2 uv) {
	int period = int(u_CellsPerTile + 0.5);
	uint seed = uint(u_Seed);
	float grain = gradient_noise(uv * float(period * 16), period * 16, seed) * 0.5 + 0.5;
	float ripple = 0.5 + 0.5 * sin((uv.y * float(period) + 0.35 * fbm(uv, period, 3, seed + 3u)) * 6.2831853);
	Surface surface;
	surface.albedo = mix(u_ColorB, u_ColorA, grain * 0.6 + ripple * 0.4);
	surface.height = ripple * 0.6 + grain * 0.2;
	surface.roughness = 0.95;
	surface.metallic = 0.0;
	surface.ambient_occlusion = 1.0;
	return surface;
}
#include "BakeMain.glsl"
