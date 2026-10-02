package GPU

import gl "vendor:OpenGL"

FRAMEBUFFER_COLOR_ATTACHMENTS_MAX :: 4

Framebuffer_Desc :: struct {
	width:         i32,
	height:        i32,
	color_formats: []Texture_Format,
	depth_format:  Texture_Format,
}

Framebuffer :: struct {
	id:           u32,
	width:        i32,
	height:       i32,
	colors:       [FRAMEBUFFER_COLOR_ATTACHMENTS_MAX]Texture,
	color_count:  int,
	depth:        Texture,
	color_format: [FRAMEBUFFER_COLOR_ATTACHMENTS_MAX]Texture_Format,
	depth_format: Texture_Format,
}

Framebuffer_Create :: proc(desc: Framebuffer_Desc) -> Framebuffer {
	assert(len(desc.color_formats) <= FRAMEBUFFER_COLOR_ATTACHMENTS_MAX, "Framebuffer_Create: too many colour attachments")
	assert(len(desc.color_formats) > 0 || desc.depth_format != .None, "Framebuffer_Create: no attachments")
	framebuffer := Framebuffer{width = desc.width, height = desc.height, color_count = len(desc.color_formats), depth_format = desc.depth_format}
	copy(framebuffer.color_format[:], desc.color_formats)
	build_attachments(&framebuffer)
	return framebuffer
}

Framebuffer_Resize :: proc(framebuffer: ^Framebuffer, width, height: i32) {
	if framebuffer.width == width && framebuffer.height == height do return
	release_attachments(framebuffer)
	framebuffer.width = width
	framebuffer.height = height
	build_attachments(framebuffer)
}

Framebuffer_Bind :: proc(framebuffer: ^Framebuffer) {
	gl.BindFramebuffer(gl.FRAMEBUFFER, framebuffer.id)
	gl.Viewport(0, 0, framebuffer.width, framebuffer.height)
}

Framebuffer_Bind_Default :: proc(width, height: i32) {
	gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
	gl.Viewport(0, 0, width, height)
}

Framebuffer_Destroy :: proc(framebuffer: ^Framebuffer) {
	release_attachments(framebuffer)
	framebuffer^ = {}
}

@(private = "file")
build_attachments :: proc(framebuffer: ^Framebuffer) {
	gl.GenFramebuffers(1, &framebuffer.id)
	gl.BindFramebuffer(gl.FRAMEBUFFER, framebuffer.id)
	draw_buffers: [FRAMEBUFFER_COLOR_ATTACHMENTS_MAX]u32
	for index in 0 ..< framebuffer.color_count {
		texture := Texture_Create({.Texture_2D, framebuffer.color_format[index], framebuffer.width, framebuffer.height, 0, 1})
		framebuffer.colors[index] = texture
		attachment := gl.COLOR_ATTACHMENT0 + u32(index)
		gl.FramebufferTexture2D(gl.FRAMEBUFFER, attachment, gl.TEXTURE_2D, texture.id, 0)
		draw_buffers[index] = attachment
	}
	if framebuffer.depth_format != .None {
		framebuffer.depth = Texture_Create({.Texture_2D, framebuffer.depth_format, framebuffer.width, framebuffer.height, 0, 1})
		gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.TEXTURE_2D, framebuffer.depth.id, 0)
	}
	if framebuffer.color_count > 0 {
		gl.DrawBuffers(i32(framebuffer.color_count), &draw_buffers[0])
	} else {
		gl.DrawBuffer(gl.NONE)
		gl.ReadBuffer(gl.NONE)
	}
	assert(gl.CheckFramebufferStatus(gl.FRAMEBUFFER) == gl.FRAMEBUFFER_COMPLETE, "Framebuffer incomplete")
	GL_Check()
}

@(private = "file")
release_attachments :: proc(framebuffer: ^Framebuffer) {
	for index in 0 ..< framebuffer.color_count do Texture_Destroy(&framebuffer.colors[index])
	if framebuffer.depth_format != .None do Texture_Destroy(&framebuffer.depth)
	gl.DeleteFramebuffers(1, &framebuffer.id)
}

Layer_Target :: struct {
	texture: ^Texture,
	layer:   i32,
}

// A framebuffer that renders into layers of textures it does not own, so destroying it frees only the framebuffer object.
Framebuffer_Create_For_Layers :: proc(width, height: i32) -> Framebuffer {
	framebuffer := Framebuffer{width = width, height = height}
	gl.GenFramebuffers(1, &framebuffer.id)
	return framebuffer
}

Framebuffer_Set_Layers :: proc(framebuffer: ^Framebuffer, targets: []Layer_Target) {
	assert(len(targets) >= 1 && len(targets) <= FRAMEBUFFER_COLOR_ATTACHMENTS_MAX, "Framebuffer_Set_Layers: 1 to 4 targets")
	gl.BindFramebuffer(gl.FRAMEBUFFER, framebuffer.id)
	draw_buffers: [FRAMEBUFFER_COLOR_ATTACHMENTS_MAX]u32
	for target, index in targets {
		attachment := gl.COLOR_ATTACHMENT0 + u32(index)
		gl.FramebufferTextureLayer(gl.FRAMEBUFFER, attachment, target.texture.id, 0, target.layer)
		draw_buffers[index] = attachment
	}
	gl.DrawBuffers(i32(len(targets)), &draw_buffers[0])
	assert(gl.CheckFramebufferStatus(gl.FRAMEBUFFER) == gl.FRAMEBUFFER_COMPLETE, "Framebuffer incomplete")
	GL_Check()
}
