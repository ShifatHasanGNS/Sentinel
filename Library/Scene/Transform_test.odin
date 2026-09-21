// Transform_test.odin — hierarchy correctness checks, run with
// `odin test Library/Scene`.
//
// Central case: a 3-level chain (base -> arm -> tip). Rotating the arm
// must move the tip through the arm's OWN rotation, composed with
// whatever the base is doing — the exact bug class CLAUDE.md §5.3 calls
// out ("rotating the tank hull, then the turret independently, must keep
// [children] correctly tracked through nested transforms").
package Scene

import "core:math"
import la "core:math/linalg"
import "core:testing"

import geo "../Geometry"

EPSILON :: 1e-4

@(test)
test_root_node_world_matrix_is_its_local_matrix :: proc(t: ^testing.T) {
	h := Hierarchy{}
	defer Destroy(&h)

	local := Identity_Transform()
	local.Position = {3, 4, 5}
	Add_Node(&h, "root", NO_PARENT, local, geo_empty_mesh(), la.Vector3f32{1, 1, 1})

	world := Compute_World_Matrices(&h)
	defer delete(world)

	expect_vector3_near(t, World_Position(world[0]), la.Vector3f32{3, 4, 5})
}

@(test)
test_three_level_chain_tip_position_before_rotation :: proc(t: ^testing.T) {
	h := Hierarchy{}
	defer Destroy(&h)

	base := Add_Node(&h, "base", NO_PARENT, Identity_Transform(), geo_empty_mesh(), la.Vector3f32{1, 1, 1})

	arm_local := Identity_Transform()
	arm := Add_Node(&h, "arm", base, arm_local, geo_empty_mesh(), la.Vector3f32{1, 1, 1})

	tip_local := Identity_Transform()
	tip_local.Position = {2, 0, 0}
	tip := Add_Node(&h, "tip", arm, tip_local, geo_empty_mesh(), la.Vector3f32{1, 1, 1})

	world := Compute_World_Matrices(&h)
	defer delete(world)

	expect_vector3_near(t, World_Position(world[tip]), la.Vector3f32{2, 0, 0})
}

// The central hierarchy test: rotating the ARM by +90 degrees about Y must
// carry the tip from (2,0,0) to (0,0,-2) — the same +X -> -Z rotation
// Library/Camera/Camera_test.odin already confirmed, now proven through a
// parent-child transform chain rather than a single matrix.
@(test)
test_rotating_arm_moves_tip_through_the_chain :: proc(t: ^testing.T) {
	h := Hierarchy{}
	defer Destroy(&h)

	base := Add_Node(&h, "base", NO_PARENT, Identity_Transform(), geo_empty_mesh(), la.Vector3f32{1, 1, 1})

	arm_local := Identity_Transform()
	arm_local.Rotation.y = math.to_radians(f32(90))
	arm := Add_Node(&h, "arm", base, arm_local, geo_empty_mesh(), la.Vector3f32{1, 1, 1})

	tip_local := Identity_Transform()
	tip_local.Position = {2, 0, 0}
	tip := Add_Node(&h, "tip", arm, tip_local, geo_empty_mesh(), la.Vector3f32{1, 1, 1})

	world := Compute_World_Matrices(&h)
	defer delete(world)

	expect_vector3_near(t, World_Position(world[tip]), la.Vector3f32{0, 0, -2})
}

// Rotating/moving the BASE must move every downstream node, composed with
// whatever the arm is already doing — confirms world matrices compose
// through more than one level, not just parent-of-root.
@(test)
test_moving_base_moves_everything_downstream :: proc(t: ^testing.T) {
	h := Hierarchy{}
	defer Destroy(&h)

	base_local := Identity_Transform()
	base := Add_Node(&h, "base", NO_PARENT, base_local, geo_empty_mesh(), la.Vector3f32{1, 1, 1})

	arm_local := Identity_Transform()
	arm_local.Rotation.y = math.to_radians(f32(90))
	arm := Add_Node(&h, "arm", base, arm_local, geo_empty_mesh(), la.Vector3f32{1, 1, 1})

	tip_local := Identity_Transform()
	tip_local.Position = {2, 0, 0}
	tip := Add_Node(&h, "tip", arm, tip_local, geo_empty_mesh(), la.Vector3f32{1, 1, 1})

	h.Nodes[base].Local.Position = {5, 0, 0}

	world := Compute_World_Matrices(&h)
	defer delete(world)

	expect_vector3_near(t, World_Position(world[tip]), la.Vector3f32{5, 0, -2})
}

@(test)
test_world_direction_ignores_translation :: proc(t: ^testing.T) {
	h := Hierarchy{}
	defer Destroy(&h)

	local := Identity_Transform()
	local.Position = {100, 200, 300} // large translation; must not leak into the direction
	local.Rotation.y = math.to_radians(f32(90))
	Add_Node(&h, "node", NO_PARENT, local, geo_empty_mesh(), la.Vector3f32{1, 1, 1})

	world := Compute_World_Matrices(&h)
	defer delete(world)

	// Local +X rotated +90 degrees about Y -> -Z (the established convention).
	direction := World_Direction(world[0], la.Vector3f32{1, 0, 0})
	expect_vector3_near(t, direction, la.Vector3f32{0, 0, -1})
}

@(test)
test_find_node_by_name :: proc(t: ^testing.T) {
	h := Hierarchy{}
	defer Destroy(&h)

	Add_Node(&h, "alpha", NO_PARENT, Identity_Transform(), geo_empty_mesh(), la.Vector3f32{1, 1, 1})
	beta := Add_Node(&h, "beta", NO_PARENT, Identity_Transform(), geo_empty_mesh(), la.Vector3f32{1, 1, 1})

	testing.expect(t, Find_Node(&h, "beta") == beta)
	testing.expect(t, Find_Node(&h, "does not exist") == NO_PARENT)
}

@(private = "file")
geo_empty_mesh :: proc() -> geo.Mesh {
	return geo.Empty_Mesh()
}

@(private = "file")
expect_vector3_near :: proc(t: ^testing.T, got, want: la.Vector3f32, loc := #caller_location) {
	for i in 0 ..< 3 {
		diff := math.abs(got[i] - want[i])
		testing.expectf(t, diff <= EPSILON, "vector mismatch at component %d: got %v, want %v (diff %v)", i, got, want, diff, loc = loc)
	}
}
