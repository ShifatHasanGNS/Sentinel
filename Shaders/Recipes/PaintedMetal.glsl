#version 410 core
#include "Noise.glsl"
#include "Surface.glsl"
Surface recipe_surface(vec2 uv) {
	int period = int(u_CellsPerTile + 0.5);
	uint seed = uint(u_Seed);
	vec2 inside = fract(uv * float(period));
	vec2 edge_distance = min(inside, 1.0 - inside);
	float edge = min(edge_distance.x, edge_distance.y);
	float panels = step(0.25, u_Detail); // detail 0 gives seamless paint (vehicle bodies); otherwise riveted panels.
	float seam = (1.0 - smoothstep(0.0, 0.025, edge)) * panels;
	float rivet = (1.0 - smoothstep(0.012, 0.022, length(abs(inside - 0.5) - 0.42))) * panels;
	float wear_field = fbm(uv, period * 2, 4, seed) * 0.5 + 0.5;
	// Seamless vehicle paint (panels = 0) wears only in small flecks; riveted panels also chip along their edges.
	float chips = 1.0 - smoothstep(0.0, 0.5, worley(uv, period * 16, seed + 5u).x);
	float wear = panels > 0.5 ? smoothstep(0.62, 0.8, wear_field + 0.35 * (1.0 - smoothstep(0.0, 0.06, edge))) : smoothstep(0.78, 0.9, wear_field) * chips * 0.5;
	float grain = fbm(uv, period * 16, 2, seed + 31u);
	Surface surface;
	surface.albedo = mix(u_ColorA * (0.82 + 0.36 * grain), u_ColorB, wear) * (1.0 - 0.5 * seam);
	surface.height = 0.6 - 0.35 * seam + 0.3 * rivet + 0.1 * grain; // The grain is the faint orange peel of paint.
	surface.roughness = mix(0.35, 0.6, wear);
	surface.metallic = wear;
	surface.ambient_occlusion = 1.0 - 0.5 * seam;
	return surface;
}
#include "BakeMain.glsl"
