package main

import "../../Engine/Platform"
import "core:fmt"
import "core:os"
import "../Support"
import gpu "../../Engine/GPU"

// GL contexts and macOS windowing are main-thread-only, so these checks run as a program, not under `odin test`.
main :: proc() {
	checks: Support.Checks
	c := &checks
	window, window_ok := Platform.Window_Create("GPU test", 64, 64, false)
	Support.expect(c, window_ok)
	if !window_ok do os.exit(1)
	defer Platform.Window_Destroy(&window)
	defer gpu.Sampler_Cache_Destroy()

	check_texture_round_trip_rgba8(c)
	check_texture_round_trip_rgba32f(c)
	check_mip_chain_length_and_generation(c)
	check_sampler_cache(c)
	check_shader_uniform_and_framebuffer(c)
	check_uniform_block(c)
	check_array_texture_layer_sampling(c)
	check_bad_shader_reports_failure(c)
	check_render_into_array_layer(c)
	fmt.printfln("%d checks passed, %d failed", checks.passed, checks.failed)
	if checks.failed > 0 do os.exit(1)
}

check_texture_round_trip_rgba8 :: proc(c: ^Support.Checks) {
	texture := gpu.Texture_Create({.Texture_2D, .RGBA8, 4, 4, 0, 1})
	defer gpu.Texture_Destroy(&texture)
	pixels: [16][4]u8
	for index in 0 ..< 16 do pixels[index] = {u8(index * 16), u8(255 - index), u8(index), 255}
	gpu.Texture_Upload(&texture, pixels[:])
	read_back: [16][4]u8
	gpu.Texture_Read_2D(&texture, read_back[:])
	Support.expect_value(c, read_back, pixels)
}

check_texture_round_trip_rgba32f :: proc(c: ^Support.Checks) {
	texture := gpu.Texture_Create({.Texture_2D, .RGBA32F, 2, 2, 0, 1})
	defer gpu.Texture_Destroy(&texture)
	pixels := [4][4]f32{{0.5, -2, 100, 1}, {0, 0, 0, 0}, {1e-3, 1e3, -1e3, 0.25}, {3, 2, 1, 0}}
	gpu.Texture_Upload(&texture, pixels[:])
	read_back: [4][4]f32
	gpu.Texture_Read_2D(&texture, read_back[:])
	Support.expect_value(c, read_back, pixels)
}

check_mip_chain_length_and_generation :: proc(c: ^Support.Checks) {
	texture := gpu.Texture_Create({.Texture_2D, .RGBA8, 8, 4, 0, 0})
	defer gpu.Texture_Destroy(&texture)
	Support.expect_value(c, texture.mip_levels, 4)
	white: [32][4]u8
	for &pixel in white do pixel = {255, 255, 255, 255}
	gpu.Texture_Upload(&texture, white[:])
	gpu.Texture_Generate_Mips(&texture)
	last_level: [1][4]u8
	gpu.Texture_Read_2D(&texture, last_level[:], 3)
	Support.expect_value(c, last_level[0], [4]u8{255, 255, 255, 255})
	single := gpu.Texture_Create({.Texture_2D, .RGBA8, 4, 4, 0, 1})
	defer gpu.Texture_Destroy(&single)
	white_4x4: [16][4]u8
	for &pixel in white_4x4 do pixel = {255, 255, 255, 255}
	gpu.Texture_Upload(&single, white_4x4[:])
	gpu.Texture_Generate_Mips(&single)
	Support.expect_value(c, single.mip_levels, 3)
	generated_level: [1][4]u8
	gpu.Texture_Read_2D(&single, generated_level[:], 2)
	Support.expect_value(c, generated_level[0], [4]u8{255, 255, 255, 255})
	odd := gpu.Texture_Create({.Texture_2D, .R8, 1, 1, 0, 0})
	defer gpu.Texture_Destroy(&odd)
	Support.expect_value(c, odd.mip_levels, 1)
}

check_sampler_cache :: proc(c: ^Support.Checks) {
	first := gpu.Sampler_Get(gpu.Sampler_Trilinear_Repeat)
	Support.expect_value(c, gpu.Sampler_Get(gpu.Sampler_Trilinear_Repeat), first)
	Support.expect(c, gpu.Sampler_Get(gpu.Sampler_Nearest_Clamp) != first)
	Support.expect(c, gpu.Sampler_Get(gpu.Sampler_Shadow) != gpu.Sampler_Get(gpu.Sampler_Linear_Clamp))
}

SOLID_COLOR_VERTEX :: `#version 410 core
void main() {
	vec2 corner = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
	gl_Position = vec4(corner * 2.0 - 1.0, 0.0, 1.0);
}
`

check_shader_uniform_and_framebuffer :: proc(c: ^Support.Checks) {
	shader, ok := gpu.Shader_Create_From_Source(SOLID_COLOR_VERTEX, `#version 410 core
uniform vec3 u_Color;
out vec4 color;
void main() { color = vec4(u_Color, 1.0); }
`, "solid color")
	Support.expect(c, ok)
	defer gpu.Shader_Destroy(&shader)
	framebuffer := gpu.Framebuffer_Create({4, 4, {.RGBA8}, .None})
	defer gpu.Framebuffer_Destroy(&framebuffer)
	pass := gpu.Fullscreen_Pass_Create()
	defer gpu.Fullscreen_Pass_Destroy(&pass)

	gpu.Framebuffer_Bind(&framebuffer)
	gpu.Shader_Use(&shader)
	gpu.Shader_Set(&shader, "u_Color", [3]f32{1, 0, 0.5})
	gpu.Fullscreen_Pass_Draw(&pass)
	pixels: [16][4]u8
	gpu.Texture_Read_2D(&framebuffer.colors[0], pixels[:])
	Support.expect_value(c, pixels[0], [4]u8{255, 0, 128, 255})
	Support.expect_value(c, pixels[15], [4]u8{255, 0, 128, 255})

	gpu.Framebuffer_Resize(&framebuffer, 8, 2)
	Support.expect_value(c, framebuffer.width, 8)
	gpu.Framebuffer_Bind(&framebuffer)
	gpu.Shader_Set(&shader, "u_Color", [3]f32{0, 1, 0})
	gpu.Fullscreen_Pass_Draw(&pass)
	resized: [16][4]u8
	gpu.Texture_Read_2D(&framebuffer.colors[0], resized[:])
	Support.expect_value(c, resized[15], [4]u8{0, 255, 0, 255})
}

Block_Data :: struct {
	color: [4]f32,
}

check_uniform_block :: proc(c: ^Support.Checks) {
	shader, ok := gpu.Shader_Create_From_Source(SOLID_COLOR_VERTEX, `#version 410 core
layout(std140) uniform Block { vec4 block_color; };
out vec4 color;
void main() { color = block_color; }
`, "uniform block")
	Support.expect(c, ok)
	defer gpu.Shader_Destroy(&shader)
	gpu.Shader_Bind_Uniform_Block(&shader, "Block", 3)
	block := gpu.Uniform_Block_Create(3, size_of(Block_Data))
	defer gpu.Uniform_Block_Destroy(&block)
	data := Block_Data{{0, 0, 1, 1}}
	gpu.Uniform_Block_Write(&block, &data)
	framebuffer := gpu.Framebuffer_Create({2, 2, {.RGBA8}, .None})
	defer gpu.Framebuffer_Destroy(&framebuffer)
	pass := gpu.Fullscreen_Pass_Create()
	defer gpu.Fullscreen_Pass_Destroy(&pass)
	gpu.Framebuffer_Bind(&framebuffer)
	gpu.Shader_Use(&shader)
	gpu.Fullscreen_Pass_Draw(&pass)
	pixels: [4][4]u8
	gpu.Texture_Read_2D(&framebuffer.colors[0], pixels[:])
	Support.expect_value(c, pixels[0], [4]u8{0, 0, 255, 255})
}

check_array_texture_layer_sampling :: proc(c: ^Support.Checks) {
	array := gpu.Texture_Create({.Texture_2D_Array, .RGBA8, 1, 1, 3, 1})
	defer gpu.Texture_Destroy(&array)
	layers := [3][1][4]u8{{{10, 0, 0, 255}}, {{0, 200, 0, 255}}, {{0, 0, 90, 255}}}
	for index in 0 ..< 3 do gpu.Texture_Upload(&array, layers[index][:], 0, i32(index))
	shader, ok := gpu.Shader_Create_From_Source(SOLID_COLOR_VERTEX, `#version 410 core
uniform sampler2DArray u_Layers;
out vec4 color;
void main() { color = texelFetch(u_Layers, ivec3(0, 0, 1), 0); }
`, "array sampling")
	Support.expect(c, ok)
	defer gpu.Shader_Destroy(&shader)
	framebuffer := gpu.Framebuffer_Create({1, 1, {.RGBA8}, .None})
	defer gpu.Framebuffer_Destroy(&framebuffer)
	pass := gpu.Fullscreen_Pass_Create()
	defer gpu.Fullscreen_Pass_Destroy(&pass)
	gpu.Texture_Units_Reset()
	unit := gpu.Texture_Bind_Next(&array, gpu.Sampler_Nearest_Clamp)
	gpu.Shader_Set(&shader, "u_Layers", unit)
	gpu.Framebuffer_Bind(&framebuffer)
	gpu.Shader_Use(&shader)
	gpu.Fullscreen_Pass_Draw(&pass)
	pixel: [1][4]u8
	gpu.Texture_Read_2D(&framebuffer.colors[0], pixel[:])
	Support.expect_value(c, pixel[0], [4]u8{0, 200, 0, 255})
}

check_bad_shader_reports_failure :: proc(c: ^Support.Checks) {
	_, ok := gpu.Shader_Create_From_Source(SOLID_COLOR_VERTEX, "#version 410 core\nvoid main() { not valid }\n", "deliberately broken")
	Support.expect(c, !ok)
}

check_render_into_array_layer :: proc(c: ^Support.Checks) {
	array := gpu.Texture_Create({.Texture_2D_Array, .RGBA8, 2, 2, 3, 1})
	defer gpu.Texture_Destroy(&array)
	painter, painter_ok := gpu.Shader_Create_From_Source(SOLID_COLOR_VERTEX, `#version 410 core
layout(location = 0) out vec4 first;
layout(location = 1) out vec4 second;
void main() { first = vec4(1.0, 0.0, 0.0, 1.0); second = vec4(0.0, 0.0, 1.0, 1.0); }
`, "layer painter")
	Support.expect(c, painter_ok)
	defer gpu.Shader_Destroy(&painter)
	other := gpu.Texture_Create({.Texture_2D_Array, .RGBA8, 2, 2, 3, 1})
	defer gpu.Texture_Destroy(&other)
	target := gpu.Framebuffer_Create_For_Layers(2, 2)
	defer gpu.Framebuffer_Destroy(&target)
	gpu.Framebuffer_Set_Layers(&target, {{&array, 2}, {&other, 1}})
	pass := gpu.Fullscreen_Pass_Create()
	defer gpu.Fullscreen_Pass_Destroy(&pass)
	gpu.Framebuffer_Bind(&target)
	gpu.Shader_Use(&painter)
	gpu.Fullscreen_Pass_Draw(&pass)

	Support.expect_value(c, read_array_texel(&array, 2), [4]u8{255, 0, 0, 255})
	Support.expect_value(c, read_array_texel(&array, 0), [4]u8{0, 0, 0, 0})
	Support.expect_value(c, read_array_texel(&other, 1), [4]u8{0, 0, 255, 255})
	Support.expect_value(c, read_array_texel(&other, 2), [4]u8{0, 0, 0, 0})
}

read_array_texel :: proc(array: ^gpu.Texture, layer: i32) -> [4]u8 {
	reader, _ := gpu.Shader_Create_From_Source(SOLID_COLOR_VERTEX, `#version 410 core
uniform sampler2DArray u_Layers;
uniform int u_Layer;
out vec4 color;
void main() { color = texelFetch(u_Layers, ivec3(0, 0, u_Layer), 0); }
`, "layer reader")
	defer gpu.Shader_Destroy(&reader)
	destination := gpu.Framebuffer_Create({1, 1, {.RGBA8}, .None})
	defer gpu.Framebuffer_Destroy(&destination)
	pass := gpu.Fullscreen_Pass_Create()
	defer gpu.Fullscreen_Pass_Destroy(&pass)
	gpu.Texture_Units_Reset()
	unit := gpu.Texture_Bind_Next(array, gpu.Sampler_Nearest_Clamp)
	gpu.Shader_Set(&reader, "u_Layers", unit)
	gpu.Shader_Set(&reader, "u_Layer", layer)
	gpu.Framebuffer_Bind(&destination)
	gpu.Shader_Use(&reader)
	gpu.Fullscreen_Pass_Draw(&pass)
	pixel: [1][4]u8
	gpu.Texture_Read_2D(&destination.colors[0], pixel[:])
	return pixel[0]
}
