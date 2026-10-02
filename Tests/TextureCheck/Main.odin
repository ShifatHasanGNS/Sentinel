package main

import "../../Engine/GPU"
import "../../Game/Materials"
import "../../Engine/Platform"
import "../../Engine/Procedural"
import "../Support"
import "core:fmt"
import "core:math"
import "core:os"

PROBE_SIZE :: 64

// Bake and noise checks need a GL context, so they run as a program on the main thread, not under `odin test`.
main :: proc() {
	checks: Support.Checks
	window, window_ok := Platform.Window_Create("Texture check", 64, 64, false)
	if !window_ok do os.exit(1)
	defer Platform.Window_Destroy(&window)
	defer GPU.Sampler_Cache_Destroy()

	check_noise_probe(&checks)
	check_normal_from_height_on_a_ramp(&checks)
	check_albedo_survives_the_srgb_round_trip(&checks)
	check_every_material_tiles_and_has_detail(&checks)
	fmt.printfln("%d checks passed, %d failed", checks.passed, checks.failed)
	if checks.failed > 0 do os.exit(1)
}

render_noise_probe :: proc(shader: ^GPU.Shader, mode: i32) -> (pixels: [PROBE_SIZE * PROBE_SIZE][4]f32) {
	target := GPU.Framebuffer_Create({PROBE_SIZE, PROBE_SIZE, {.RGBA32F}, .None})
	defer GPU.Framebuffer_Destroy(&target)
	pass := GPU.Fullscreen_Pass_Create()
	defer GPU.Fullscreen_Pass_Destroy(&pass)
	GPU.Framebuffer_Bind(&target)
	GPU.Shader_Use(shader)
	GPU.Shader_Set(shader, "u_Mode", mode)
	GPU.Fullscreen_Pass_Draw(&pass)
	GPU.Texture_Read_2D(&target.colors[0], pixels[:])
	return pixels
}

check_noise_probe :: proc(checks: ^Support.Checks) {
	shader, ok := GPU.Shader_Create("Tests/TextureCheck/Fixtures/NoiseProbe.glsl")
	Support.expect(checks, ok)
	if !ok do return
	defer GPU.Shader_Destroy(&shader)

	for mode in 0 ..< i32(3) {
		pixels := render_noise_probe(&shader, mode)
		worst_period_error: f32
		for pixel in pixels do worst_period_error = max(worst_period_error, abs(pixel.x - pixel.y))
		Support.expect(checks, worst_period_error < 1e-3)
	}

	gradient := render_noise_probe(&shader, 0)
	lowest, highest: f32 = 1, -1
	differing_seed_count := 0
	for pixel in gradient {
		lowest, highest = min(lowest, pixel.x), max(highest, pixel.x)
		if abs(pixel.x - pixel.z) > 1e-3 do differing_seed_count += 1
	}
	Support.expect(checks, lowest >= -1 && highest <= 1)
	Support.expect(checks, highest - lowest > 1)
	Support.expect(checks, differing_seed_count > len(gradient) / 2)

	for pixel in render_noise_probe(&shader, 3) do Support.expect(checks, abs(pixel.x) < 1e-5)
	for pixel in render_noise_probe(&shader, 2) do Support.expect(checks, pixel.x >= 0 && pixel.x <= 1.5 && pixel.z >= pixel.x)
}

near :: proc(actual: u8, expected: f32, tolerance: f32) -> bool {
	return abs(f32(actual) - expected) <= tolerance
}

// Height = u. At bump strength 2 over 1 cell the slope is 2, so the normal is (-2, 0, 1) / sqrt(5), packed as n * 0.5 + 0.5.
check_normal_from_height_on_a_ramp :: proc(checks: ^Support.Checks) {
	recipe := Procedural.Texture_Recipe{shader_path = "Tests/TextureCheck/Fixtures/RampRecipe.glsl", seed = 1, cells_per_tile = 1, bump_strength = 2}
	set, ok := Procedural.Texture_Set_Bake({recipe}, PROBE_SIZE)
	Support.expect(checks, ok)
	if !ok do return
	defer Procedural.Texture_Set_Destroy(&set)

	normal: [PROBE_SIZE * PROBE_SIZE][4]u8
	GPU.Texture_Read_Layer(&set.normal, 0, normal[:])
	centre := normal[PROBE_SIZE / 2 * PROBE_SIZE + PROBE_SIZE / 2]
	Support.expect(checks, near(centre.x, 255 * (0.5 - 1 / math.sqrt(f32(5))), 2))
	Support.expect(checks, near(centre.y, 127.5, 2))
	Support.expect(checks, near(centre.z, 255 * (0.5 + 0.5 / math.sqrt(f32(5))), 2))
	Support.expect(checks, near(centre.w, 255 * (f32(PROBE_SIZE / 2) + 0.5) / PROBE_SIZE, 2))

	orm: [PROBE_SIZE * PROBE_SIZE][4]u8
	GPU.Texture_Read_Layer(&set.orm, 0, orm[:])
	Support.expect(checks, near(orm[0].x, 64, 1) && near(orm[0].y, 191, 1) && near(orm[0].z, 255, 1))
}

// The recipe writes linear 0.5. The sRGB target stores it encoded (about 188) and sampling decodes it, so a linear read must give 128.
check_albedo_survives_the_srgb_round_trip :: proc(checks: ^Support.Checks) {
	recipe := Procedural.Texture_Recipe{shader_path = "Tests/TextureCheck/Fixtures/RampRecipe.glsl", seed = 1, cells_per_tile = 1, bump_strength = 1}
	set, ok := Procedural.Texture_Set_Bake({recipe}, PROBE_SIZE)
	Support.expect(checks, ok)
	if !ok do return
	defer Procedural.Texture_Set_Destroy(&set)
	sampled := sample_array_texel(&set.albedo, 0)
	Support.expect(checks, near(sampled.x, 127.5, 1.5) && near(sampled.w, 255, 0))
	raw: [PROBE_SIZE * PROBE_SIZE][4]u8
	GPU.Texture_Read_Layer(&set.albedo, 0, raw[:])
	Support.expect(checks, raw[0].x > 170) // Stored encoded, not linear.
}

sample_array_texel :: proc(array: ^GPU.Texture, layer: i32) -> [4]u8 {
	reader, ok := GPU.Shader_Create_From_Source(`#version 410 core
void main() {
	vec2 corner = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
	gl_Position = vec4(corner * 2.0 - 1.0, 0.0, 1.0);
}
`, `#version 410 core
uniform sampler2DArray u_Layers;
uniform int u_Layer;
out vec4 color;
void main() { color = texelFetch(u_Layers, ivec3(8, 8, u_Layer), 0); }
`, "array sampler")
	assert(ok)
	defer GPU.Shader_Destroy(&reader)
	destination := GPU.Framebuffer_Create({1, 1, {.RGBA8}, .None})
	defer GPU.Framebuffer_Destroy(&destination)
	pass := GPU.Fullscreen_Pass_Create()
	defer GPU.Fullscreen_Pass_Destroy(&pass)
	GPU.Texture_Units_Reset()
	unit := GPU.Texture_Bind_Next(array, GPU.Sampler_Nearest_Clamp)
	GPU.Shader_Set(&reader, "u_Layers", unit)
	GPU.Shader_Set(&reader, "u_Layer", layer)
	GPU.Framebuffer_Bind(&destination)
	GPU.Shader_Use(&reader)
	GPU.Fullscreen_Pass_Draw(&pass)
	pixel: [1][4]u8
	GPU.Texture_Read_2D(&destination.colors[0], pixel[:])
	return pixel[0]
}

// Evaluates each recipe at uv and at uv + whole tiles on the GPU; a seamlessly tiling recipe returns identical surfaces.
check_every_material_tiles_and_has_detail :: proc(checks: ^Support.Checks) {
	recipes := Materials.Materials_Recipes()
	for recipe, material in recipes do check_recipe_tiles(checks, recipe, material)

	set, ok := Materials.Materials_Bake()
	Support.expect(checks, ok)
	if !ok do return
	defer Procedural.Texture_Set_Destroy(&set)
	Support.expect_value(checks, int(set.layer_count), len(Materials.Surface_Material))
	pixels := make([][4]u8, int(set.size) * int(set.size))
	defer delete(pixels)
	for layer in 0 ..< set.layer_count {
		GPU.Texture_Read_Layer(&set.albedo, layer, pixels)
		Support.expect(checks, standard_deviation(pixels, 0) > 2)
		GPU.Texture_Read_Layer(&set.normal, layer, pixels)
		Support.expect(checks, standard_deviation(pixels, 0) > 2) // Normals must lean: a flat map would be constant.
	}
}

check_recipe_tiles :: proc(checks: ^Support.Checks, recipe: Procedural.Texture_Recipe, material: Materials.Surface_Material) {
	shader, ok := GPU.Shader_Create(recipe.shader_path, {"BAKE_PERIODICITY_PROBE"}, true)
	Support.expect(checks, ok)
	if !ok do return
	defer GPU.Shader_Destroy(&shader)
	Procedural.Texture_Recipe_Set_Uniforms(&shader, recipe, PROBE_SIZE)
	target := GPU.Framebuffer_Create({PROBE_SIZE, PROBE_SIZE, {.RGBA32F, .RGBA32F, .RGBA32F}, .None})
	defer GPU.Framebuffer_Destroy(&target)
	pass := GPU.Fullscreen_Pass_Create()
	defer GPU.Fullscreen_Pass_Destroy(&pass)
	GPU.Framebuffer_Bind(&target)
	GPU.Shader_Use(&shader)
	GPU.Fullscreen_Pass_Draw(&pass)
	for attachment in 0 ..< 2 {
		differences: [PROBE_SIZE * PROBE_SIZE][4]f32
		GPU.Texture_Read_2D(&target.colors[attachment], differences[:])
		worst: f32
		for difference in differences do worst = max(worst, max(difference.x, difference.y, difference.z, difference.w))
		if worst >= 1e-3 do fmt.eprintfln("material %v does not tile: worst difference %f", material, worst)
		Support.expect(checks, worst < 1e-3)
	}
}

standard_deviation :: proc(pixels: [][4]u8, channel: int) -> f32 {
	mean: f32
	for pixel in pixels do mean += f32(pixel[channel]) / f32(len(pixels))
	variance: f32
	for pixel in pixels do variance += (f32(pixel[channel]) - mean) * (f32(pixel[channel]) - mean) / f32(len(pixels))
	return math.sqrt(variance)
}
