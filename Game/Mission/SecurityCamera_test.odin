package Mission

import "core:math"
import "core:testing"

// Seam: Camera_Sees, Camera_Update, and the Alarm.

// A camera at head height facing +Z (yaw 0), not sweeping at time 0.
test_camera :: proc() -> Security_Camera {
	return Security_Camera{position = {0, 3, 0}, center_yaw = 0}
}

@(test)
test_a_camera_sees_what_is_in_range_inside_the_cone_and_in_the_clear :: proc(t: ^testing.T) {
	camera := test_camera()
	ahead := [3]f32{0, 1, 20} // 20 m ahead, 2 m below: a shallow dip within the cone of the 0.3 rad down-look.
	testing.expect(t, Camera_Sees(camera, 0, ahead, true))
	testing.expect(t, !Camera_Sees(camera, 0, ahead, false)) // A wall in the way.
	testing.expect(t, !Camera_Sees(camera, 0, {0, 1, CAMERA_RANGE_METERS + 3}, true)) // Out of range.
	testing.expect(t, !Camera_Sees(camera, 0, {0, 1, -20}, true)) // Behind it.
	testing.expect(t, !Camera_Sees(camera, 0, {20, 1, 5}, true)) // Far off to the side.
	testing.expect(t, !Camera_Sees(camera, 0, {0, 40, 5}, true)) // Straight up.
	testing.expect(t, Camera_Sees(camera, 0, {0, 1, CAMERA_RANGE_METERS * 0.6 - 1}, true, 0.6)) // Crouching: shorter range, still inside it.
	testing.expect(t, !Camera_Sees(camera, 0, {0, 1, CAMERA_RANGE_METERS * 0.6 + 4}, true, 0.6))
	camera.disabled = true
	testing.expect(t, !Camera_Sees(camera, 0, ahead, true))
}

// The sweep turns the cone: a point 25 degrees to one side is seen only around the time the camera points that way.
@(test)
test_the_sweep_moves_the_cone_across_the_yard :: proc(t: ^testing.T) {
	camera := test_camera()
	side := [3]f32{20 * math.sin(f32(0.8)), 1.5, 20 * math.cos(f32(0.8))}
	seen_at_some_time, unseen_at_some_time := false, false
	for step in 0 ..< 200 {
		if Camera_Sees(camera, f32(step) * 0.1, side, true) do seen_at_some_time = true
		else do unseen_at_some_time = true
	}
	testing.expect(t, seen_at_some_time && unseen_at_some_time)
	testing.expect(t, abs(Camera_Yaw(camera, 0)) < 1e-6)
	testing.expect(t, abs(Camera_Yaw(camera, math.PI / 2 / CAMERA_SWEEP_RATE) - CAMERA_SWEEP_RADIANS) < 1e-4)
}

@(test)
test_the_alarm_needs_an_unbroken_look_and_a_disabled_camera_never_raises_it :: proc(t: ^testing.T) {
	camera := test_camera()
	for _ in 0 ..< int(CAMERA_DETECT_SECONDS * 60) - 5 do testing.expect(t, !Camera_Update(&camera, true, 1.0 / 60))
	for _ in 0 ..< 60 do Camera_Update(&camera, false, 1.0 / 60) // Looks away: suspicion drains.
	testing.expect_value(t, camera.detect_seconds, 0)
	raised := false
	for _ in 0 ..< int(CAMERA_DETECT_SECONDS * 60) + 3 {
		if Camera_Update(&camera, true, 1.0 / 60) {
			raised = true
			break
		}
	}
	testing.expect(t, raised)
	testing.expect_value(t, camera.detect_seconds, 0) // Reset after raising.
	camera.disabled = true
	for _ in 0 ..< 300 do testing.expect(t, !Camera_Update(&camera, true, 1.0 / 60))
}

@(test)
test_the_alarm_counts_down_and_restarts_when_raised_again :: proc(t: ^testing.T) {
	alarm: Alarm
	testing.expect(t, !Alarm_Active(alarm))
	Alarm_Raise(&alarm)
	testing.expect(t, Alarm_Active(alarm))
	Alarm_Update(&alarm, ALARM_SECONDS - 1)
	testing.expect(t, Alarm_Active(alarm))
	Alarm_Raise(&alarm)
	testing.expect_value(t, alarm.seconds_left, ALARM_SECONDS) // Restarted, not stacked.
	Alarm_Update(&alarm, ALARM_SECONDS + 5)
	testing.expect(t, !Alarm_Active(alarm))
	testing.expect_value(t, alarm.seconds_left, 0)
}
