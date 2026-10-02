// Bake pass shared by all recipes: include after defining `Surface recipe_surface(vec2 uv)`.
// Writes albedo (sRGB target, so the shader outputs linear), normal + height, and roughness/metallic/occlusion.

#stage vertex
out vec2 v_uv;
void main() {
	vec2 corner = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
	v_uv = corner;
	gl_Position = vec4(corner * 2.0 - 1.0, 0.0, 1.0);
}

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
// Central differences of the height field give dh/du and dh/dv per unit uv. Dividing by cells per tile makes the slope
// per cell, so bump strength means the same for any tile scale: the normal is (-dh/dx, -dh/dy, 1) normalised.
void main() {
	float texel = 1.0 / u_TextureSize;
	Surface surface = recipe_surface(v_uv);
	float height_right = recipe_surface(v_uv + vec2(texel, 0.0)).height;
	float height_left = recipe_surface(v_uv - vec2(texel, 0.0)).height;
	float height_up = recipe_surface(v_uv + vec2(0.0, texel)).height;
	float height_down = recipe_surface(v_uv - vec2(0.0, texel)).height;
	vec2 slope_per_cell = vec2(height_right - height_left, height_up - height_down) / (2.0 * texel) / u_CellsPerTile;
	vec3 normal = normalize(vec3(-slope_per_cell * u_BumpStrength, 1.0));
	o_Albedo = vec4(surface.albedo, 1.0);
	o_Normal = vec4(normal * 0.5 + 0.5, surface.height);
	o_Orm = vec4(surface.roughness, surface.metallic, surface.ambient_occlusion, 1.0);
}
#endif
