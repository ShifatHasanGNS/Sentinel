package Procedural

import "../GPU"
import gl "vendor:OpenGL"

// A recipe is a GLSL surface function plus parameters. cells_per_tile must be a whole number so the periodic noise tiles.
// Colour and detail meanings belong to each recipe's shader.
Texture_Recipe :: struct {
	shader_path:    string,
	seed:           u32,
	cells_per_tile: i32,
	colors:         [3][3]f32,
	detail:         f32,
	bump_strength:  f32,
}

// One array layer per recipe, in recipe order.
Texture_Set :: struct {
	albedo:      GPU.Texture, // sRGB; sampling returns linear.
	normal:      GPU.Texture, // xyz = tangent-space normal * 0.5 + 0.5, w = height.
	orm:         GPU.Texture, // x = roughness, y = metallic, z = ambient occlusion.
	layer_count: i32,
	size:        i32,
}

Texture_Set_Bake :: proc(recipes: []Texture_Recipe, size: i32) -> (set: Texture_Set, ok: bool) {
	assert(len(recipes) > 0, "Texture_Set_Bake: no recipes")
	assert(size > 0, "Texture_Set_Bake: size must be positive")
	set = Texture_Set{layer_count = i32(len(recipes)), size = size}
	set.albedo = GPU.Texture_Create({.Texture_2D_Array, .SRGB8_A8, size, size, set.layer_count, 1})
	set.normal = GPU.Texture_Create({.Texture_2D_Array, .RGBA8, size, size, set.layer_count, 1})
	set.orm = GPU.Texture_Create({.Texture_2D_Array, .RGBA8, size, size, set.layer_count, 1})
	target := GPU.Framebuffer_Create_For_Layers(size, size)
	defer GPU.Framebuffer_Destroy(&target)
	pass := GPU.Fullscreen_Pass_Create()
	defer GPU.Fullscreen_Pass_Destroy(&pass)
	for recipe, layer in recipes {
		if !bake_layer(&set, &target, &pass, recipe, i32(layer)) {
			Texture_Set_Destroy(&set)
			return {}, false
		}
	}
	GPU.Texture_Generate_Mips(&set.albedo)
	GPU.Texture_Generate_Mips(&set.normal)
	GPU.Texture_Generate_Mips(&set.orm)
	return set, true
}

Texture_Set_Destroy :: proc(set: ^Texture_Set) {
	GPU.Texture_Destroy(&set.albedo)
	GPU.Texture_Destroy(&set.normal)
	GPU.Texture_Destroy(&set.orm)
	set^ = {}
}

@(private = "file")
bake_layer :: proc(set: ^Texture_Set, target: ^GPU.Framebuffer, pass: ^GPU.Fullscreen_Pass, recipe: Texture_Recipe, layer: i32) -> bool {
	assert(recipe.cells_per_tile >= 1, "Texture_Recipe: cells_per_tile must be >= 1")
	shader, ok := GPU.Shader_Create(recipe.shader_path, nil, true)
	if !ok do return false
	defer GPU.Shader_Destroy(&shader)
	Texture_Recipe_Set_Uniforms(&shader, recipe, set.size)
	GPU.Framebuffer_Set_Layers(target, {{&set.albedo, layer}, {&set.normal, layer}, {&set.orm, layer}})
	GPU.Framebuffer_Bind(target)
	GPU.Shader_Use(&shader)
	gl.Enable(gl.FRAMEBUFFER_SRGB)
	GPU.Fullscreen_Pass_Draw(pass)
	gl.Disable(gl.FRAMEBUFFER_SRGB)
	return true
}

Texture_Recipe_Set_Uniforms :: proc(shader: ^GPU.Shader, recipe: Texture_Recipe, size: i32) {
	GPU.Shader_Set(shader, "u_Seed", f32(recipe.seed))
	GPU.Shader_Set(shader, "u_CellsPerTile", f32(recipe.cells_per_tile))
	GPU.Shader_Set(shader, "u_ColorA", recipe.colors[0])
	GPU.Shader_Set(shader, "u_ColorB", recipe.colors[1])
	GPU.Shader_Set(shader, "u_ColorC", recipe.colors[2])
	GPU.Shader_Set(shader, "u_Detail", recipe.detail)
	GPU.Shader_Set(shader, "u_BumpStrength", recipe.bump_strength)
	GPU.Shader_Set(shader, "u_TextureSize", f32(size))
}
