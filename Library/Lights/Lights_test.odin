// Lights_test.odin — proves Update_From_Scene actually derives a light's
// world Position/Direction from its parent's LIVE world matrix, run with
// `odin test Library/Lights`. Central case (explicitly asked for this
// session): a light attached to a ROTATED child lands at the expected
// world position — and, since CLAUDE.md §5.3's hardest test is the tank's
// nested hull->turret chain, a two-level version of the same check too.
package Lights

import "core:math"
import la "core:math/linalg"
import "core:testing"

import geo "../Geometry"
import scenepkg "../Scene"

EPSILON :: 1e-4

// test_point_light_follows_rotated_parent mirrors Library/Scene/
// Transform_test.odin's own "rotating arm moves tip" case (+90 degrees
// about Y carries local +X to world -Z), just through a Light's
// LocalOffset instead of a child Node's own Position — proving the same
// hierarchy math applies identically to lights.
@(test)
test_point_light_follows_rotated_parent :: proc(t: ^testing.T) {
	h := scenepkg.Hierarchy{}
	defer scenepkg.Destroy(&h)

	base := scenepkg.Add_Node(&h, "base", scenepkg.NO_PARENT, scenepkg.Identity_Transform(), geo.Empty_Mesh(), scenepkg.Default_Material({1, 1, 1}))

	arm_local := scenepkg.Identity_Transform()
	arm_local.Rotation.y = math.to_radians(f32(90))
	arm := scenepkg.Add_Node(&h, "arm", base, arm_local, geo.Empty_Mesh(), scenepkg.Default_Material({1, 1, 1}))

	lights := make([dynamic]Light, 0, 1)
	defer delete(lights)
	append(&lights, Make_Point(arm, la.Vector3f32{2, 0, 0}, la.Vector3f32{1, 1, 1}, 1.0, 10.0))

	world := scenepkg.Compute_World_Matrices(&h)
	defer delete(world)
	Update_From_Scene(lights[:], world[:])

	expect_vector3_near(t, lights[0].Position, la.Vector3f32{0, 0, -2})
}

// test_spot_light_direction_follows_rotated_parent checks the DIRECTION
// half of the same requirement: a spot's LocalDirection must rotate with
// its parent too, not just its position (Shaders/Scene.glsl's cone falloff
// depends on this being right, not just where the light sits).
@(test)
test_spot_light_direction_follows_rotated_parent :: proc(t: ^testing.T) {
	h := scenepkg.Hierarchy{}
	defer scenepkg.Destroy(&h)

	turret_local := scenepkg.Identity_Transform()
	turret_local.Rotation.y = math.to_radians(f32(90))
	turret := scenepkg.Add_Node(&h, "turret", scenepkg.NO_PARENT, turret_local, geo.Empty_Mesh(), scenepkg.Default_Material({1, 1, 1}))

	lights := make([dynamic]Light, 0, 1)
	defer delete(lights)
	append(&lights, Make_Spot(turret, la.Vector3f32{0, 0, 0}, la.Vector3f32{0, 0, 1}, la.Vector3f32{1, 1, 1}, 1.0, 10.0, 10, 20))

	world := scenepkg.Compute_World_Matrices(&h)
	defer delete(world)
	Update_From_Scene(lights[:], world[:])

	// Local +Z rotated +90 degrees about Y -> world +X (the same rotation
	// Library/Lights/Lights.odin's direction_rotation gizmo helper and
	// Library/Camera/Camera.odin's Forward both already rely on).
	expect_vector3_near(t, lights[0].Direction, la.Vector3f32{1, 0, 0})
}

// test_light_follows_nested_rotated_chain is the tank's own hull->turret
// scenario in miniature: TWO independent rotations must compose correctly
// for a light parented to the innermost node — the exact case CLAUDE.md
// §5.3 calls the clearest possible demonstration that a child transform
// can move independently of its parent while an attached light stays
// correctly tracked through both.
@(test)
test_light_follows_nested_rotated_chain :: proc(t: ^testing.T) {
	h := scenepkg.Hierarchy{}
	defer scenepkg.Destroy(&h)

	hull_local := scenepkg.Identity_Transform()
	hull_local.Rotation.y = math.to_radians(f32(90))
	hull := scenepkg.Add_Node(&h, "hull", scenepkg.NO_PARENT, hull_local, geo.Empty_Mesh(), scenepkg.Default_Material({1, 1, 1}))

	turret_local := scenepkg.Identity_Transform()
	turret_local.Rotation.y = math.to_radians(f32(90)) // independent of the hull's own rotation
	turret := scenepkg.Add_Node(&h, "turret", hull, turret_local, geo.Empty_Mesh(), scenepkg.Default_Material({1, 1, 1}))

	lights := make([dynamic]Light, 0, 1)
	defer delete(lights)
	append(&lights, Make_Point(turret, la.Vector3f32{2, 0, 0}, la.Vector3f32{1, 1, 1}, 1.0, 10.0))

	world := scenepkg.Compute_World_Matrices(&h)
	defer delete(world)
	Update_From_Scene(lights[:], world[:])

	// Two +90-degree Y rotations compose to +180: local +X ends up at
	// world -X (turning the tip all the way around), not back at +X and
	// not at the single-rotation -Z either — this is what actually
	// distinguishes "composed through two nested transforms" from
	// "accidentally reads the wrong one."
	expect_vector3_near(t, lights[0].Position, la.Vector3f32{-2, 0, 0})
}

@(private = "file")
expect_vector3_near :: proc(t: ^testing.T, got, want: la.Vector3f32, loc := #caller_location) {
	for i in 0 ..< 3 {
		diff := math.abs(got[i] - want[i])
		testing.expectf(t, diff <= EPSILON, "vector mismatch at component %d: got %v, want %v (diff %v)", i, got, want, diff, loc = loc)
	}
}
