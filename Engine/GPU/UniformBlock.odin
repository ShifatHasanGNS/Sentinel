package GPU

import gl "vendor:OpenGL"

// A uniform block shared by several shaders. The CPU struct must follow std140 layout:
// every vec3 occupies 16 bytes and mat4 columns are 16-byte aligned, so pad explicitly.
Uniform_Block :: struct {
	buffer:  Buffer,
	binding: u32,
}

Uniform_Block_Create :: proc(binding: u32, size_bytes: int) -> Uniform_Block {
	block := Uniform_Block{buffer = Buffer_Create_Empty(.Uniform, size_bytes, .Dynamic), binding = binding}
	gl.BindBufferBase(gl.UNIFORM_BUFFER, binding, block.buffer.id)
	GL_Check()
	return block
}

Uniform_Block_Write :: proc(block: ^Uniform_Block, data: ^$T) {
	assert(size_of(T) <= block.buffer.size_bytes, "Uniform_Block_Write: data larger than block")
	Buffer_Write(&block.buffer, ([^]T)(data)[:1])
}

Uniform_Block_Destroy :: proc(block: ^Uniform_Block) {
	Buffer_Destroy(&block.buffer)
}
