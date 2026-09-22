package VertexBufferLayout

import "core:fmt"
import gl "vendor:OpenGL"

@(private = "file")
VertexBufferElement :: struct {
	type:       int,
	count:      int,
	normalized: bool,
	size:       int,
}

VertexBufferLayout :: struct {
	Elements: [dynamic]VertexBufferElement,
	Stride:   int,
}

New :: proc() -> VertexBufferLayout {
	return VertexBufferLayout{}
}

Delete :: proc(layout: ^VertexBufferLayout) {
	delete(layout.Elements)
}

Push :: proc(layout: ^VertexBufferLayout, element_type: typeid, count: int, normalized: bool) {
	type: int
	size: int

	switch element_type {
	case i8:
		type = gl.BYTE
		size = count * 1
	case u8:
		type = gl.UNSIGNED_BYTE
		size = count * 1
	case i16:
		type = gl.SHORT
		size = count * 2
	case u16:
		type = gl.UNSIGNED_SHORT
		size = count * 2
	case i32:
		type = gl.INT
		size = count * 4
	case u32:
		type = gl.UNSIGNED_INT
		size = count * 4
	case f32:
		type = gl.FLOAT
		size = count * 4
	case f64:
		type = gl.DOUBLE
		size = count * 8
	case:
		panic(fmt.tprintf("VertexBufferLayout.Push: unsupported element type %v", element_type))
	}

	append(&layout.Elements, VertexBufferElement{type, count, normalized, size})
	layout.Stride += size
}
