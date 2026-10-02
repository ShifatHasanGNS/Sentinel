#version 410 core
#include "Noise.glsl"
#include "Surface.glsl"
Surface recipe_surface(vec2 uv) {
	int period = int(u_CellsPerTile + 0.5);
	uint seed = uint(u_Seed);
	float groove_phase = fract(uv.y * float(period * 4));
	float groove = smoothstep(0.3, 0.5, abs(groove_phase - 0.5) * 2.0);
	float grain = fbm(uv, period * 16, 2, seed) * 0.5 + 0.5;
	Surface surface;
	surface.albedo = mix(u_ColorA, u_ColorB, groove) * (0.8 + 0.4 * grain);
	surface.height = 0.7 - 0.5 * groove + 0.1 * grain;
	surface.roughness = 0.85;
	surface.metallic = 0.0;
	surface.ambient_occlusion = 1.0 - 0.6 * groove;
	return surface;
}
#include "BakeMain.glsl"
