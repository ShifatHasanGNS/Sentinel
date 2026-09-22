// Camera_test.odin — run with `odin test Library/Camera`.
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

@(test)
test_view_matrix_places_forward_point_on_negative_z :: proc(t: ^testing.T) {
	cam := Default_Camera(la.Vector3f32{0, 0, 0})
	view := View_Matrix(&cam)

	point_ahead := la.Vector4f32{0, 0, -5, 1}
	view_space := la.mul(view, point_ahead)

	expect_vector4_near(t, view_space, la.Vector4f32{0, 0, -5, 1})
}

@(test)
test_forward_yaw_90_faces_negative_x :: proc(t: ^testing.T) {
	cam := Default_Camera(la.Vector3f32{0, 0, 0})
	cam.yaw = math.to_radians(f32(90))

	forward := Forward(&cam)
	expect_vector3_near(t, forward, la.Vector3f32{-1, 0, 0})
}

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

	Apply_Look_Delta(&cam, 10, -10)

	testing.expectf(t, cam.yaw < 0, "expected yaw to decrease (turn right), got %v", cam.yaw)
	testing.expectf(t, cam.pitch > 0, "expected pitch to increase (look up), got %v", cam.pitch)
}

@(test)
test_apply_look_delta_clamps_pitch :: proc(t: ^testing.T) {
	cam := Default_Camera(la.Vector3f32{0, 0, 0})
	cam.look_sensitivity = 1

	Apply_Look_Delta(&cam, 0, -1000)

	testing.expectf(t, cam.pitch <= PITCH_LIMIT_RADIANS+EPSILON, "expected pitch clamped to <= %v, got %v", PITCH_LIMIT_RADIANS, cam.pitch)
}

@(test)
test_apply_move_forward_and_right :: proc(t: ^testing.T) {
	cam := Default_Camera(la.Vector3f32{0, 0, 0})
	cam.move_speed = 2

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
	cam.fov_y = math.to_radians(f32(90))

	Toggle_Projection(&cam, la.Vector3f32{0, 0, 0})

	testing.expect(t, cam.projection == .Orthographic)
	testing.expectf(t, math.abs(cam.ortho_half_height - 10) <= EPSILON, "expected ortho_half_height ~= 10, got %v", cam.ortho_half_height)

	Toggle_Projection(&cam, la.Vector3f32{0, 0, 0})
	testing.expect(t, cam.projection == .Perspective)
}

@(test)
test_zoom_ortho_scales_and_clamps_to_minimum :: proc(t: ^testing.T) {
	cam := Default_Camera(la.Vector3f32{0, 0, 0})
	cam.ortho_half_height = 10

	Zoom_Ortho(&cam, 1)
	testing.expectf(t, cam.ortho_half_height < 10, "expected zoom-in to shrink ortho_half_height, got %v", cam.ortho_half_height)

	Zoom_Ortho(&cam, 1000)
	testing.expectf(t, cam.ortho_half_height >= MIN_ORTHO_HALF_HEIGHT, "expected clamp to >= %v, got %v", MIN_ORTHO_HALF_HEIGHT, cam.ortho_half_height)
}

@(test)
test_patrol_path_position_is_always_at_radius :: proc(t: ^testing.T) {
	expect_vector3_near(t, Patrol_Path_Position(0), la.Vector3f32{PATROL_RADIUS, 0, 0})
	expect_vector3_near(t, Patrol_Path_Position(math.PI * 0.5), la.Vector3f32{0, 0, PATROL_RADIUS})
	expect_vector3_near(t, Patrol_Path_Position(math.PI), la.Vector3f32{-PATROL_RADIUS, 0, 0})
	expect_vector3_near(t, Patrol_Path_Position(math.PI * 1.5), la.Vector3f32{0, 0, -PATROL_RADIUS})

	arbitrary := Patrol_Path_Position(0.83)
	testing.expectf(t, math.abs(la.length(arbitrary)-PATROL_RADIUS) <= EPSILON, "expected distance ~= PATROL_RADIUS at an arbitrary angle, got %v", la.length(arbitrary))
}

@(test)
test_patrol_nearest_angle_round_trips_through_path_position :: proc(t: ^testing.T) {
	original_angle: f32 = 0.83
	position := Patrol_Path_Position(original_angle)
	recovered_angle := Patrol_Nearest_Angle(position)
	testing.expectf(t, math.abs(recovered_angle-original_angle) <= EPSILON, "expected angle ~= %v, got %v", original_angle, recovered_angle)
}

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
