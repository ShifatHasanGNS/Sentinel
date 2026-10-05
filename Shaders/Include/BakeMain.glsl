// Bake pass shared by all recipes: include after defining `Surface recipe_surface(vec2 uv)`.
// Writes albedo (sRGB target, so the shader outputs linear), normal + height, and roughness/metallic/occlusion.

#include "Fullscreen.glsl"

#stage fragment
in vec2 v_uv;
layout(location = 0) out vec4 o_Albedo;
layout(location = 1) out vec4 o_Normal;
layout(location = 2) out vec4 o_Orm;
uniform float u_BumpStrength;
uniform float u_TextureSize;

#ifdef BAKE_PERIODICITY_PROBE
// Test mode: output how far the surface at uv + whole tiles differs from the surface at uv. A tiling recipe gives zero.
void main() {
	Surface here = recipe_surface(v_uv);
	Surface shifted = recipe_surface(v_uv + vec2(1.0, -2.0));
	o_Albedo = vec4(abs(here.albedo - shifted.albedo), 0.0);
	o_Normal = vec4(abs(here.height - shifted.height), abs(here.roughness - shifted.roughness), abs(here.metallic - shifted.metallic), abs(here.ambient_occlusion - shifted.ambient_occlusion));
	o_Orm = vec4(0.0);
}
#else
// Scharr 3x3 gradient of the height field: weights (3, 10, 3) are the most rotation-invariant small kernel, so slopes at 45
// degrees are not weaker than axis-aligned ones as with central differences. Dividing by 32 normalises the kernel, by the
// texel step gives dh/du, and by cells per tile gives slope per cell, so bump strength is independent of tile scale.
// Cavity occlusion: where the height is below its neighbourhood mean (negative Laplacian) light is trapped, so darken it.
void main() {
	float texel = 1.0 / u_TextureSize;
	Surface surface = recipe_surface(v_uv);
	float samples[9];
	for (int index = 0; index < 9; index++) {
		vec2 offset = vec2(float(index % 3 - 1), float(index / 3 - 1)) * texel;
		samples[index] = index == 4 ? surface.height : recipe_surface(v_uv + offset).height;
	}
	float gradient_x = (3.0 * (samples[2] + samples[8] - samples[0] - samples[6]) + 10.0 * (samples[5] - samples[3])) / 32.0;
	float gradient_y = (3.0 * (samples[6] + samples[8] - samples[0] - samples[2]) + 10.0 * (samples[7] - samples[1])) / 32.0;
	vec2 slope_per_cell = vec2(gradient_x, gradient_y) / texel / u_CellsPerTile;
	float neighbour_mean = (samples[1] + samples[3] + samples[5] + samples[7]) * 0.25;
	float cavity = clamp((neighbour_mean - surface.height) * u_TextureSize * 0.02, 0.0, 0.5);
	vec3 normal = normalize(vec3(-slope_per_cell * u_BumpStrength, 1.0));
	o_Albedo = vec4(surface.albedo * (1.0 - 0.5 * cavity), 1.0);
	o_Normal = vec4(normal * 0.5 + 0.5, surface.height);
	o_Orm = vec4(surface.roughness, surface.metallic, surface.ambient_occlusion * (1.0 - cavity), 1.0);
}
#endif
