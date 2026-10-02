package Procedural

import "core:math/linalg"
import "core:testing"

@(test)
test_parts_with_one_material_merge_into_one_mesh_with_summed_counts :: proc(t: ^testing.T) {
	assembly := Assembly_Build({
		{primitive = Box({2, 2, 2}), material = 1},
		{primitive = Sphere(1, 16, 8), position = {5, 0, 0}, material = 1},
	})
	defer Assembly_Destroy(&assembly)
	testing.expect_value(t, len(assembly.groups), 1)
	box, sphere := Box_Create({2, 2, 2}), Sphere_Create(1, 16, 8)
	defer Mesh_Destroy(&box)
	defer Mesh_Destroy(&sphere)
	testing.expect_value(t, len(assembly.groups[0].mesh.vertices), len(box.vertices) + len(sphere.vertices))
	testing.expect_value(t, len(assembly.groups[0].mesh.indices), len(box.indices) + len(sphere.indices))
	lowest, highest := Assembly_Bounds(assembly)
	testing.expect_value(t, lowest, [3]f32{-1, -1, -1})
	testing.expect_value(t, highest, [3]f32{6, 1, 1})
}

@(test)
test_materials_and_emission_split_groups_and_equal_ones_share :: proc(t: ^testing.T) {
	assembly := Assembly_Build({
		{primitive = Box({1, 1, 1}), material = 1},
		{primitive = Box({1, 1, 1}), position = {3, 0, 0}, material = 2},
		{primitive = Box({1, 1, 1}), position = {6, 0, 0}, material = 1},
		{primitive = Box({1, 1, 1}), position = {9, 0, 0}, material = 1, emission = {1, 0.8, 0.4}},
	})
	defer Assembly_Destroy(&assembly)
	testing.expect_value(t, len(assembly.groups), 3)
	for group in assembly.groups {
		if group.material == 1 && group.emission == {} do testing.expect_value(t, len(group.mesh.vertices), 48)
		else do testing.expect_value(t, len(group.mesh.vertices), 24)
	}
}

@(test)
test_rotation_and_stretch_place_each_part :: proc(t: ^testing.T) {
	turned := Assembly_Build({{primitive = Box({4, 1, 2}), rotation_degrees = {0, 90, 0}}})
	defer Assembly_Destroy(&turned)
	lowest, highest := Assembly_Bounds(turned)
	testing.expect(t, linalg.length(highest - [3]f32{1, 0.5, 2}) < 1e-4 && linalg.length(lowest - [3]f32{-1, -0.5, -2}) < 1e-4)

	tall := Assembly_Build({{primitive = Sphere(1, 24, 12), stretch = {1, 3, 0}}}) // A zero component of stretch means 1.
	defer Assembly_Destroy(&tall)
	lowest, highest = Assembly_Bounds(tall)
	testing.expect(t, abs(highest.y - 3) < 1e-4 && abs(highest.x - 1) < 1e-4 && abs(highest.z - 1) < 1e-4)
}

@(test)
test_deformers_apply_before_stretch :: proc(t: ^testing.T) {
	assembly := Assembly_Build({{primitive = Cylinder(1, 2, 24, 4), deformers = {Taper{1, 0.5}}, stretch = {2, 1, 2}}})
	defer Assembly_Destroy(&assembly)
	top_radius, bottom_radius: f32
	for vertex in assembly.groups[0].mesh.vertices {
		radius := linalg.length([2]f32{vertex.position.x, vertex.position.z})
		if abs(vertex.position.y - 1) < 1e-4 do top_radius = max(top_radius, radius)
		if abs(vertex.position.y + 1) < 1e-4 do bottom_radius = max(bottom_radius, radius)
	}
	testing.expect(t, abs(bottom_radius - 2) < 1e-3 && abs(top_radius - 1) < 1e-3) // Tapered 1 -> 0.5, then stretched x2.
}

@(test)
test_only_solid_parts_produce_collision_boxes_matching_their_bounds :: proc(t: ^testing.T) {
	assembly := Assembly_Build({
		{primitive = Box({2, 2, 2}), solid = true},
		{primitive = Sphere(1, 12, 6), position = {10, 0, 0}},
		{primitive = Box({4, 1, 2}), position = {0, 5, 0}, rotation_degrees = {0, 90, 0}, solid = true},
	})
	defer Assembly_Destroy(&assembly)
	testing.expect_value(t, len(assembly.collision_boxes), 2)
	testing.expect_value(t, assembly.collision_boxes[0], Collision_Box{{-1, -1, -1}, {1, 1, 1}})
	box := assembly.collision_boxes[1]
	testing.expect(t, linalg.length(box.lowest - [3]f32{-1, 4.5, -2}) < 1e-4 && linalg.length(box.highest - [3]f32{1, 5.5, 2}) < 1e-4)
}

@(test)
test_assembled_meshes_are_valid_even_with_mirroring :: proc(t: ^testing.T) {
	assembly := Assembly_Build({
		{primitive = Cylinder(1, 2, 16, 2), stretch = {-1, 1, 1}, material = 0},
		{primitive = Capsule(0.5, 1, 16, 6), position = {4, 0, 0}, rotation_degrees = {30, 20, 10}, material = 0},
		{primitive = Sphere(1, 20, 10), deformers = {Noise_Displace{0.2, 1.5, 3, 4}}, position = {-4, 0, 0}, material = 0},
	})
	defer Assembly_Destroy(&assembly)
	expect_valid_mesh(t, assembly.groups[0].mesh, "assembled")
}

@(test)
test_assembly_is_deterministic :: proc(t: ^testing.T) {
	parts := []Part{
		{primitive = Sphere(1, 20, 10), deformers = {Noise_Displace{0.2, 1.5, 3, 9}}, material = 2},
		{primitive = Torus(1, 0.2, 24, 8), position = {0, 2, 0}, rotation_degrees = {90, 0, 0}, material = 2},
	}
	first, second := Assembly_Build(parts), Assembly_Build(parts)
	defer Assembly_Destroy(&first)
	defer Assembly_Destroy(&second)
	testing.expect_value(t, len(first.groups[0].mesh.vertices), len(second.groups[0].mesh.vertices))
	for vertex, index in first.groups[0].mesh.vertices do testing.expect_value(t, vertex, second.groups[0].mesh.vertices[index])
}
