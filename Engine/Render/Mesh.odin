package Render

import "../GPU"
import "../Procedural"

Mesh :: struct {
	vertex_buffer: GPU.Buffer,
	index_buffer:  GPU.Buffer,
	vertex_array:  GPU.Vertex_Array,
}

// Matches Procedural.Vertex: position, normal, tangent (xyz + handedness), uv.
Mesh_Upload :: proc(source: Procedural.Mesh) -> (mesh: Mesh) {
	mesh.vertex_buffer = GPU.Buffer_Create(.Vertex, source.vertices[:])
	mesh.index_buffer = GPU.Buffer_Create(.Index, source.indices[:])
	attributes := [4]GPU.Vertex_Attribute{{3, .Float32, false, 0}, {3, .Float32, false, 0}, {4, .Float32, false, 0}, {2, .Float32, false, 0}}
	streams := [1]GPU.Vertex_Stream{{&mesh.vertex_buffer, attributes[:]}}
	mesh.vertex_array = GPU.Vertex_Array_Create(streams[:], &mesh.index_buffer, i32(len(source.indices)))
	return mesh
}

Mesh_Draw :: proc(mesh: ^Mesh) {
	GPU.Vertex_Array_Draw(&mesh.vertex_array)
}

Mesh_Destroy :: proc(mesh: ^Mesh) {
	GPU.Vertex_Array_Destroy(&mesh.vertex_array)
	GPU.Buffer_Destroy(&mesh.vertex_buffer)
	GPU.Buffer_Destroy(&mesh.index_buffer)
}
