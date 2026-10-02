package Procedural

import "core:math"
import "core:math/linalg"
import "core:testing"

// Properties every generated surface must satisfy, whatever its shape. The expected values come from geometry, not from the generators.
expect_valid_mesh :: proc(t: ^testing.T, mesh: Mesh, label: string) {
	problem := Mesh_Find_Problem(mesh)
	testing.expectf(t, problem == "", "%s: %s", label, problem)
}

// A triangle wound counter-clockwise seen from outside has a geometric normal along the surface normals.
expect_winding_agrees_with_normals :: proc(t: ^testing.T, mesh: Mesh, label: string) {
	for first := 0; first + 2 < len(mesh.indices); first += 3 {
		a, b, c := mesh.vertices[mesh.indices[first]], mesh.vertices[mesh.indices[first + 1]], mesh.vertices[mesh.indices[first + 2]]
		geometric := linalg.cross(b.position - a.position, c.position - a.position)
		if linalg.length(geometric) < 1e-5 do continue // Pole triangles collapse to a point and have no orientation.
		testing.expectf(t, linalg.dot(geometric, a.normal + b.normal + c.normal) > 0, "%s: triangle %d wound against its normals", label, first / 3)
	}
}

@(test)
test_box_is_valid_and_spans_its_size :: proc(t: ^testing.T) {
	mesh := Box_Create({2, 4, 6})
	defer Mesh_Destroy(&mesh)
	expect_valid_mesh(t, mesh, "box")
	lowest, highest := Mesh_Bounds(mesh)
	testing.expect_value(t, lowest, [3]f32{-1, -2, -3})
	testing.expect_value(t, highest, [3]f32{1, 2, 3})
	testing.expect_value(t, len(mesh.vertices), 24)
	testing.expect_value(t, len(mesh.indices), 36)
}

@(test)
test_box_faces_have_axis_aligned_normals :: proc(t: ^testing.T) {
	mesh := Box_Create({1, 1, 1})
	defer Mesh_Destroy(&mesh)
	for vertex in mesh.vertices {
		testing.expect_value(t, abs(vertex.normal.x) + abs(vertex.normal.y) + abs(vertex.normal.z), 1)
	}
}

@(test)
test_sphere_vertices_lie_on_the_radius_with_radial_normals :: proc(t: ^testing.T) {
	radius: f32 = 2.5
	mesh := Sphere_Create(radius, 16, 8)
	defer Mesh_Destroy(&mesh)
	expect_valid_mesh(t, mesh, "sphere")
	for vertex in mesh.vertices {
		testing.expect(t, abs(linalg.length(vertex.position) - radius) < 1e-4)
		testing.expect(t, linalg.length(vertex.normal - vertex.position / radius) < 1e-4)
	}
}

@(test)
test_sphere_counts_bounds_and_uv_coverage :: proc(t: ^testing.T) {
	mesh := Sphere_Create(1, 12, 6)
	defer Mesh_Destroy(&mesh)
	testing.expect_value(t, len(mesh.vertices), (12 + 1) * (6 + 1))
	testing.expect_value(t, len(mesh.indices), 12 * 6 * 6)
	lowest, highest := Mesh_Bounds(mesh)
	testing.expect(t, abs(lowest.y + 1) < 1e-5 && abs(highest.y - 1) < 1e-5)
	u_lowest, u_highest, v_lowest, v_highest: f32 = 1, 0, 1, 0
	for vertex in mesh.vertices {
		u_lowest, u_highest = min(u_lowest, vertex.uv.x), max(u_highest, vertex.uv.x)
		v_lowest, v_highest = min(v_lowest, vertex.uv.y), max(v_highest, vertex.uv.y)
	}
	testing.expect_value(t, [4]f32{u_lowest, u_highest, v_lowest, v_highest}, [4]f32{0, 1, 0, 1})
}

@(test)
test_sphere_encloses_the_volume_of_a_sphere :: proc(t: ^testing.T) {
	mesh := Sphere_Create(1, 64, 32)
	defer Mesh_Destroy(&mesh)
	volume: f32
	for first := 0; first + 2 < len(mesh.indices); first += 3 {
		a, b, c := mesh.vertices[mesh.indices[first]].position, mesh.vertices[mesh.indices[first + 1]].position, mesh.vertices[mesh.indices[first + 2]].position
		volume += linalg.dot(a, linalg.cross(b, c)) / 6
	}
	testing.expect(t, abs(volume - 4.0 / 3.0 * math.PI) < 0.05)
}

signed_volume :: proc(mesh: Mesh) -> f32 {
	volume: f32
	for first := 0; first + 2 < len(mesh.indices); first += 3 {
		a, b, c := mesh.vertices[mesh.indices[first]].position, mesh.vertices[mesh.indices[first + 1]].position, mesh.vertices[mesh.indices[first + 2]].position
		volume += linalg.dot(a, linalg.cross(b, c)) / 6
	}
	return volume
}

@(test)
test_cylinder_is_closed_valid_and_has_the_right_volume :: proc(t: ^testing.T) {
	mesh := Cylinder_Create(1.5, 4, 64)
	defer Mesh_Destroy(&mesh)
	expect_valid_mesh(t, mesh, "cylinder")
	lowest, highest := Mesh_Bounds(mesh)
	testing.expect(t, abs(lowest.y + 2) < 1e-5 && abs(highest.y - 2) < 1e-5)
	testing.expect(t, abs(highest.x - 1.5) < 1e-4 && abs(lowest.z + 1.5) < 1e-4)
	testing.expect(t, abs(signed_volume(mesh) - math.PI * 1.5 * 1.5 * 4) / (math.PI * 1.5 * 1.5 * 4) < 0.005)
}

@(test)
test_cone_is_closed_valid_and_has_the_right_volume :: proc(t: ^testing.T) {
	mesh := Cone_Create(2, 3, 64)
	defer Mesh_Destroy(&mesh)
	expect_valid_mesh(t, mesh, "cone")
	lowest, highest := Mesh_Bounds(mesh)
	testing.expect(t, abs(lowest.y + 1.5) < 1e-5 && abs(highest.y - 1.5) < 1e-5)
	expected_volume: f32 = math.PI * 2 * 2 * 3 / 3
	testing.expect(t, abs(signed_volume(mesh) - expected_volume) / expected_volume < 0.005)
}

@(test)
test_cone_side_normals_tilt_toward_the_apex :: proc(t: ^testing.T) {
	mesh := Cone_Create(1, 1, 8)
	defer Mesh_Destroy(&mesh)
	for vertex in mesh.vertices {
		if vertex.normal.y == 0 || vertex.normal.y == 1 || vertex.normal.y == -1 do continue
		testing.expect(t, abs(vertex.normal.y - 1 / math.sqrt(f32(2))) < 1e-4) // Slope 45 degrees: normal is half up, half outward.
	}
}

@(test)
test_capsule_is_closed_valid_and_has_the_right_volume :: proc(t: ^testing.T) {
	radius, shaft_height: f32 = 0.5, 2
	mesh := Capsule_Create(radius, shaft_height, 48, 16)
	defer Mesh_Destroy(&mesh)
	expect_valid_mesh(t, mesh, "capsule")
	lowest, highest := Mesh_Bounds(mesh)
	testing.expect(t, abs(highest.y - (shaft_height / 2 + radius)) < 1e-4 && abs(lowest.y + (shaft_height / 2 + radius)) < 1e-4)
	expected_volume: f32 = math.PI * radius * radius * shaft_height + 4.0 / 3.0 * math.PI * radius * radius * radius
	testing.expect(t, abs(signed_volume(mesh) - expected_volume) / expected_volume < 0.01)
}

@(test)
test_capsule_with_no_shaft_is_a_sphere :: proc(t: ^testing.T) {
	mesh := Capsule_Create(1, 0, 32, 16)
	defer Mesh_Destroy(&mesh)
	for vertex in mesh.vertices do testing.expect(t, abs(linalg.length(vertex.position) - 1) < 1e-4)
}

@(test)
test_torus_is_valid_and_has_the_right_volume :: proc(t: ^testing.T) {
	major, minor: f32 = 2, 0.5
	mesh := Torus_Create(major, minor, 64, 32)
	defer Mesh_Destroy(&mesh)
	expect_valid_mesh(t, mesh, "torus")
	lowest, highest := Mesh_Bounds(mesh)
	testing.expect(t, abs(highest.x - (major + minor)) < 1e-4 && abs(highest.y - minor) < 1e-4)
	expected_volume: f32 = 2 * math.PI * math.PI * major * minor * minor
	testing.expect(t, abs(signed_volume(mesh) - expected_volume) / expected_volume < 0.01)
}

@(test)
test_torus_vertices_sit_one_minor_radius_from_the_core_circle :: proc(t: ^testing.T) {
	mesh := Torus_Create(3, 1, 24, 12)
	defer Mesh_Destroy(&mesh)
	for vertex in mesh.vertices {
		horizontal := linalg.length([2]f32{vertex.position.x, vertex.position.z})
		distance_to_core := linalg.length([2]f32{horizontal - 3, vertex.position.y})
		testing.expect(t, abs(distance_to_core - 1) < 1e-4)
	}
}

@(test)
test_wedge_is_closed_valid_and_has_the_right_volume :: proc(t: ^testing.T) {
	mesh := Wedge_Create({2, 3, 4})
	defer Mesh_Destroy(&mesh)
	expect_valid_mesh(t, mesh, "wedge")
	lowest, highest := Mesh_Bounds(mesh)
	testing.expect_value(t, lowest, [3]f32{-1, -1.5, -2})
	testing.expect_value(t, highest, [3]f32{1, 1.5, 2})
	testing.expect(t, abs(signed_volume(mesh) - 2 * 3 * 4 / 2) < 1e-4)
}

@(test)
test_wedge_slope_faces_up_and_toward_the_low_end :: proc(t: ^testing.T) {
	mesh := Wedge_Create({2, 2, 2})
	defer Mesh_Destroy(&mesh)
	found_slope := false
	for vertex in mesh.vertices {
		if vertex.normal.y > 0.1 && vertex.normal.z > 0.1 {
			found_slope = true
			testing.expect(t, abs(vertex.normal.y - vertex.normal.z) < 1e-5) // 45 degree ramp.
		}
	}
	testing.expect(t, found_slope)
}

@(test)
test_subdivided_box_keeps_its_shape_and_adds_grid_vertices :: proc(t: ^testing.T) {
	mesh := Box_Create({2, 2, 2}, {4, 3, 2})
	defer Mesh_Destroy(&mesh)
	expect_valid_mesh(t, mesh, "subdivided box")
	testing.expect_value(t, len(mesh.vertices), 2 * (4 * 3 + 5 * 3 + 5 * 4))
	testing.expect_value(t, len(mesh.indices), 2 * 6 * (3 * 2 + 4 * 2 + 4 * 3))
	testing.expect(t, abs(signed_volume(mesh) - 8) < 1e-4)
	lowest, highest := Mesh_Bounds(mesh)
	testing.expect_value(t, lowest, [3]f32{-1, -1, -1})
	testing.expect_value(t, highest, [3]f32{1, 1, 1})
}

@(test)
test_cylinder_height_segments_add_rings_without_changing_volume :: proc(t: ^testing.T) {
	mesh := Cylinder_Create(1, 3, 32, 4)
	defer Mesh_Destroy(&mesh)
	expect_valid_mesh(t, mesh, "segmented cylinder")
	heights := make(map[f32]bool)
	defer delete(heights)
	for vertex in mesh.vertices do heights[math.round(vertex.position.y * 1000) / 1000] = true
	testing.expect_value(t, len(heights), 5)
	expected_volume: f32 = math.PI * 3
	testing.expect(t, abs(signed_volume(mesh) - expected_volume) / expected_volume < 0.01)
}

@(test)
test_capsule_shaft_segments_add_rings_without_changing_volume :: proc(t: ^testing.T) {
	mesh := Capsule_Create(0.5, 2, 32, 8, 3)
	defer Mesh_Destroy(&mesh)
	expect_valid_mesh(t, mesh, "segmented capsule")
	testing.expect_value(t, len(mesh.vertices), (2 * (8 + 1) + 2) * (32 + 1))
	expected_volume: f32 = math.PI * 0.25 * 2 + 4.0 / 3.0 * math.PI * 0.125
	testing.expect(t, abs(signed_volume(mesh) - expected_volume) / expected_volume < 0.01)
}
