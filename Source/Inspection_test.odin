// Inspection_test.odin — unit tests for Source/Inspection.odin's ray/AABB
// picking math, run with `odin test Source`. This is the one piece of this
// session's work with no live interactive way to verify it (mouse clicking
// requires an actual human at an actual window) and no analytic-formula
// cross-check the way the searchlight-rotation headless test has — so it
// gets real, isolated unit tests instead, the same "don't just trust the
// math, check it" standard Library/Camera/Camera_test.odin already holds
// the rest of this project's geometry to.
package main

import "core:math"
import la "core:math/linalg"
import "core:testing"

import cam "../Library/Camera"

EPSILON :: 1e-4

@(test)
test_ray_intersects_aabb_hits_centered_box :: proc(t: ^testing.T) {
	box := AABB{Min = {-1, -1, -1}, Max = {1, 1, 1}}
	origin := la.Vector3f32{0, 0, 5}
	direction := la.Vector3f32{0, 0, -1}

	hit_t, hit := Ray_Intersects_AABB(origin, direction, box)
	testing.expect(t, hit, "expected a hit")
	testing.expectf(t, math.abs(hit_t-4) <= EPSILON, "expected t ~= 4 (distance to the near face), got %v", hit_t)
}

@(test)
test_ray_intersects_aabb_misses_box_to_the_side :: proc(t: ^testing.T) {
	box := AABB{Min = {-1, -1, -1}, Max = {1, 1, 1}}
	origin := la.Vector3f32{10, 10, 5}
	direction := la.Vector3f32{0, 0, -1}

	_, hit := Ray_Intersects_AABB(origin, direction, box)
	testing.expect(t, !hit, "expected no hit for a ray that passes nowhere near the box")
}

@(test)
test_ray_intersects_aabb_reports_zero_when_origin_is_inside :: proc(t: ^testing.T) {
	box := AABB{Min = {-1, -1, -1}, Max = {1, 1, 1}}
	origin := la.Vector3f32{0, 0, 0}
	direction := la.Vector3f32{0, 0, -1}

	hit_t, hit := Ray_Intersects_AABB(origin, direction, box)
	testing.expect(t, hit, "expected a hit for a ray starting inside the box")
	testing.expectf(t, hit_t >= 0, "expected a non-negative t for an inside-box origin, got %v", hit_t)
}

@(test)
test_ray_intersects_aabb_ignores_box_behind_the_ray :: proc(t: ^testing.T) {
	box := AABB{Min = {-1, -1, -1}, Max = {1, 1, 1}}
	origin := la.Vector3f32{0, 0, -5} // box is at z=[-1,1], ray points further away (-Z)
	direction := la.Vector3f32{0, 0, -1}

	_, hit := Ray_Intersects_AABB(origin, direction, box)
	testing.expect(t, !hit, "expected no hit for a box entirely behind the ray's direction")
}

// Confirms Screen_Point_To_Ray's own documented claim: for a camera facing
// -Z at the origin, the screen-centre ray (NDC 0,0) must point straight
// down -Z, matching Library/Camera.Camera's own Forward at yaw=pitch=0 —
// the same "known configuration, known answer" standard Camera_test.odin
// already uses throughout.
@(test)
test_screen_point_to_ray_centre_matches_camera_forward :: proc(t: ^testing.T) {
	test_camera := cam.Default_Camera(la.Vector3f32{0, 0, 5})
	view := cam.View_Matrix(&test_camera)
	projection := cam.Projection_Matrix(&test_camera, 1.0)

	origin, direction := Screen_Point_To_Ray(view, projection, 0, 0)

	expect_vector3_near(t, direction, la.Vector3f32{0, 0, -1})
	testing.expectf(t, math.abs(origin.x) <= EPSILON && math.abs(origin.y) <= EPSILON, "expected the near point to be on the camera's own forward axis (x~=0, y~=0), got %v", origin)
}

// An end-to-end sanity check of the whole picking pipeline: a camera at
// the origin facing -Z, two boxes at different depths directly ahead —
// Pick_Node must return the NEARER one, not just "a" hit, and a ray aimed
// off to the side must return -1 (nothing).
@(test)
test_pick_node_returns_nearest_hit :: proc(t: ^testing.T) {
	test_camera := cam.Default_Camera(la.Vector3f32{0, 0, 0})
	view := cam.View_Matrix(&test_camera)
	projection := cam.Projection_Matrix(&test_camera, 1.0)

	world_matrices := []la.Matrix4f32{
		la.matrix4_translate(la.Vector3f32{0, 0, -20}), // node 0: far box
		la.matrix4_translate(la.Vector3f32{0, 0, -5}),  // node 1: near box
		la.matrix4_translate(la.Vector3f32{50, 0, -5}), // node 2: off to the side, never hit
	}
	unit_box := AABB{Min = {-1, -1, -1}, Max = {1, 1, 1}}
	selectable := []int{0, 1, 2}
	local_aabbs := []AABB{unit_box, unit_box, unit_box}

	origin, direction := Screen_Point_To_Ray(view, projection, 0, 0)
	picked := Pick_Node(world_matrices, selectable, local_aabbs, origin, direction)

	testing.expectf(t, picked == 1, "expected the NEAR box (selectable index 1) to win over the far one, got %v", picked)
}

@(test)
test_pick_node_returns_negative_one_when_nothing_hit :: proc(t: ^testing.T) {
	test_camera := cam.Default_Camera(la.Vector3f32{0, 0, 0})
	view := cam.View_Matrix(&test_camera)
	projection := cam.Projection_Matrix(&test_camera, 1.0)

	world_matrices := []la.Matrix4f32{la.matrix4_translate(la.Vector3f32{50, 0, -5})}
	selectable := []int{0}
	local_aabbs := []AABB{{Min = {-1, -1, -1}, Max = {1, 1, 1}}}

	origin, direction := Screen_Point_To_Ray(view, projection, 0, 0)
	picked := Pick_Node(world_matrices, selectable, local_aabbs, origin, direction)

	testing.expectf(t, picked == -1, "expected no pick (-1), got %v", picked)
}

@(private = "file")
expect_vector3_near :: proc(t: ^testing.T, got, want: la.Vector3f32, loc := #caller_location) {
	for i in 0 ..< 3 {
		diff := math.abs(got[i] - want[i])
		testing.expectf(t, diff <= EPSILON, "vector mismatch at component %d: got %v, want %v (diff %v)", i, got, want, diff, loc = loc)
	}
}
