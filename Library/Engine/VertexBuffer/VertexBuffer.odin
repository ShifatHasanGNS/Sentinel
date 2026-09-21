// Package VertexBuffer — Library/Engine sub-package.
// Theme-agnostic: must never know about SENTINEL-specific scene/object code.
// Carried over from the earlier learning-project Engine.zip skeleton
// (Requirements.md §7, CLAUDE.md §13.2). Audited: no core:math/linalg usage,
// looks reusable as-is. Re-confirm during Session 1b's Engine integration pass.

package VertexBuffer

import dbg "../Debugger"
import gl "vendor:OpenGL"

VertexBuffer :: struct {
	RendererID: u32,
}

// Takes any typed slice (`[]f32`, `[]Vertex`, ...) and uploads its raw
// bytes to a new GL_ARRAY_BUFFER. Computing raw_data/size_of here, where
// the element type T is still known, keeps callers from having to (and
// getting wrong) recompute byte sizes themselves.
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
