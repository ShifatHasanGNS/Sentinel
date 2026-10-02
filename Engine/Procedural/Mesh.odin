package Procedural

// tangent.w is the bitangent handedness: bitangent = cross(normal, tangent.xyz) * tangent.w.
Vertex :: struct {
	position: [3]f32,
	normal:   [3]f32,
	tangent:  [4]f32,
	uv:       [2]f32,
}

Mesh :: struct {
	vertices: [dynamic]Vertex,
	indices:  [dynamic]u32,
}

Mesh_Destroy :: proc(mesh: ^Mesh) {
	delete(mesh.vertices)
	delete(mesh.indices)
	mesh^ = {}
}

Mesh_Bounds :: proc(mesh: Mesh) -> (lowest, highest: [3]f32) {
	assert(len(mesh.vertices) > 0, "Mesh_Bounds: empty mesh")
	lowest = mesh.vertices[0].position
	highest = lowest
	for vertex in mesh.vertices {
		lowest = {min(lowest.x, vertex.position.x), min(lowest.y, vertex.position.y), min(lowest.z, vertex.position.z)}
		highest = {max(highest.x, vertex.position.x), max(highest.y, vertex.position.y), max(highest.z, vertex.position.z)}
	}
	return
}
