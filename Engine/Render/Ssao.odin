package Render

import "../GPU"
import gl "vendor:OpenGL"

// Screen-space ambient occlusion: a noisy hemisphere visibility estimate, then a 4x4 box blur that exactly cancels the 4x4 noise.
Ssao :: struct {
	raw:     GPU.Framebuffer,
	blurred: GPU.Framebuffer,
	sample:  GPU.Shader,
	blur:    GPU.Shader,
}

Ssao_Create :: proc(width, height: i32) -> (ssao: Ssao, ok: bool) {
	ssao.sample = GPU.Shader_Create("Shaders/PostSsao.glsl", nil, true) or_return
	ssao.blur = GPU.Shader_Create("Shaders/PostSsao.glsl", {"BLUR"}, true) or_return
	ssao.raw = GPU.Framebuffer_Create({width, height, {.R8}, .None})
	ssao.blurred = GPU.Framebuffer_Create({width, height, {.R8}, .None})
	return ssao, true
}

Ssao_Destroy :: proc(ssao: ^Ssao) {
	GPU.Framebuffer_Destroy(&ssao.blurred)
	GPU.Framebuffer_Destroy(&ssao.raw)
	GPU.Shader_Destroy(&ssao.blur)
	GPU.Shader_Destroy(&ssao.sample)
}

// Leaves the result in `blurred`: 1 is open, 0 is fully occluded.
Ssao_Render :: proc(renderer: ^Renderer, camera: Camera, radius_meters: f32) {
	ssao := &renderer.ssao
	GPU.Framebuffer_Resize(&ssao.raw, renderer.gbuffer.width, renderer.gbuffer.height)
	GPU.Framebuffer_Resize(&ssao.blurred, renderer.gbuffer.width, renderer.gbuffer.height)
	gl.Disable(gl.DEPTH_TEST)
	gl.Disable(gl.BLEND)
	GPU.Framebuffer_Bind(&ssao.raw)
	GPU.Shader_Use(&ssao.sample)
	bind_gbuffer(&ssao.sample, renderer, camera)
	GPU.Shader_Set(&ssao.sample, "u_ViewProjection", camera.view_projection)
	GPU.Shader_Set(&ssao.sample, "u_Radius", radius_meters)
	GPU.Fullscreen_Pass_Draw(&renderer.fullscreen)
	GPU.Framebuffer_Bind(&ssao.blurred)
	GPU.Shader_Use(&ssao.blur)
	GPU.Texture_Units_Reset()
	GPU.Shader_Set(&ssao.blur, "u_Ao", GPU.Texture_Bind_Next(&ssao.raw.colors[0], GPU.Sampler_Nearest_Clamp))
	GPU.Shader_Set(&ssao.blur, "u_TexelSize", [2]f32{1 / f32(ssao.raw.width), 1 / f32(ssao.raw.height)})
	GPU.Fullscreen_Pass_Draw(&renderer.fullscreen)
}
