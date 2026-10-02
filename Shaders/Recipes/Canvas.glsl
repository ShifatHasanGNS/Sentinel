#version 410 core
#include "Noise.glsl"
#include "Surface.glsl"
Surface recipe_surface(vec2 uv) {
	int period = int(u_CellsPerTile + 0.5);
	uint seed = uint(u_Seed);
	vec2 thread = uv * float(period * 8);
	float over = mod(floor(thread.x) + floor(thread.y), 2.0);
	float weft = 0.5 + 0.5 * cos(6.2831853 * thread.x);
	float warp = 0.5 + 0.5 * cos(6.2831853 * thread.y);
	float height = over < 1.0 ? weft : warp;
	Surface surface;
	surface.albedo = mix(u_ColorB, u_ColorA, height) * (0.9 + 0.2 * (fbm(uv, period, 3, seed) * 0.5 + 0.5));
	surface.height = height;
	surface.roughness = 0.9;
	surface.metallic = 0.0;
	surface.ambient_occlusion = 0.7 + 0.3 * height;
	return surface;
}
#include "BakeMain.glsl"
