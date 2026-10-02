package Procedural

import "core:math"
import "core:math/linalg"
import "core:testing"

@(test)
test_append_adds_counts_and_places_geometry_by_the_transform :: proc(t: ^testing.T) {
	combined := Box_Create({1, 1, 1})
	defer Mesh_Destroy(&combined)
	part := Box_Create({2, 2, 2})
	defer Mesh_Destroy(&part)
	transform := linalg.matrix4_translate_f32({10, 0, 0}) * linalg.matrix4_scale_f32({1, 2, 1})
	Mesh_Append(&combined, part, transform)
	testing.expect_value(t, len(combined.vertices), 48)
	testing.expect_value(t, len(combined.indices), 72)
	for index in combined.indices do testing.expect(t, int(index) < len(combined.vertices))
	lowest, highest := Mesh_Bounds(combined)
	testing.expect_value(t, lowest, [3]f32{-0.5, -2, -1})
	testing.expect_value(t, highest, [3]f32{11, 2, 1})
	appended_triangle_uses_appended_vertices := true
	for index in combined.indices[36:] do if index < 24 do appended_triangle_uses_appended_vertices = false
	testing.expect(t, appended_triangle_uses_appended_vertices)
}

// Under non-uniform scale a normal must follow the inverse transpose, not the matrix itself: for the ellipsoid x^2 + (y/3)^2 + z^2 = 1 the true normal is along (x, y/9, z).
@(test)
test_normals_stay_perpendicular_under_non_uniform_scale :: proc(t: ^testing.T) {
	combined: Mesh
	defer Mesh_Destroy(&combined)
	sphere := Sphere_Create(1, 24, 12)
	defer Mesh_Destroy(&sphere)
	Mesh_Append(&combined, sphere, linalg.matrix4_scale_f32({1, 3, 1}))
	for vertex in combined.vertices {
		expected := linalg.normalize([3]f32{vertex.position.x, vertex.position.y / 9, vertex.position.z})
		testing.expect(t, linalg.length(vertex.normal - expected) < 1e-4)
		testing.expect(t, abs(linalg.length(vertex.normal) - 1) < 1e-4)
		testing.expect(t, abs(linalg.dot(vertex.normal, vertex.tangent.xyz)) < 1e-4)
	}
}

@(test)
test_mirroring_keeps_winding_outward_and_bitangent_consistent :: proc(t: ^testing.T) {
	source := Cylinder_Create(1, 2, 24)
	defer Mesh_Destroy(&source)
	mirror := linalg.matrix4_scale_f32({-1, 1, 1})
	combined: Mesh
	defer Mesh_Destroy(&combined)
	Mesh_Append(&combined, source, mirror)
	expect_winding_agrees_with_normals(t, combined, "mirrored cylinder")
	testing.expect(t, signed_volume(combined) > 0)
	for vertex, index in source.vertices {
		original_bitangent := linalg.cross(vertex.normal, vertex.tangent.xyz) * vertex.tangent.w
		expected_bitangent := linalg.normalize([3]f32{-original_bitangent.x, original_bitangent.y, original_bitangent.z})
		mirrored := combined.vertices[index]
		actual_bitangent := linalg.cross(mirrored.normal, mirrored.tangent.xyz) * mirrored.tangent.w
		testing.expect(t, linalg.length(actual_bitangent - expected_bitangent) < 1e-4)
	}
}

@(test)
test_rotation_keeps_vertices_on_the_same_sphere :: proc(t: ^testing.T) {
	combined: Mesh
	defer Mesh_Destroy(&combined)
	sphere := Sphere_Create(2, 12, 6)
	defer Mesh_Destroy(&sphere)
	Mesh_Append(&combined, sphere, linalg.matrix4_rotate_f32(math.PI / 3, {1, 1, 0}))
	for vertex in combined.vertices do testing.expect(t, abs(linalg.length(vertex.position) - 2) < 1e-4)
}
