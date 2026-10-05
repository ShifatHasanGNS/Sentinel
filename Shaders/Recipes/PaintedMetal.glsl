#version 410 core
#include "Noise.glsl"
#include "Surface.glsl"
Surface recipe_surface(vec2 uv) {
	int period = int(u_CellsPerTile + 0.5);
	uint seed = uint(u_Seed);
	vec2 inside = fract(uv * float(period));
	vec2 edge_distance = min(inside, 1.0 - inside);
	float edge = min(edge_distance.x, edge_distance.y);
	float panels = step(0.25, u_Detail); // detail >= 0.25: riveted panels; detail 0.05 to 0.25: paint with fine panel lines (vehicle bodies); 0: seamless paint.
	float lined = step(0.05, u_Detail);
	float seam = (1.0 - smoothstep(0.0, mix(0.005, 0.025, panels), edge)) * lined;
	float rivet = (1.0 - smoothstep(0.012, 0.022, length(abs(inside - 0.5) - 0.42))) * panels;
	float wear_field = fbm(uv, period * 2, 4, seed) * 0.5 + 0.5;
	// Seamless vehicle paint (panels = 0) wears only in small flecks; riveted panels also chip along their edges.
	float chips = 1.0 - smoothstep(0.0, 0.5, worley(uv, period * 16, seed + 5u).x);
	float wear = panels > 0.5 ? smoothstep(0.62, 0.8, wear_field + 0.35 * (1.0 - smoothstep(0.0, 0.06, edge))) : smoothstep(0.78, 0.9, wear_field) * chips * 0.5;
	float grain = fbm(uv, period * 16, 2, seed + 31u);
	// Scratches: thin lines where a noise field crosses zero, kept to some areas; they expose bright metal.
	float scratch_lines = 1.0 - smoothstep(0.0, 0.035, abs(gradient_noise(uv * float(period * 40), period * 40, seed + 7u)));
	float scratches = scratch_lines * smoothstep(0.55, 0.78, fbm(uv, period * 2, 3, seed + 11u) * 0.5 + 0.5);
	float grime = smoothstep(0.5, 0.9, warped_fbm(uv, period, 4, 0.4, seed + 17u) * 0.5 + 0.5);
	Surface surface;
	// Paint fades unevenly in the sun: a slow warped field lightens and warms some regions.
	float fade = warped_fbm(uv, period, 3, 0.5, seed + 23u) * 0.5 + 0.5;
	vec3 paint = mix(u_ColorA * (0.82 + 0.36 * grain), u_ColorA * vec3(1.12, 1.1, 1.05), smoothstep(0.55, 0.85, fade) * (1.0 - panels));
	surface.albedo = mix(mix(paint, u_ColorB, wear), u_ColorB * 0.8, scratches * 0.7) * (1.0 - 0.5 * seam) * (1.0 - 0.3 * grime);
	surface.height = 0.6 - 0.35 * seam + 0.3 * rivet + 0.012 * grain; // The grain is the faint orange peel of paint: a whisper, not a hammered finish.
	surface.roughness = clamp(mix(0.35, 0.6, wear) + 0.2 * grime - 0.15 * scratches, 0.05, 1.0);
	surface.metallic = max(wear, scratches);
	surface.ambient_occlusion = 1.0 - 0.5 * seam;
	return surface;
}
#include "BakeMain.glsl"
