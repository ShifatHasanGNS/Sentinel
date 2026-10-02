package Procedural

import "core:fmt"
import la "core:math/linalg"

// Returns a description of the first thing wrong with a mesh, or "" if it is sound: indices in range, unit normals and
// tangents, tangents perpendicular to normals, handedness +-1, uv in [0, 1], and triangles wound counter-clockwise seen
// from the side their vertex normals face. Degenerate triangles (collapsed poles) have no orientation and are skipped.
Mesh_Find_Problem :: proc(mesh: Mesh) -> string {
	if len(mesh.vertices) == 0 do return "no vertices"
	if len(mesh.indices) == 0 || len(mesh.indices) % 3 != 0 do return fmt.tprintf("index count %d is not a positive multiple of 3", len(mesh.indices))
	for index in mesh.indices {
		if int(index) >= len(mesh.vertices) do return fmt.tprintf("index %d out of range", index)
	}
	for vertex, index in mesh.vertices {
		if abs(la.length(vertex.normal) - 1) >= 1e-4 do return fmt.tprintf("vertex %d normal is not unit length", index)
		if abs(la.length(vertex.tangent.xyz) - 1) >= 1e-4 do return fmt.tprintf("vertex %d tangent is not unit length", index)
		if abs(la.dot(vertex.normal, vertex.tangent.xyz)) >= 1e-3 do return fmt.tprintf("vertex %d tangent is not perpendicular to its normal", index)
		if abs(vertex.tangent.w) != 1 do return fmt.tprintf("vertex %d handedness is %f", index, vertex.tangent.w)
		if vertex.uv.x < 0 || vertex.uv.x > 1 || vertex.uv.y < 0 || vertex.uv.y > 1 do return fmt.tprintf("vertex %d uv %v is outside [0, 1]", index, vertex.uv)
	}
	for first := 0; first + 2 < len(mesh.indices); first += 3 {
		a, b, c := mesh.vertices[mesh.indices[first]], mesh.vertices[mesh.indices[first + 1]], mesh.vertices[mesh.indices[first + 2]]
		geometric := la.cross(b.position - a.position, c.position - a.position)
		if la.length(geometric) < 1e-5 do continue
		if la.dot(geometric, a.normal + b.normal + c.normal) <= 0 do return fmt.tprintf("triangle %d is wound against its normals", first / 3)
	}
	return ""
}
