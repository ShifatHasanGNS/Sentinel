package Render

import "../GPU"
import gl "vendor:OpenGL"

BLOOM_LEVELS :: 5
BLOOM_THRESHOLD :: 1.2

// A mip-like chain of half-resolution HDR targets. Down: 13-tap filter from the scene. Up: tent filter added back level by level,
// so the result is a sum of progressively wider blurs (a cheap approximation of a very wide gaussian).
Bloom :: struct {
	levels:     [BLOOM_LEVELS]GPU.Framebuffer,
	downsample: GPU.Shader,
	upsample:   GPU.Shader,
}

Bloom_Create :: proc(width, height: i32) -> (bloom: Bloom, ok: bool) {
	bloom.downsample = GPU.Shader_Create("Shaders/PostBloom.glsl", {"DOWNSAMPLE"}, true) or_return
	bloom.upsample = GPU.Shader_Create("Shaders/PostBloom.glsl", nil, true) or_return
	for &level, index in bloom.levels do level = GPU.Framebuffer_Create({max(width >> u32(index + 1), 1), max(height >> u32(index + 1), 1), {.RGBA16F}, .None})
	return bloom, true
}

Bloom_Destroy :: proc(bloom: ^Bloom) {
	for &level in bloom.levels do GPU.Framebuffer_Destroy(&level)
	GPU.Shader_Destroy(&bloom.upsample)
	GPU.Shader_Destroy(&bloom.downsample)
}

// Leaves the blurred highlights in levels[0]; the tonemap pass adds it to the scene.
Bloom_Render :: proc(bloom: ^Bloom, scene: ^GPU.Texture, scene_width, scene_height: i32, fullscreen: ^GPU.Fullscreen_Pass) {
	gl.Disable(gl.DEPTH_TEST)
	gl.Disable(gl.BLEND)
	source, source_width, source_height := scene, scene_width, scene_height
	for &level, index in bloom.levels {
		GPU.Framebuffer_Resize(&level, max(scene_width >> u32(index + 1), 1), max(scene_height >> u32(index + 1), 1))
		GPU.Framebuffer_Bind(&level)
		bloom_pass(&bloom.downsample, source, source_width, source_height, BLOOM_THRESHOLD if index == 0 else 0, fullscreen)
		source, source_width, source_height = &level.colors[0], level.width, level.height
	}
	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.ONE, gl.ONE)
	for index := BLOOM_LEVELS - 1; index > 0; index -= 1 {
		smaller, larger := &bloom.levels[index], &bloom.levels[index - 1]
		GPU.Framebuffer_Bind(larger)
		bloom_pass(&bloom.upsample, &smaller.colors[0], smaller.width, smaller.height, 0, fullscreen)
	}
	gl.Disable(gl.BLEND)
}

@(private = "file")
bloom_pass :: proc(shader: ^GPU.Shader, source: ^GPU.Texture, width, height: i32, threshold: f32, fullscreen: ^GPU.Fullscreen_Pass) {
	GPU.Shader_Use(shader)
	GPU.Texture_Units_Reset()
	GPU.Shader_Set(shader, "u_Source", GPU.Texture_Bind_Next(source, GPU.Sampler_Linear_Clamp))
	GPU.Shader_Set(shader, "u_TexelSize", [2]f32{1 / f32(width), 1 / f32(height)})
	GPU.Shader_Set(shader, "u_Threshold", threshold)
	GPU.Fullscreen_Pass_Draw(fullscreen)
}
