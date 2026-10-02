package GPU

import gl "vendor:OpenGL"

Attribute_Type :: enum {
	Float32,
	Unsigned_Byte,
	Int32,
	Unsigned_Int32,
}

// divisor 0 advances per vertex, 1 per instance (a mat4 instance attribute is four 4-component entries).
Vertex_Attribute :: struct {
	components: i32,
	type:       Attribute_Type,
	normalized: bool,
	divisor:    u32,
}

Vertex_Stream :: struct {
	buffer:     ^Buffer,
	attributes: []Vertex_Attribute,
}

Vertex_Array :: struct {
	id:          u32,
	index_count: i32,
}

Vertex_Array_Create :: proc(streams: []Vertex_Stream, index_buffer: ^Buffer, index_count: i32) -> Vertex_Array {
	assert(len(streams) > 0, "Vertex_Array_Create: no vertex streams")
	array := Vertex_Array{index_count = index_count}
	gl.GenVertexArrays(1, &array.id)
	gl.BindVertexArray(array.id)
	location: u32
	for stream in streams {
		gl.BindBuffer(gl.ARRAY_BUFFER, stream.buffer.id)
		location = attach_stream(stream, location)
	}
	if index_buffer != nil do gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, index_buffer.id)
	gl.BindVertexArray(0)
	GL_Check()
	return array
}

Vertex_Array_Draw :: proc(array: ^Vertex_Array, instance_count: i32 = 1) {
	gl.BindVertexArray(array.id)
	gl.DrawElementsInstanced(gl.TRIANGLES, array.index_count, gl.UNSIGNED_INT, nil, instance_count)
	GL_Check()
}

Vertex_Array_Destroy :: proc(array: ^Vertex_Array) {
	gl.DeleteVertexArrays(1, &array.id)
	array^ = {}
}

@(private = "file")
attach_stream :: proc(stream: Vertex_Stream, first_location: u32) -> (next_location: u32) {
	stride: i32
	for attribute in stream.attributes do stride += attribute.components * attribute_size_bytes(attribute.type)
	offset: uintptr
	location := first_location
	for attribute in stream.attributes {
		gl.EnableVertexAttribArray(location)
		point_attribute(location, attribute, stride, offset)
		gl.VertexAttribDivisor(location, attribute.divisor)
		offset += uintptr(attribute.components * attribute_size_bytes(attribute.type))
		location += 1
	}
	return location
}

@(private = "file")
point_attribute :: proc(location: u32, attribute: Vertex_Attribute, stride: i32, offset: uintptr) {
	switch attribute.type {
	case .Float32:
		gl.VertexAttribPointer(location, attribute.components, gl.FLOAT, attribute.normalized, stride, offset)
	case .Unsigned_Byte:
		gl.VertexAttribPointer(location, attribute.components, gl.UNSIGNED_BYTE, attribute.normalized, stride, offset)
	case .Int32:
		gl.VertexAttribIPointer(location, attribute.components, gl.INT, stride, offset)
	case .Unsigned_Int32:
		gl.VertexAttribIPointer(location, attribute.components, gl.UNSIGNED_INT, stride, offset)
	}
}

@(private = "file")
attribute_size_bytes :: proc(type: Attribute_Type) -> i32 {
	switch type {
	case .Unsigned_Byte: return 1
	case .Float32, .Int32, .Unsigned_Int32: return 4
	}
	unreachable()
}
