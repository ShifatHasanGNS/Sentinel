package Catalogue

import "../../Engine/Procedural"
import "core:math"
import "core:testing"

// Real-world size ranges in meters, as {width x, height y, depth z} minimum and maximum. Objects stand on y = 0 and face +Z;
// vehicles are long along Z. The ranges come from how big these things are, not from the models.
Size_Range :: struct {
	lowest:  [3]f32,
	highest: [3]f32,
}

size_ranges := [Object_Kind]Size_Range{
	.Barracks = {{12, 3, 5}, {24, 6, 9}},
	.Headquarters = {{10, 3.5, 8}, {20, 8, 14}},
	.Hangar = {{12, 6, 18}, {20, 10, 32}},
	.Mess_Hall = {{10, 3, 6}, {18, 6, 10}},
	.Generator_Shed = {{2.5, 2, 2.5}, {5, 3.5, 5}},
	.Fuel_Tank = {{6, 2.5, 2.5}, {10, 4.5, 4}},
	.Water_Tower = {{4, 10, 4}, {8, 18, 8}},
	.Watchtower = {{2.5, 6, 2.5}, {5, 11, 5}},
	.Guard_Post = {{2, 2.4, 2}, {4, 3.6, 4}},
	.Bunker = {{4, 1.8, 4}, {9, 3.5, 9}},
	.Helipad = {{14, 0.1, 14}, {24, 0.8, 24}},
	.Radio_Mast = {{1, 20, 1}, {7, 35, 7}},
	.Radar_Station = {{3, 4, 3}, {7, 9, 7}},
	.Fence_Section = {{2.8, 2.2, 0.1}, {3.2, 3.6, 0.5}},
	.Gate = {{6, 2.5, 0.2}, {10, 4, 0.8}},
	.Barrier_Arm = {{4, 1, 0.2}, {8, 1.6, 0.8}},
	.T_Wall = {{2, 2.5, 0.5}, {4, 4, 1.4}},
	.Hesco_Barrier = {{1, 1.2, 1}, {2.2, 2.2, 2.2}},
	.Sandbag_Wall = {{2, 0.6, 0.4}, {4, 1.4, 1}},
	.Jeep = {{1.8, 1.6, 4}, {2.4, 2.3, 5.5}},
	.Cargo_Truck = {{2.2, 2.8, 6}, {2.8, 3.8, 9}},
	.Armored_Carrier = {{2.4, 2.2, 6}, {3, 3.2, 8.5}},
	.Battle_Tank = {{3, 2.2, 6.5}, {4, 3.2, 11}},
	.Helicopter = {{11, 3, 11}, {16, 5, 18}},
	.Crate = {{0.8, 0.8, 0.8}, {1.5, 1.5, 1.5}},
	.Barrel = {{0.5, 0.8, 0.5}, {0.7, 1.0, 0.7}},
	.Pallet = {{1.1, 0.9, 1.1}, {1.4, 1.8, 1.4}},
	.Tent = {{3, 2, 4}, {7, 3.5, 9}},
	.Camo_Net = {{5, 2, 5}, {12, 3.5, 12}},
	.Floodlight = {{0.5, 3.5, 0.5}, {1.5, 6, 1.5}},
	.Sign = {{1, 1.8, 0.05}, {2, 2.8, 0.3}},
	.Flag = {{0.8, 5, 0.05}, {2.2, 8, 0.4}},
	.Ammo_Box = {{0.3, 0.18, 0.15}, {0.7, 0.4, 0.4}},
}

TRIANGLE_BUDGET_PER_OBJECT :: 30000

@(test)
test_every_object_is_valid_finite_grounded_and_budgeted :: proc(t: ^testing.T) {
	for kind in Object_Kind {
		assembly := Catalogue_Build(kind)
		defer Procedural.Assembly_Destroy(&assembly)
		label := object_name(kind)
		testing.expectf(t, len(assembly.groups) > 0, "%s: no geometry", label)
		if len(assembly.groups) == 0 do continue
		triangles := 0
		for group in assembly.groups {
			triangles += len(group.mesh.indices) / 3
			for vertex in group.mesh.vertices {
				for value in vertex.position do testing.expectf(t, !math.is_nan(value) && !math.is_inf(value), "%s: non-finite vertex", label)
			}
			problem := Procedural.Mesh_Find_Problem(group.mesh)
			testing.expectf(t, problem == "", "%s: %s", label, problem)
		}
		testing.expectf(t, triangles <= TRIANGLE_BUDGET_PER_OBJECT, "%s: %d triangles exceeds the budget", label, triangles)
		lowest, _ := Procedural.Assembly_Bounds(assembly)
		testing.expectf(t, lowest.y >= -0.3 && lowest.y <= 0.1, "%s: lowest point %f is not resting on the ground", label, lowest.y)
	}
}

@(test)
test_every_object_has_a_plausible_real_world_size :: proc(t: ^testing.T) {
	for kind in Object_Kind {
		assembly := Catalogue_Build(kind)
		defer Procedural.Assembly_Destroy(&assembly)
		if len(assembly.groups) == 0 do continue
		lowest, highest := Procedural.Assembly_Bounds(assembly)
		size := highest - lowest
		range := size_ranges[kind]
		for axis in 0 ..< 3 {
			testing.expectf(t, size[axis] >= range.lowest[axis] && size[axis] <= range.highest[axis], "%s: axis %d is %.2f m, expected %.2f to %.2f", object_name(kind), axis, size[axis], range.lowest[axis], range.highest[axis])
		}
	}
}

@(test)
test_objects_are_deterministic :: proc(t: ^testing.T) {
	for kind in Object_Kind {
		first, second := Catalogue_Build(kind), Catalogue_Build(kind)
		defer Procedural.Assembly_Destroy(&first)
		defer Procedural.Assembly_Destroy(&second)
		testing.expect_value(t, len(first.groups), len(second.groups))
		for group, index in first.groups {
			testing.expect_value(t, len(group.mesh.vertices), len(second.groups[index].mesh.vertices))
			for vertex, vertex_index in group.mesh.vertices {
				if vertex != second.groups[index].mesh.vertices[vertex_index] {
					testing.expectf(t, false, "%s: output differs between builds", object_name(kind))
					break
				}
			}
		}
	}
}

// Collision boxes (for walking and shooting) come from the parts marked solid. They must hug the visible object: never stick
// out past it, and together reach most of its extent so walls actually block.
@(test)
test_collision_boxes_hug_the_visible_object :: proc(t: ^testing.T) {
	for kind in Object_Kind {
		assembly := Catalogue_Build(kind)
		defer Procedural.Assembly_Destroy(&assembly)
		if len(assembly.groups) == 0 do continue
		lowest, highest := Procedural.Assembly_Bounds(assembly)
		testing.expectf(t, len(assembly.collision_boxes) > 0, "%s: no collision boxes", object_name(kind))
		if len(assembly.collision_boxes) == 0 do continue
		box_lowest, box_highest := assembly.collision_boxes[0].lowest, assembly.collision_boxes[0].highest
		for box in assembly.collision_boxes {
			box_lowest = {min(box_lowest.x, box.lowest.x), min(box_lowest.y, box.lowest.y), min(box_lowest.z, box.lowest.z)}
			box_highest = {max(box_highest.x, box.highest.x), max(box_highest.y, box.highest.y), max(box_highest.z, box.highest.z)}
		}
		for axis in 0 ..< 3 {
			testing.expectf(t, box_lowest[axis] >= lowest[axis] - 0.05 && box_highest[axis] <= highest[axis] + 0.05, "%s: collision boxes stick out on axis %d", object_name(kind), axis)
			extent, covered := highest[axis] - lowest[axis], box_highest[axis] - box_lowest[axis]
			thin := extent < 1 // A fence's thickness needs no coverage rule.
			guy_wires := kind == .Radio_Mast && axis != 1 // Thin diagonal wires are not collision geometry.
			if thin || guy_wires do continue
			testing.expectf(t, covered >= 0.6 * extent, "%s: collision boxes cover only %.0f%% of axis %d", object_name(kind), 100 * covered / extent, axis)
		}
	}
}

// Shadows need only an object's structure, not its bars, wires and panes: the shadow mesh is the solid parts alone.
@(test)
test_shadow_meshes_are_a_cheaper_subset_of_each_object :: proc(t: ^testing.T) {
	for kind in Object_Kind {
		full, shadow := Catalogue_Build(kind), Catalogue_Build_Shadow(kind)
		defer Procedural.Assembly_Destroy(&full)
		defer Procedural.Assembly_Destroy(&shadow)
		full_triangles, shadow_triangles := 0, 0
		for group in full.groups do full_triangles += len(group.mesh.indices) / 3
		for group in shadow.groups do shadow_triangles += len(group.mesh.indices) / 3
		testing.expectf(t, shadow_triangles > 0, "%s: empty shadow mesh", object_name(kind))
		testing.expectf(t, shadow_triangles <= full_triangles, "%s: shadow mesh is bigger than the object", object_name(kind))
	}
	fence_full, fence_shadow := Catalogue_Build(.Fence_Section), Catalogue_Build_Shadow(.Fence_Section)
	defer Procedural.Assembly_Destroy(&fence_full)
	defer Procedural.Assembly_Destroy(&fence_shadow)
	count :: proc(assembly: Procedural.Assembly) -> (triangles: int) {
		for group in assembly.groups do triangles += len(group.mesh.indices) / 3
		return
	}
	testing.expect(t, count(fence_shadow) * 3 < count(fence_full)) // The fence's wire mesh and razor coil are most of its triangles.
}
