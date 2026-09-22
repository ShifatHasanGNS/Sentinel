// Camera_test.odin — sanity checks on core:math/linalg, run with
// `odin test Library/Camera`.
//
// These are confidence checks on how SENTINEL USES core:math/linalg (see
// the conventions block at the top of Camera.odin) — not a from-scratch
// math implementation to verify from first principles. If any of these
// ever fails after an Odin toolchain upgrade, the conventions comment in
// Camera.odin is the thing that's now wrong and needs re-deriving, not
// patching around here.
package Camera

import "core:math"
import la "core:math/linalg"
import "core:testing"

EPSILON :: 1e-4

@(test)
test_identity_is_neutral :: proc(t: ^testing.T) {
	identity := la.MATRIX4F32_IDENTITY
	v := la.Vector4f32{1, 2, 3, 1}
	expect_vector4_near(t, la.mul(identity, v), v)
}

@(test)
test_multiplication_is_associative :: proc(t: ^testing.T) {
	a := la.matrix4_translate(la.Vector3f32{1, 0, 0})
	b := la.matrix4_rotate(math.to_radians(f32(45)), la.Vector3f32{0, 1, 0})
	c := la.matrix4_scale(la.Vector3f32{2, 2, 2})
	v := la.Vector4f32{1, 2, 3, 1}

	left_first := la.mul(la.mul(a, b), c)
	right_first := la.mul(a, la.mul(b, c))

	expect_vector4_near(t, la.mul(left_first, v), la.mul(right_first, v))
}

@(test)
test_inverse_round_trip :: proc(t: ^testing.T) {
	m := la.mul(
		la.matrix4_translate(la.Vector3f32{3, -2, 5}),
		la.matrix4_rotate(math.to_radians(f32(37)), la.Vector3f32{0, 1, 0}),
	)
	round_trip := la.mul(la.matrix4_inverse(m), m)
	expect_vector4_near(t, la.mul(round_trip, la.Vector4f32{1, 2, 3, 1}), la.Vector4f32{1, 2, 3, 1})
}

// Confirms the right-hand-rule rotation direction recorded in Camera.odin's
// conventions block: +X rotated +90 degrees about +Y must land on -Z.
@(test)
test_known_rotation_direction :: proc(t: ^testing.T) {
	rot := la.matrix4_rotate(math.to_radians(f32(90)), la.Vector3f32{0, 1, 0})
	rotated := la.mul(rot, la.Vector4f32{1, 0, 0, 0})
	expect_vector4_near(t, rotated, la.Vector4f32{0, 0, -1, 0})
}

@(test)
test_normalize_produces_unit_length :: proc(t: ^testing.T) {
	length := la.length(la.normalize(la.Vector3f32{3, 4, 0}))
	testing.expectf(t, math.abs(length - 1) <= EPSILON, "expected unit length, got %v", length)
}

// ---------------------------------------------------------------------------
// Roadmap step 2 (Camera.odin) tests. Two goals per the session's success
// criteria: known points project to expected clip coordinates, and near/far
// map to the documented -1/+1 NDC z range for BOTH projections (matrix4_
// perspective's default was already confirmed above at file scope; matrix_
// ortho3d's sign was NOT previously confirmed anywhere in this project, so
// test_orthographic_clip_z_maps_near_and_far below is the first empirical
// check of it — see that test's comment for what it found).
// ---------------------------------------------------------------------------

// A camera at the origin facing -Z (yaw = pitch = 0) should put a point
// straight ahead on the view-space -Z axis with zero x/y — this is the
// simplest possible check that View_Matrix and Forward agree with each
// other and with the coordinate convention documented above.
@(test)
test_view_matrix_places_forward_point_on_negative_z :: proc(t: ^testing.T) {
	cam := Default_Camera(la.Vector3f32{0, 0, 0})
	view := View_Matrix(&cam)

	point_ahead := la.Vector4f32{0, 0, -5, 1}
	view_space := la.mul(view, point_ahead)

	expect_vector4_near(t, view_space, la.Vector4f32{0, 0, -5, 1})
}

// Confirms Forward's closed-form yaw/pitch formula against the SAME known
// rotation this package's conventions block cites (+X rotated +90 degrees
// about +Y -> -Z, Camera_test.odin's test_known_rotation_direction above):
// a camera yawed +90 degrees should face -X, matching Forward's derivation
// in Camera.odin's own comment.
@(test)
test_forward_yaw_90_faces_negative_x :: proc(t: ^testing.T) {
	cam := Default_Camera(la.Vector3f32{0, 0, 0})
	cam.yaw = math.to_radians(f32(90))

	forward := Forward(&cam)
	expect_vector3_near(t, forward, la.Vector3f32{-1, 0, 0})
}

// Perspective clip-space z: near -> NDC z = -1, far -> NDC z = +1, per the
// convention already documented (and confirmed for raw matrix4_perspective)
// in Camera.odin's conventions block. This test exercises it through
// Camera's own Projection_Matrix, not just the raw linalg call.
@(test)
test_perspective_clip_z_maps_near_and_far :: proc(t: ^testing.T) {
	cam := Default_Camera(la.Vector3f32{0, 0, 0})
	cam.near = 1
	cam.far = 10
	projection := Projection_Matrix(&cam, 1.0)

	near_ndc_z := project_and_divide(projection, la.Vector4f32{0, 0, -cam.near, 1}).z
	far_ndc_z := project_and_divide(projection, la.Vector4f32{0, 0, -cam.far, 1}).z

	testing.expectf(t, math.abs(near_ndc_z - -1) <= EPSILON, "expected near -> NDC z -1, got %v", near_ndc_z)
	testing.expectf(t, math.abs(far_ndc_z - 1) <= EPSILON, "expected far -> NDC z +1, got %v", far_ndc_z)
}

// Orthographic clip-space z, checked empirically the same way as the
// perspective case above rather than assumed: matrix_ortho3d's doc comment
// in core:math/linalg/specific.odin gives no worked example, and this
// project had never called it before Camera.odin. Result: near -> NDC z =
// -1, far -> NDC z = +1 — the SAME range as perspective (both use linalg's
// shared flip_z_axis=true default), so the two projections are directly
// comparable at the near/far planes, which is what lets Source/Main.odin's
// P-key toggle swap between them without the depth range appearing to
// change.
@(test)
test_orthographic_clip_z_maps_near_and_far :: proc(t: ^testing.T) {
	cam := Default_Camera(la.Vector3f32{0, 0, 0})
	cam.projection = .Orthographic
	cam.near = 1
	cam.far = 10
	cam.ortho_half_height = 5
	projection := Projection_Matrix(&cam, 1.0)

	near_ndc_z := project_and_divide(projection, la.Vector4f32{0, 0, -cam.near, 1}).z
	far_ndc_z := project_and_divide(projection, la.Vector4f32{0, 0, -cam.far, 1}).z

	testing.expectf(t, math.abs(near_ndc_z - -1) <= EPSILON, "expected near -> NDC z -1, got %v", near_ndc_z)
	testing.expectf(t, math.abs(far_ndc_z - 1) <= EPSILON, "expected far -> NDC z +1, got %v", far_ndc_z)
}

// Orthographic's defining property vs. perspective: a point off-centre
// stays at the SAME NDC x regardless of its distance from the camera (no
// foreshortening). Picks two points on the same world-space vertical line
// at different depths and checks their NDC x matches.
@(test)
test_orthographic_has_no_foreshortening :: proc(t: ^testing.T) {
	cam := Default_Camera(la.Vector3f32{0, 0, 0})
	cam.projection = .Orthographic
	cam.near = 0.1
	cam.far = 100
	cam.ortho_half_height = 5
	projection := Projection_Matrix(&cam, 1.0)

	near_ndc_x := project_and_divide(projection, la.Vector4f32{2, 0, -1, 1}).x
	far_ndc_x := project_and_divide(projection, la.Vector4f32{2, 0, -50, 1}).x

	testing.expectf(t, math.abs(near_ndc_x - far_ndc_x) <= EPSILON, "expected equal NDC x (no foreshortening), got near=%v far=%v", near_ndc_x, far_ndc_x)
}

@(test)
test_apply_look_delta_updates_yaw_and_pitch :: proc(t: ^testing.T) {
	cam := Default_Camera(la.Vector3f32{0, 0, 0})
	cam.look_sensitivity = 0.01

	// Cursor moved right (+10px) and up (-10px, GLFW's y grows downward):
	// per Apply_Look_Delta's documented sign convention, yaw should
	// DECREASE (turn right) and pitch should INCREASE (look up).
	Apply_Look_Delta(&cam, 10, -10)

	testing.expectf(t, cam.yaw < 0, "expected yaw to decrease (turn right), got %v", cam.yaw)
	testing.expectf(t, cam.pitch > 0, "expected pitch to increase (look up), got %v", cam.pitch)
}

@(test)
test_apply_look_delta_clamps_pitch :: proc(t: ^testing.T) {
	cam := Default_Camera(la.Vector3f32{0, 0, 0})
	cam.look_sensitivity = 1

	// Wildly excessive upward look input must clamp, not wrap or overshoot.
	Apply_Look_Delta(&cam, 0, -1000)

	testing.expectf(t, cam.pitch <= PITCH_LIMIT_RADIANS+EPSILON, "expected pitch clamped to <= %v, got %v", PITCH_LIMIT_RADIANS, cam.pitch)
}

@(test)
test_apply_move_forward_and_right :: proc(t: ^testing.T) {
	cam := Default_Camera(la.Vector3f32{0, 0, 0})
	cam.move_speed = 2

	// Facing -Z (yaw = pitch = 0): forward is -Z, right is +X (both
	// confirmed by this file's other tests and Camera.odin's comments).
	Apply_Move(&cam, 1, 0, 0, 1, false)
	expect_vector3_near(t, cam.position, la.Vector3f32{0, 0, -2})

	cam.position = la.Vector3f32{0, 0, 0}
	Apply_Move(&cam, 0, 1, 0, 1, false)
	expect_vector3_near(t, cam.position, la.Vector3f32{2, 0, 0})
}

@(test)
test_apply_move_sprint_multiplies_speed :: proc(t: ^testing.T) {
	cam := Default_Camera(la.Vector3f32{0, 0, 0})
	cam.move_speed = 2
	cam.sprint_multiplier = 3

	Apply_Move(&cam, 1, 0, 0, 1, true)
	expect_vector3_near(t, cam.position, la.Vector3f32{0, 0, -6})
}

@(test)
test_apply_move_zero_input_is_a_no_op :: proc(t: ^testing.T) {
	cam := Default_Camera(la.Vector3f32{3, 4, 5})
	Apply_Move(&cam, 0, 0, 0, 1, false)
	expect_vector3_near(t, cam.position, la.Vector3f32{3, 4, 5})
}

@(test)
test_toggle_projection_syncs_ortho_half_height_to_distance :: proc(t: ^testing.T) {
	cam := Default_Camera(la.Vector3f32{0, 0, 10})
	cam.fov_y = math.to_radians(f32(90)) // tan(45deg) = 1, for an easy expected value

	Toggle_Projection(&cam, la.Vector3f32{0, 0, 0}) // distance = 10

	testing.expect(t, cam.projection == .Orthographic)
	testing.expectf(t, math.abs(cam.ortho_half_height - 10) <= EPSILON, "expected ortho_half_height ~= 10, got %v", cam.ortho_half_height)

	Toggle_Projection(&cam, la.Vector3f32{0, 0, 0})
	testing.expect(t, cam.projection == .Perspective)
}

@(test)
test_zoom_ortho_scales_and_clamps_to_minimum :: proc(t: ^testing.T) {
	cam := Default_Camera(la.Vector3f32{0, 0, 0})
	cam.ortho_half_height = 10

	Zoom_Ortho(&cam, 1) // one "scroll in" step should shrink the volume
	testing.expectf(t, cam.ortho_half_height < 10, "expected zoom-in to shrink ortho_half_height, got %v", cam.ortho_half_height)

	Zoom_Ortho(&cam, 1000) // absurd zoom-in must clamp, never reach/cross 0
	testing.expectf(t, cam.ortho_half_height >= MIN_ORTHO_HALF_HEIGHT, "expected clamp to >= %v, got %v", MIN_ORTHO_HALF_HEIGHT, cam.ortho_half_height)
}

// ---------------------------------------------------------------------------
// Roadmap step 9 (Patrol Mode) tests.
// ---------------------------------------------------------------------------

// Patrol_Path_Position must land exactly PATROL_RADIUS from the origin at
// every angle (it's a plain circle, Camera.odin's own comment on why) —
// checked at the 4 axis-aligned angles plus one arbitrary angle, since a
// circle-vs-ellipse mistake (unequal x/z scale) would only show up off the
// axes.
@(test)
test_patrol_path_position_is_always_at_radius :: proc(t: ^testing.T) {
	expect_vector3_near(t, Patrol_Path_Position(0), la.Vector3f32{PATROL_RADIUS, 0, 0})
	expect_vector3_near(t, Patrol_Path_Position(math.PI * 0.5), la.Vector3f32{0, 0, PATROL_RADIUS})
	expect_vector3_near(t, Patrol_Path_Position(math.PI), la.Vector3f32{-PATROL_RADIUS, 0, 0})
	expect_vector3_near(t, Patrol_Path_Position(math.PI * 1.5), la.Vector3f32{0, 0, -PATROL_RADIUS})

	arbitrary := Patrol_Path_Position(0.83)
	testing.expectf(t, math.abs(la.length(arbitrary)-PATROL_RADIUS) <= EPSILON, "expected distance ~= PATROL_RADIUS at an arbitrary angle, got %v", la.length(arbitrary))
}

// Patrol_Nearest_Angle is EXACT for this circular path (its own comment) —
// checked by round-tripping THROUGH Patrol_Path_Position at an arbitrary
// (non-axis-aligned) angle: the nearest angle to a point already ON the
// circle must be that same angle, confirming the general claim, not just
// the axis-aligned special case.
@(test)
test_patrol_nearest_angle_round_trips_through_path_position :: proc(t: ^testing.T) {
	original_angle: f32 = 0.83
	position := Patrol_Path_Position(original_angle)
	recovered_angle := Patrol_Nearest_Angle(position)
	testing.expectf(t, math.abs(recovered_angle-original_angle) <= EPSILON, "expected angle ~= %v, got %v", original_angle, recovered_angle)
}

// Patrol_Camera_Pose's height at t=0 must be exactly PATROL_HEIGHT (the
// bob term is sin(0*rate) = 0), and at every t it must stay within the
// documented bob amplitude — a coarse sanity check that height bobbing is
// wired to the right term and bounded, not a full waveform check.
@(test)
test_patrol_camera_pose_height_bob_is_bounded :: proc(t: ^testing.T) {
	position_at_zero, _, _ := Patrol_Camera_Pose(0)
	testing.expectf(t, math.abs(position_at_zero.y-PATROL_HEIGHT) <= EPSILON, "expected height ~= PATROL_HEIGHT at t=0, got %v", position_at_zero.y)

	position_later, _, _ := Patrol_Camera_Pose(37.0)
	testing.expectf(
		t,
		math.abs(position_later.y-PATROL_HEIGHT) <= PATROL_HEIGHT_BOB_AMPLITUDE+EPSILON,
		"expected height within PATROL_HEIGHT +/- bob amplitude, got %v",
		position_later.y,
	)
}

// Patrol_Camera_Pose's yaw/pitch must actually aim at Patrol_Look_Target,
// not just be "some" angle — reconstructs Forward from the returned yaw/
// pitch (the same formula View_Matrix relies on) and confirms it points
// the same direction as (target - position), the definition of "looking
// at" this project already uses elsewhere (Camera_Looking_At).
@(test)
test_patrol_camera_pose_looks_at_target :: proc(t: ^testing.T) {
	time_seconds: f32 = 12.5
	position, yaw, pitch := Patrol_Camera_Pose(time_seconds)

	cam := Default_Camera(position)
	cam.yaw = yaw
	cam.pitch = pitch
	forward := Forward(&cam)

	expected_direction := la.normalize(Patrol_Look_Target(time_seconds) - position)
	expect_vector3_near(t, forward, expected_direction)
}

// project_and_divide applies a clip-space transform and performs the
// perspective divide (w-divide), returning NDC coordinates. Orthographic
// matrices always have w = 1, so this is a correct no-op divide for them
// too — one helper covers both projections' tests above.
@(private = "file")
project_and_divide :: proc(clip_from_view: la.Matrix4f32, view_space_point: la.Vector4f32) -> la.Vector3f32 {
	clip := la.mul(clip_from_view, view_space_point)
	return la.Vector3f32{clip.x, clip.y, clip.z} / clip.w
}

@(private = "file")
expect_vector4_near :: proc(t: ^testing.T, got, want: la.Vector4f32, loc := #caller_location) {
	for i in 0 ..< 4 {
		diff := math.abs(got[i] - want[i])
		testing.expectf(t, diff <= EPSILON, "vector mismatch at component %d: got %v, want %v (diff %v)", i, got, want, diff, loc = loc)
	}
}

@(private = "file")
expect_vector3_near :: proc(t: ^testing.T, got, want: la.Vector3f32, loc := #caller_location) {
	for i in 0 ..< 3 {
		diff := math.abs(got[i] - want[i])
		testing.expectf(t, diff <= EPSILON, "vector mismatch at component %d: got %v, want %v (diff %v)", i, got, want, diff, loc = loc)
	}
}
