package Support

import "../../Engine/GPU"

// Renders a fullscreen shader into an RGBA32F target of the given size and returns every pixel. Call between Texture_Units_Reset and draw setup as needed.
Probe_Render :: proc(shader: ^GPU.Shader, width, height: i32) -> []([4]f32) {
	target := GPU.Framebuffer_Create({width, height, {.RGBA32F}, .None})
	defer GPU.Framebuffer_Destroy(&target)
	pass := GPU.Fullscreen_Pass_Create()
	defer GPU.Fullscreen_Pass_Destroy(&pass)
	GPU.Framebuffer_Bind(&target)
	GPU.Shader_Use(shader)
	GPU.Fullscreen_Pass_Draw(&pass)
	pixels := make([][4]f32, int(width) * int(height))
	GPU.Texture_Read_2D(&target.colors[0], pixels)
	return pixels
}
