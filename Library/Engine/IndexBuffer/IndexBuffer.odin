package IndexBuffer

import dbg "../Debugger"
import gl "vendor:OpenGL"

IndexBuffer :: struct {
	RendererID: u32,
	Count:      int,
}

GetCount :: proc(i_buffer: ^IndexBuffer) -> int {
	return i_buffer.Count
}

New :: proc(data: []u32) -> IndexBuffer {
	i_buffer := IndexBuffer {
		Count = len(data),
	}

	gl.GenBuffers(1, &i_buffer.RendererID); dbg.GL_Check()
	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, i_buffer.RendererID); dbg.GL_Check()
	defer gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0)
	gl.BufferData(
		gl.ELEMENT_ARRAY_BUFFER,
		len(data) * size_of(u32),
		raw_data(data),
		gl.STATIC_DRAW,
	); dbg.GL_Check()

	return i_buffer
}

Delete :: proc(i_buffer: ^IndexBuffer) {
	gl.DeleteBuffers(1, &i_buffer.RendererID); dbg.GL_Check()
}

Bind :: proc(i_buffer: ^IndexBuffer) {
	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, i_buffer.RendererID); dbg.GL_Check()
}

Unbind :: proc() {
	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0); dbg.GL_Check()
}
