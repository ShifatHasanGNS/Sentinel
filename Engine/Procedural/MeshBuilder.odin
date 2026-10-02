package Procedural

import "core:math/linalg"

// Appends source into destination under transform. Normals use the inverse transpose of the upper 3x3, which keeps them
// perpendicular to the surface under non-uniform scale. A negative determinant (mirroring) reverses triangle winding and
// the tangent handedness so the surface still faces outward.
Mesh_Append :: proc(destination: ^Mesh, source: Mesh, transform: matrix[4, 4]f32) {
	linear := matrix[3, 3]f32{
		transform[0, 0], transform[0, 1], transform[0, 2],
		transform[1, 0], transform[1, 1], transform[1, 2],
		transform[2, 0], transform[2, 1], transform[2, 2],
	}
	normal_matrix := linalg.transpose(linalg.inverse(linear))
	handedness_sign: f32 = -1 if linalg.determinant(linear) < 0 else 1
	first := u32(len(destination.vertices))
	for vertex in source.vertices {
		position := transform * [4]f32{vertex.position.x, vertex.position.y, vertex.position.z, 1}
		tangent := linalg.normalize(linear * vertex.tangent.xyz)
		append(&destination.vertices, Vertex{
			position = position.xyz,
			normal = linalg.normalize(normal_matrix * vertex.normal),
			tangent = {tangent.x, tangent.y, tangent.z, vertex.tangent.w * handedness_sign},
			uv = vertex.uv,
		})
	}
	for corner := 0; corner + 2 < len(source.indices); corner += 3 {
		a, b, c := source.indices[corner] + first, source.indices[corner + 1] + first, source.indices[corner + 2] + first
		if handedness_sign < 0 {
			append(&destination.indices, a, c, b)
		} else {
			append(&destination.indices, a, b, c)
		}
	}
}
