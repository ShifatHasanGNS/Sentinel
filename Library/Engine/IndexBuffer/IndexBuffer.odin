// Package IndexBuffer — Library/Engine sub-package.
// Theme-agnostic: must never know about SENTINEL-specific scene/object code.
// Carried over from the earlier learning-project Engine.zip skeleton
// (Requirements.md §7, CLAUDE.md §13.2). Audited: no core:math/linalg usage,
// looks reusable as-is. Re-confirm during Session 1b's Engine integration pass.

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

// Takes the index data directly as `[]u32` - Count and the byte size
// passed to GL are both derived from len(data), so there's no separate
// count/size argument for a caller to get out of sync with the slice.
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
