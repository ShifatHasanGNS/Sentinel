package Render

import "../GPU"

SKY_LUT_WIDTH :: 192
SKY_LUT_HEIGHT :: 128

Sky_Lut :: struct {
	target:     GPU.Framebuffer,
	shader:     GPU.Shader,
	fullscreen: GPU.Fullscreen_Pass,
}

Sky_Lut_Create :: proc() -> (lut: Sky_Lut) {
	shader, ok := GPU.Shader_Create("Shaders/SkyLutPass.glsl", nil, true)
	assert(ok, "Sky_Lut_Create: shader failed to build")
	lut.shader = shader
	lut.target = GPU.Framebuffer_Create({SKY_LUT_WIDTH, SKY_LUT_HEIGHT, {.RGBA16F}, .None})
	lut.fullscreen = GPU.Fullscreen_Pass_Create()
	return lut
}

Sky_Lut_Destroy :: proc(lut: ^Sky_Lut) {
	GPU.Fullscreen_Pass_Destroy(&lut.fullscreen)
	GPU.Framebuffer_Destroy(&lut.target)
	GPU.Shader_Destroy(&lut.shader)
}

// Re-evaluates the atmosphere for the current sun. Leaves the LUT framebuffer bound.
Sky_Lut_Render :: proc(lut: ^Sky_Lut, to_sun: [3]f32, sun_intensity: f32) {
	GPU.Framebuffer_Bind(&lut.target)
	GPU.Shader_Use(&lut.shader)
	GPU.Shader_Set(&lut.shader, "u_ToSun", to_sun)
	GPU.Shader_Set(&lut.shader, "u_SunIntensity", sun_intensity)
	GPU.Fullscreen_Pass_Draw(&lut.fullscreen)
}

Sky_Lut_Bind :: proc(shader: ^GPU.Shader, lut: ^Sky_Lut) {
	GPU.Shader_Set(shader, "u_SkyLut", GPU.Texture_Bind_Next(&lut.target.colors[0], GPU.Sampler_Linear_Repeat))
}
