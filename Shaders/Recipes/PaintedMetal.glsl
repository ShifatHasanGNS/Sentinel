#version 410 core
#include "Noise.glsl"
#include "Surface.glsl"
Surface recipe_surface(vec2 uv) {
	int period = int(u_CellsPerTile + 0.5);
	uint seed = uint(u_Seed);
	vec2 inside = fract(uv * float(period));
	vec2 edge_distance = min(inside, 1.0 - inside);
	float edge = min(edge_distance.x, edge_distance.y);
	float seam = 1.0 - smoothstep(0.0, 0.025, edge);
	float rivet = 1.0 - smoothstep(0.012, 0.022, length(abs(inside - 0.5) - 0.42));
	float wear_field = fbm(uv, period * 2, 4, seed) * 0.5 + 0.5;
	float wear = smoothstep(0.62, 0.8, wear_field + 0.35 * (1.0 - smoothstep(0.0, 0.06, edge)));
	float grain = fbm(uv, period * 8, 2, seed + 31u);
	Surface surface;
	surface.albedo = mix(u_ColorA * (0.9 + 0.2 * grain), u_ColorB, wear) * (1.0 - 0.5 * seam);
	surface.height = 0.6 - 0.35 * seam + 0.3 * rivet;
	surface.roughness = mix(0.35, 0.6, wear);
	surface.metallic = wear;
	surface.ambient_occlusion = 1.0 - 0.5 * seam;
	return surface;
}
#include "BakeMain.glsl"
