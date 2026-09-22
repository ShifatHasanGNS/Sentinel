// Geometry_test.odin — winding/normal correctness checks.
package Geometry

import "core:math"
import la "core:math/linalg"
import "core:testing"

EPSILON :: 1e-4

@(test)
test_cube_triangle_normals_match_winding :: proc(t: ^testing.T) {
	mesh := Cube(2, 3, 4)
	defer Destroy(&mesh)
	expect_winding_matches_normals(t, mesh)
}

@(test)
test_cube_normals_point_outward :: proc(t: ^testing.T) {
	mesh := Cube(2, 3, 4)
	defer Destroy(&mesh)
	expect_normals_point_outward(t, mesh, la.Vector3f32{0, 0, 0})
}

@(test)
test_cube_vertex_and_triangle_counts :: proc(t: ^testing.T) {
	mesh := Cube(2, 3, 4)
	defer Destroy(&mesh)
	// 6 faces x 4 duplicated corners = 24 vertices; 36 indices.
	testing.expectf(t, len(mesh.Vertices) == 24, "expected 24 vertices, got %d", len(mesh.Vertices))
	testing.expectf(t, len(mesh.Indices) == 36, "expected 36 indices, got %d", len(mesh.Indices))
}

@(test)
test_cube_face_extents_match_dimensions :: proc(t: ^testing.T) {
	mesh := Cube(2, 4, 6)
	defer Destroy(&mesh)

	min_extent, max_extent := la.Vector3f32{0, 0, 0}, la.Vector3f32{0, 0, 0}
	for vertex, i in mesh.Vertices {
		if i == 0 {
			min_extent, max_extent = vertex.Position, vertex.Position
			continue
		}
		for axis in 0 ..< 3 {
			min_extent[axis] = min(min_extent[axis], vertex.Position[axis])
			max_extent[axis] = max(max_extent[axis], vertex.Position[axis])
		}
	}

	expect_vector3_near(t, min_extent, la.Vector3f32{-1, -2, -3})
	expect_vector3_near(t, max_extent, la.Vector3f32{1, 2, 3})
}

@(test)
test_tetrahedron_triangle_normals_match_winding :: proc(t: ^testing.T) {
	mesh := Tetrahedron(2)
	defer Destroy(&mesh)
	expect_winding_matches_normals(t, mesh)
}

@(test)
test_tetrahedron_normals_point_outward :: proc(t: ^testing.T) {
	mesh := Tetrahedron(2)
	defer Destroy(&mesh)
	expect_normals_point_outward(t, mesh, la.Vector3f32{0, 0, 0})
}

@(test)
test_tetrahedron_vertex_and_triangle_counts :: proc(t: ^testing.T) {
	mesh := Tetrahedron(2)
	defer Destroy(&mesh)
	testing.expectf(t, len(mesh.Vertices) == 12, "expected 12 vertices, got %d", len(mesh.Vertices))
	testing.expectf(t, len(mesh.Indices) == 12, "expected 12 indices, got %d", len(mesh.Indices))
}

@(test)
test_plane_triangle_normals_match_winding :: proc(t: ^testing.T) {
	mesh := Plane(2, 3)
	defer Destroy(&mesh)
	expect_winding_matches_normals(t, mesh)
}

@(test)
test_plane_faces_positive_z :: proc(t: ^testing.T) {
	mesh := Plane(2, 3)
	defer Destroy(&mesh)

	for vertex in mesh.Vertices {
		expect_vector3_near(t, vertex.Normal, la.Vector3f32{0, 0, 1})
	}
}

@(test)
test_plane_vertex_and_triangle_counts :: proc(t: ^testing.T) {
	mesh := Plane(2, 3)
	defer Destroy(&mesh)
	testing.expectf(t, len(mesh.Vertices) == 4, "expected 4 vertices, got %d", len(mesh.Vertices))
	testing.expectf(t, len(mesh.Indices) == 6, "expected 6 indices, got %d", len(mesh.Indices))
}

@(test)
test_append_mesh_with_identity_preserves_positions_and_normals :: proc(t: ^testing.T) {
	src := Cube(2, 2, 2)
	defer Destroy(&src)

	dst := Empty_Mesh()
	defer Destroy(&dst)
	Append_Mesh(&dst, src, la.MATRIX4F32_IDENTITY)

	testing.expectf(t, len(dst.Vertices) == len(src.Vertices), "expected %d vertices, got %d", len(src.Vertices), len(dst.Vertices))
	for vertex, i in dst.Vertices {
		expect_vector3_near(t, vertex.Position, src.Vertices[i].Position)
		expect_vector3_near(t, vertex.Normal, src.Vertices[i].Normal)
	}
}

@(test)
test_append_mesh_offsets_indices_for_second_instance :: proc(t: ^testing.T) {
	src := Tetrahedron(1)
	defer Destroy(&src)

	dst := Empty_Mesh()
	defer Destroy(&dst)
	Append_Mesh(&dst, src, la.MATRIX4F32_IDENTITY)
	Append_Mesh(&dst, src, la.matrix4_translate(la.Vector3f32{5, 0, 0}))

	testing.expectf(t, len(dst.Vertices) == 2 * len(src.Vertices), "expected %d vertices, got %d", 2 * len(src.Vertices), len(dst.Vertices))
	testing.expectf(t, len(dst.Indices) == 2 * len(src.Indices), "expected %d indices, got %d", 2 * len(src.Indices), len(dst.Indices))

	second_half_start := len(src.Indices)
	for index in dst.Indices[second_half_start:] {
		testing.expectf(t, int(index) >= len(src.Vertices), "expected second instance's indices to be offset, got index %d", index)
	}
}

@(test)
test_append_mesh_translates_positions :: proc(t: ^testing.T) {
	src := Cube(2, 2, 2)
	defer Destroy(&src)

	dst := Empty_Mesh()
	defer Destroy(&dst)
	offset := la.Vector3f32{10, -5, 3}
	Append_Mesh(&dst, src, la.matrix4_translate(offset))

	for vertex, i in dst.Vertices {
		expect_vector3_near(t, vertex.Position, src.Vertices[i].Position + offset)
	}
}

@(test)
test_append_mesh_keeps_normals_perpendicular_under_non_uniform_scale :: proc(t: ^testing.T) {
	src := Plane(2, 2)
	defer Destroy(&src)

	dst := Empty_Mesh()
	defer Destroy(&dst)
	Append_Mesh(&dst, src, la.matrix4_scale(la.Vector3f32{1, 5, 1}))

	for vertex in dst.Vertices {
		expect_vector3_near(t, vertex.Normal, la.Vector3f32{0, 0, 1})
	}
}

@(test)
test_append_mesh_rotates_normals :: proc(t: ^testing.T) {
	src := Plane(2, 2)
	defer Destroy(&src)

	dst := Empty_Mesh()
	defer Destroy(&dst)
	Append_Mesh(&dst, src, la.matrix4_rotate(math.to_radians(f32(90)), la.Vector3f32{0, 1, 0}))

	for vertex in dst.Vertices {
		expect_vector3_near(t, vertex.Normal, la.Vector3f32{1, 0, 0})
	}
}

@(private = "file")
expect_winding_matches_normals :: proc(t: ^testing.T, mesh: Mesh, loc := #caller_location) {
	for i := 0; i < len(mesh.Indices); i += 3 {
		i0, i1, i2 := mesh.Indices[i], mesh.Indices[i + 1], mesh.Indices[i + 2]
		v0, v1, v2 := mesh.Vertices[i0], mesh.Vertices[i1], mesh.Vertices[i2]

		geometric_normal := la.normalize(la.cross(v1.Position - v0.Position, v2.Position - v0.Position))

		expect_vector3_near(t, v0.Normal, geometric_normal, loc)
		expect_vector3_near(t, v1.Normal, geometric_normal, loc)
		expect_vector3_near(t, v2.Normal, geometric_normal, loc)
	}
}

@(private = "file")
expect_normals_point_outward :: proc(t: ^testing.T, mesh: Mesh, center: la.Vector3f32, loc := #caller_location) {
	for i := 0; i < len(mesh.Indices); i += 3 {
		i0, i1, i2 := mesh.Indices[i], mesh.Indices[i + 1], mesh.Indices[i + 2]
		v0, v1, v2 := mesh.Vertices[i0], mesh.Vertices[i1], mesh.Vertices[i2]

		triangle_centroid := (v0.Position + v1.Position + v2.Position) / 3
		outward_direction := triangle_centroid - center

		testing.expectf(
			t,
			la.dot(v0.Normal, outward_direction) > 0,
			"triangle at indices [%d %d %d] has a normal (%v) that does not point away from centre %v (triangle centroid %v)",
			i0, i1, i2, v0.Normal, center, triangle_centroid,
			loc = loc,
		)
	}
}

@(private = "file")
expect_vector3_near :: proc(t: ^testing.T, got, want: la.Vector3f32, loc := #caller_location) {
	for i in 0 ..< 3 {
		diff := math.abs(got[i] - want[i])
		testing.expectf(t, diff <= EPSILON, "vector mismatch at component %d: got %v, want %v (diff %v)", i, got, want, diff, loc = loc)
	}
}
