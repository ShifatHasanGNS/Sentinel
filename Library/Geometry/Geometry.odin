// Package Geometry — procedural primitive/mesh generation.
package Geometry

import la "core:math/linalg"

import ib "../Engine/IndexBuffer"
import rd "../Engine/Renderer"
import sd "../Engine/Shader"
import va "../Engine/VertexArray"
import vb "../Engine/VertexBuffer"
import vbl "../Engine/VertexBufferLayout"

Vertex :: struct {
	Position: la.Vector3f32,
	Normal:   la.Vector3f32,
}

Mesh :: struct {
	Vertices: [dynamic]Vertex,
	Indices:  [dynamic]u32,

	vertex_buffer: vb.VertexBuffer,
	index_buffer:  ib.IndexBuffer,
	vertex_array:  va.VertexArray,
	layout:        vbl.VertexBufferLayout,
	uploaded:      bool,
}

Empty_Mesh :: proc() -> Mesh {
	return Mesh{}
}

// Only 3 direct generators allowed: Cube, Tetrahedron, Plane.

Cube :: proc(width, height, depth: f32) -> Mesh {
	mesh := Empty_Mesh()
	half := la.Vector3f32{width, height, depth} * 0.5

	// Traversal order only, not literal geometry — append_quad auto-orients.
	corner_signs := [4][2]f32{{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}

	for axis in 0 ..< 3 {
		u := (axis + 1) % 3
		v := (axis + 2) % 3

		for sign_bit in 0 ..< 2 {
			sign: f32 = -1 if sign_bit == 0 else 1

			corner: [4]la.Vector3f32
			for k in 0 ..< 4 {
				p: la.Vector3f32
				p[axis] = sign * half[axis]
				p[u] = corner_signs[k][0] * half[u]
				p[v] = corner_signs[k][1] * half[v]
				corner[k] = p
			}

			append_quad(&mesh, corner[0], corner[1], corner[2], corner[3], la.Vector3f32{0, 0, 0})
		}
	}

	return mesh
}

Tetrahedron :: proc(size: f32) -> Mesh {
	mesh := Empty_Mesh()
	s := size * 0.5

	// 4 alternating corners of a cube.
	corner := [4]la.Vector3f32 {
		la.Vector3f32{1, 1, 1} * s,
		la.Vector3f32{1, -1, -1} * s,
		la.Vector3f32{-1, 1, -1} * s,
		la.Vector3f32{-1, -1, 1} * s,
	}

	// Row i = the face not touching corner[i]; order within a row is arbitrary.
	face := [4][3]int{{1, 2, 3}, {0, 2, 3}, {0, 1, 3}, {0, 1, 2}}

	for f in face {
		append_triangle(&mesh, corner[f[0]], corner[f[1]], corner[f[2]], la.Vector3f32{0, 0, 0})
	}

	return mesh
}

Plane :: proc(width, height: f32) -> Mesh {
	mesh := Empty_Mesh()
	half_width := width * 0.5
	half_height := height * 0.5
	normal := la.Vector3f32{0, 0, 1}

	corner := [4]la.Vector3f32 {
		{-half_width, -half_height, 0},
		{half_width, -half_height, 0},
		{half_width, half_height, 0},
		{-half_width, half_height, 0},
	}

	for c in corner {
		append(&mesh.Vertices, Vertex{Position = c, Normal = normal})
	}
	append(&mesh.Indices, u32(0), 1, 2, 0, 2, 3)

	return mesh
}

// Auto-orients so the stored normal always faces away from inward_reference.
@(private = "file")
append_triangle :: proc(mesh: ^Mesh, a, b, c: la.Vector3f32, inward_reference: la.Vector3f32) {
	normal := la.normalize(la.cross(b - a, c - a))
	centroid := (a + b + c) / 3

	v0, v1, v2 := a, b, c
	if la.dot(normal, centroid - inward_reference) < 0 {
		v1, v2 = c, b
		normal = -normal
	}

	base_index := u32(len(mesh.Vertices))
	append(&mesh.Vertices, Vertex{Position = v0, Normal = normal}, Vertex{Position = v1, Normal = normal}, Vertex{Position = v2, Normal = normal})
	append(&mesh.Indices, base_index + 0, base_index + 1, base_index + 2)
}

@(private = "file")
append_quad :: proc(mesh: ^Mesh, a, b, c, d: la.Vector3f32, inward_reference: la.Vector3f32) {
	normal := la.normalize(la.cross(b - a, c - a))
	centroid := (a + b + c + d) * 0.25

	base_index := u32(len(mesh.Vertices))
	append(&mesh.Vertices, Vertex{Position = a, Normal = normal}, Vertex{Position = b, Normal = normal}, Vertex{Position = c, Normal = normal}, Vertex{Position = d, Normal = normal})

	if la.dot(normal, centroid - inward_reference) < 0 {
		mesh.Vertices[base_index + 0].Normal = -normal
		mesh.Vertices[base_index + 1].Normal = -normal
		mesh.Vertices[base_index + 2].Normal = -normal
		mesh.Vertices[base_index + 3].Normal = -normal
		append(&mesh.Indices, base_index + 0, base_index + 2, base_index + 1)
		append(&mesh.Indices, base_index + 0, base_index + 3, base_index + 2)
	} else {
		append(&mesh.Indices, base_index + 0, base_index + 1, base_index + 2)
		append(&mesh.Indices, base_index + 0, base_index + 2, base_index + 3)
	}
}

// The only way composite shapes are built: copy src into dst under transform.
Append_Mesh :: proc(dst: ^Mesh, src: Mesh, transform: la.Matrix4f32) {
	normal_matrix := la.matrix3_from_matrix4(la.matrix4_inverse_transpose(transform))
	base_index := u32(len(dst.Vertices))

	for vertex in src.Vertices {
		world_position4 := la.mul(transform, la.Vector4f32{vertex.Position.x, vertex.Position.y, vertex.Position.z, 1})
		world_position := la.Vector3f32{world_position4.x, world_position4.y, world_position4.z}
		world_normal := la.normalize(la.mul(normal_matrix, vertex.Normal))
		append(&dst.Vertices, Vertex{Position = world_position, Normal = world_normal})
	}

	for index in src.Indices {
		append(&dst.Indices, base_index + index)
	}
}

// Formula-based radial normal, not vertex-welding (call before Append_Mesh).
Smooth_Cylinder_Normals :: proc(mesh: ^Mesh, axis_point: la.Vector3f32, axis_direction: la.Vector3f32) {
	axis := la.normalize(axis_direction)
	for &vertex in mesh.Vertices {
		offset := vertex.Position - axis_point
		radial := offset - la.dot(offset, axis) * axis
		if la.length(radial) > 1e-5 {
			vertex.Normal = la.normalize(radial)
		}
	}
}

Upload :: proc(mesh: ^Mesh) {
	mesh.vertex_buffer = vb.New(mesh.Vertices[:])
	mesh.index_buffer = ib.New(mesh.Indices[:])

	mesh.layout = vbl.New()
	vbl.Push(&mesh.layout, f32, 3, false)
	vbl.Push(&mesh.layout, f32, 3, false)

	mesh.vertex_array = va.New()
	va.AddBuffer(&mesh.vertex_array, &mesh.vertex_buffer, &mesh.layout)

	mesh.uploaded = true
}

Draw :: proc(mesh: ^Mesh, shader: ^sd.Shader) {
	renderer := rd.New(&mesh.vertex_array, &mesh.index_buffer, shader)
	rd.Draw(&renderer)
}

Destroy :: proc(mesh: ^Mesh) {
	delete(mesh.Vertices)
	delete(mesh.Indices)

	// Guards against calling GL cleanup when no GL context ever loaded.
	if mesh.uploaded {
		vb.Delete(&mesh.vertex_buffer)
		vbl.Delete(&mesh.layout)
		va.Delete(&mesh.vertex_array)
		ib.Delete(&mesh.index_buffer)
	}
}
