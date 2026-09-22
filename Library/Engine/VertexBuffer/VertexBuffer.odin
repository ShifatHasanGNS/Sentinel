package VertexBuffer

import dbg "../Debugger"
import gl "vendor:OpenGL"

VertexBuffer :: struct {
	RendererID: u32,
}

New :: proc(data: []$T) -> VertexBuffer {
	v_buffer := VertexBuffer{}

	gl.GenBuffers(1, &v_buffer.RendererID); dbg.GL_Check()
	gl.BindBuffer(gl.ARRAY_BUFFER, v_buffer.RendererID); dbg.GL_Check()
	defer gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BufferData(
		gl.ARRAY_BUFFER,
		len(data) * size_of(T),
		raw_data(data),
		gl.STATIC_DRAW,
	); dbg.GL_Check()

	return v_buffer
}

Delete :: proc(v_buffer: ^VertexBuffer) {
	gl.DeleteBuffers(1, &v_buffer.RendererID); dbg.GL_Check()
}

Bind :: proc(v_buffer: ^VertexBuffer) {
	gl.BindBuffer(gl.ARRAY_BUFFER, v_buffer.RendererID); dbg.GL_Check()
}

Unbind :: proc() {
	gl.BindBuffer(gl.ARRAY_BUFFER, 0); dbg.GL_Check()
}
