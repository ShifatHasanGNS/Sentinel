// Package VertexArray — Library/Engine sub-package.
// Theme-agnostic: must never know about SENTINEL-specific scene/object code.
// Carried over from the earlier learning-project Engine.zip skeleton
// (Requirements.md §7, CLAUDE.md §13.2). Audited: no core:math/linalg usage,
// looks reusable as-is. Re-confirm during Session 1b's Engine integration pass.

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

// Binds v_array, describes v_buffer's layout to it via VertexAttribPointer
// calls, then unbinds everything again so this call doesn't leave global GL
// state (which VAO/VBO is bound) hanging around for whatever code runs next.
AddBuffer :: proc(
	v_array: ^VertexArray,
	v_buffer: ^vb.VertexBuffer,
	layout: ^vbl.VertexBufferLayout,
) {
	Bind(v_array)
	vb.Bind(v_buffer)
	defer Unbind() // unbind VAO last, so it's still active while VBO unbinds
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

		offset += element.size // Next Offset
	}
}
