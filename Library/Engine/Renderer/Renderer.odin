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
	if renderer.VertexArray != nil {va.Unbind(); vb.Unbind()}
	if renderer.IndexBuffer != nil do ib.Unbind()
	if renderer.Shader != nil do sd.Unbind()
	if renderer.VertexArray != nil do va.Delete(renderer.VertexArray)
	if renderer.IndexBuffer != nil do ib.Delete(renderer.IndexBuffer)
	if renderer.Shader != nil do sd.Delete(renderer.Shader)
}

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
