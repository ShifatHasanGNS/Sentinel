// Package Renderer — Library/Engine sub-package.
// Theme-agnostic: must never know about SENTINEL-specific scene/object code.
// Carried over from the earlier learning-project Engine.zip skeleton
// (Requirements.md §7, CLAUDE.md §13.2). Audited: no core:math/linalg usage.
//
// KNOWN LIMITATION (do not fix yet — see CLAUDE.md §13.2, Plan.md §11.2):
// Draw() currently binds exactly one VertexArray + IndexBuffer + Shader
// triple. That's enough for the initial static scene (roadmap step 3), but
// will need to grow once per-object uniforms (model matrix, material, which
// lights affect it), the flat/Gouraud/Phong toggle, and the small ray-traced
// reflection pass (Requirements.md/CLAUDE.md §6.2) are in scope. Whether
// that's done by extending Renderer itself or driving multiple Renderer
// instances from SENTINEL-specific code is an implementation decision for
// the session that actually needs it — don't pre-extend this now.

package Renderer

import dbg "../Debugger"
import ib "../IndexBuffer"
import sd "../Shader"
import va "../VertexArray"
import vb "../VertexBuffer"
import gl "vendor:OpenGL"

Renderer :: struct {
	VertexArray: ^va.VertexArray,
	IndexBuffer: ^ib.IndexBuffer,
	Shader:      ^sd.Shader,
}

New :: proc(v_array: ^va.VertexArray, i_buffer: ^ib.IndexBuffer, shader: ^sd.Shader) -> Renderer {
	return Renderer{VertexArray = v_array, IndexBuffer = i_buffer, Shader = shader}
}

Renew :: proc(
	renderer: ^Renderer,
	v_array: ^va.VertexArray,
	i_buffer: ^ib.IndexBuffer,
	shader: ^sd.Shader,
) {
	renderer.VertexArray = v_array
	renderer.IndexBuffer = i_buffer
	renderer.Shader = shader
}

Delete :: proc(renderer: ^Renderer) {
	// Unbind
	if renderer.VertexArray != nil {va.Unbind(); vb.Unbind()}
	if renderer.IndexBuffer != nil do ib.Unbind()
	if renderer.Shader != nil do sd.Unbind()
	// Delete
	if renderer.VertexArray != nil do va.Delete(renderer.VertexArray)
	if renderer.IndexBuffer != nil do ib.Delete(renderer.IndexBuffer)
	if renderer.Shader != nil do sd.Delete(renderer.Shader)
}

// All three are required to issue a draw call - previously a missing
// IndexBuffer would silently no-op the bind and then nil-deref inside
// ib.GetCount a few lines later. Asserting up front turns that into a
// clear error at the actual mistake instead of a crash one step removed
// from it.
Draw :: proc(renderer: ^Renderer) {
	assert(renderer.VertexArray != nil, "Renderer.Draw: no VertexArray set")
	assert(renderer.IndexBuffer != nil, "Renderer.Draw: no IndexBuffer set")
	assert(renderer.Shader != nil, "Renderer.Draw: no Shader set")

	va.Bind(renderer.VertexArray)
	ib.Bind(renderer.IndexBuffer)
	sd.Bind(renderer.Shader)

	gl.DrawElements(
		gl.TRIANGLES,
		i32(ib.GetCount(renderer.IndexBuffer)),
		gl.UNSIGNED_INT,
		nil,
	); dbg.GL_Check()
}

Clear :: proc() {
	gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT); dbg.GL_Check()
}
