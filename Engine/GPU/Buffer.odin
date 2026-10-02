package GPU

import gl "vendor:OpenGL"

Buffer_Target :: enum u32 {
	Vertex  = gl.ARRAY_BUFFER,
	Index   = gl.ELEMENT_ARRAY_BUFFER,
	Uniform = gl.UNIFORM_BUFFER,
}

Buffer_Usage :: enum u32 {
	Static  = gl.STATIC_DRAW,
	Dynamic = gl.DYNAMIC_DRAW,
}

Buffer :: struct {
	id:         u32,
	target:     Buffer_Target,
	size_bytes: int,
}

Buffer_Create :: proc(target: Buffer_Target, data: []$T, usage := Buffer_Usage.Static) -> Buffer {
	buffer := Buffer_Create_Empty(target, len(data) * size_of(T), usage)
	Buffer_Write(&buffer, data)
	return buffer
}

Buffer_Create_Empty :: proc(target: Buffer_Target, size_bytes: int, usage := Buffer_Usage.Static) -> Buffer {
	assert(size_bytes > 0, "Buffer_Create_Empty: size must be positive")
	buffer := Buffer{target = target, size_bytes = size_bytes}
	gl.GenBuffers(1, &buffer.id)
	gl.BindBuffer(gl.COPY_WRITE_BUFFER, buffer.id)
	gl.BufferData(gl.COPY_WRITE_BUFFER, size_bytes, nil, u32(usage))
	GL_Check()
	return buffer
}

// Uploads go through COPY_WRITE_BUFFER so that binding an index buffer never
// rewrites the element-array binding of whichever vertex array is current.
Buffer_Write :: proc(buffer: ^Buffer, data: []$T, offset_bytes := 0) {
	size_bytes := len(data) * size_of(T)
	assert(offset_bytes + size_bytes <= buffer.size_bytes, "Buffer_Write: out of range")
	gl.BindBuffer(gl.COPY_WRITE_BUFFER, buffer.id)
	gl.BufferSubData(gl.COPY_WRITE_BUFFER, offset_bytes, size_bytes, raw_data(data))
	GL_Check()
}

Buffer_Destroy :: proc(buffer: ^Buffer) {
	gl.DeleteBuffers(1, &buffer.id)
	buffer^ = {}
}
