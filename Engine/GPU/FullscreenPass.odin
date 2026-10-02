package GPU

import gl "vendor:OpenGL"

// One oversized triangle covers the screen; positions come from gl_VertexID, so no vertex data is needed.
Fullscreen_Pass :: struct {
	empty_vertex_array: u32,
}

Fullscreen_Pass_Create :: proc() -> Fullscreen_Pass {
	pass: Fullscreen_Pass
	gl.GenVertexArrays(1, &pass.empty_vertex_array)
	return pass
}

Fullscreen_Pass_Draw :: proc(pass: ^Fullscreen_Pass) {
	gl.BindVertexArray(pass.empty_vertex_array)
	gl.DrawArrays(gl.TRIANGLES, 0, 3)
	GL_Check()
}

Fullscreen_Pass_Destroy :: proc(pass: ^Fullscreen_Pass) {
	gl.DeleteVertexArrays(1, &pass.empty_vertex_array)
	pass^ = {}
}
