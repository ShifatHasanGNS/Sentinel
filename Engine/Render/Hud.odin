package Render

import "../GPU"
import easy_font "vendor:stb/easy_font"
import gl "vendor:OpenGL"

HUD_VERTICES_MAX :: 24000 // 4000 quads: ample for a crosshair, bars and a few lines of text.

Hud_Vertex :: struct {
	position: [2]f32,
	color:    [4]f32,
}

// Immediate-mode 2D overlay in pixel coordinates (origin top-left): queue rectangles and text, then flush once over the frame.
// Text comes from stb_easy_font, a vector font that lives in code, so no font file is read.
Hud :: struct {
	shader:   GPU.Shader,
	buffer:   GPU.Buffer,
	array:    u32,
	vertices: [dynamic]Hud_Vertex,
}

Hud_Create :: proc() -> (hud: Hud, ok: bool) {
	hud.shader = GPU.Shader_Create("Shaders/Hud.glsl", nil, true) or_return
	hud.buffer = GPU.Buffer_Create_Empty(.Vertex, HUD_VERTICES_MAX * size_of(Hud_Vertex), .Dynamic)
	gl.GenVertexArrays(1, &hud.array)
	gl.BindVertexArray(hud.array)
	gl.BindBuffer(gl.ARRAY_BUFFER, hud.buffer.id)
	gl.EnableVertexAttribArray(0)
	gl.VertexAttribPointer(0, 2, gl.FLOAT, false, size_of(Hud_Vertex), 0)
	gl.EnableVertexAttribArray(1)
	gl.VertexAttribPointer(1, 4, gl.FLOAT, false, size_of(Hud_Vertex), uintptr(size_of([2]f32)))
	gl.BindVertexArray(0)
	GPU.GL_Check()
	return hud, true
}

Hud_Destroy :: proc(hud: ^Hud) {
	delete(hud.vertices)
	gl.DeleteVertexArrays(1, &hud.array)
	GPU.Buffer_Destroy(&hud.buffer)
	GPU.Shader_Destroy(&hud.shader)
}

Hud_Rect :: proc(hud: ^Hud, x, y, width, height: f32, color: [4]f32) {
	if len(hud.vertices) + 6 > HUD_VERTICES_MAX do return
	corners := [4][2]f32{{x, y}, {x + width, y}, {x + width, y + height}, {x, y + height}}
	for index in ([6]int{0, 1, 2, 0, 2, 3}) do append(&hud.vertices, Hud_Vertex{corners[index], color})
}

Hud_Text :: proc(hud: ^Hud, x, y: f32, text: string, scale: f32, color: [4]f32) {
	quads: [512]easy_font.Quad
	packed := easy_font.Color{u8(color.r * 255), u8(color.g * 255), u8(color.b * 255), u8(color.a * 255)}
	count := easy_font.print(x, y, text, packed, quads[:], scale)
	for quad in quads[:count] {
		top_left, bottom_right := quad.tl.v, quad.br.v
		Hud_Rect(hud, top_left.x, top_left.y, bottom_right.x - top_left.x, bottom_right.y - top_left.y, color)
	}
}

Hud_Text_Width :: proc(text: string, scale: f32) -> f32 {
	return f32(easy_font.width(text)) * scale
}

// Draws everything queued, blended over what is on screen, then clears the queue.
Hud_Flush :: proc(hud: ^Hud, width, height: i32) {
	defer clear(&hud.vertices)
	if len(hud.vertices) == 0 do return
	GPU.Buffer_Write(&hud.buffer, hud.vertices[:])
	gl.Disable(gl.DEPTH_TEST)
	gl.Disable(gl.CULL_FACE)
	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
	GPU.Shader_Use(&hud.shader)
	GPU.Shader_Set(&hud.shader, "u_ScreenSize", [2]f32{f32(width), f32(height)})
	gl.BindVertexArray(hud.array)
	gl.DrawArrays(gl.TRIANGLES, 0, i32(len(hud.vertices)))
	gl.BindVertexArray(0)
	gl.Disable(gl.BLEND)
	GPU.GL_Check()
}
