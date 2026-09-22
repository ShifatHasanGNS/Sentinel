package VertexArray

import dbg "../Debugger"
import vb "../VertexBuffer"
import vbl "../VertexBufferLayout"
import gl "vendor:OpenGL"

VertexArray :: struct {
	RendererID: u32,
}

New :: proc() -> VertexArray {
	v_array := VertexArray{}
	gl.GenVertexArrays(1, &v_array.RendererID); dbg.GL_Check()
	return v_array
}

Delete :: proc(v_array: ^VertexArray) {
	gl.DeleteVertexArrays(1, &v_array.RendererID); dbg.GL_Check()
}

Bind :: proc(v_array: ^VertexArray) {
	gl.BindVertexArray(v_array.RendererID); dbg.GL_Check()
}

Unbind :: proc() {
	gl.BindVertexArray(0); dbg.GL_Check()
}

AddBuffer :: proc(
	v_array: ^VertexArray,
	v_buffer: ^vb.VertexBuffer,
	layout: ^vbl.VertexBufferLayout,
) {
	Bind(v_array)
	vb.Bind(v_buffer)
	defer Unbind()
	defer vb.Unbind()

	offset := 0

	for element, i in layout.Elements {
		gl.VertexAttribPointer(
			u32(i),
			i32(element.count),
			u32(element.type),
			element.normalized,
			i32(layout.Stride),
			uintptr(offset),
		); dbg.GL_Check()

		gl.EnableVertexAttribArray(u32(i)); dbg.GL_Check()

		offset += element.size
	}
}
