package Mission

import "core:math"
import la "core:math/linalg"

CAMERA_RANGE_METERS :: f32(38.0)
CAMERA_HALF_FOV_RADIANS :: f32(0.42) // A cone about 48 degrees wide.
CAMERA_PITCH_RADIANS :: f32(-0.3) // Cameras look down at the yard.
CAMERA_SWEEP_RADIANS :: f32(0.9)
CAMERA_SWEEP_RATE :: f32(0.5) // Radians of the sweep's phase per second.
CAMERA_DETECT_SECONDS :: 0.7 // Seen this long without a break and the alarm goes.
CAMERA_DETECT_DECAY_FACTOR :: 2.0
ALARM_SECONDS :: 25.0

// A fixed camera that sweeps back and forth. Heading is (sin yaw, cos yaw), the vehicle convention.
Security_Camera :: struct {
	position:        [3]f32,
	center_yaw:      f32,
	sweep_phase:     f32, // Offsets cameras from each other.
	disabled:        bool,
	detect_seconds:  f32,
}

Camera_Yaw :: proc(camera: Security_Camera, seconds: f32) -> f32 {
	return camera.center_yaw + math.sin(seconds * CAMERA_SWEEP_RATE + camera.sweep_phase) * CAMERA_SWEEP_RADIANS
}

// The unit vector the lens points along at time `seconds`.
Camera_Direction :: proc(camera: Security_Camera, seconds: f32) -> [3]f32 {
	yaw := Camera_Yaw(camera, seconds)
	return la.normalize([3]f32{math.sin(yaw) * math.cos(CAMERA_PITCH_RADIANS), math.sin(CAMERA_PITCH_RADIANS), math.cos(yaw) * math.cos(CAMERA_PITCH_RADIANS)})
}

// Whether the camera sees `target` now: working, within range, inside its cone and with a clear line (the caller's raycast).
// `range_scale` shrinks the range for a target that is hard to see (a crouching player).
Camera_Sees :: proc(camera: Security_Camera, seconds: f32, target: [3]f32, line_is_clear: bool, range_scale: f32 = 1) -> bool {
	if camera.disabled || !line_is_clear do return false
	offset := target - camera.position
	distance := la.length(offset)
	if distance > CAMERA_RANGE_METERS * range_scale do return false
	if distance < 1e-3 do return true
	return la.dot(offset / distance, Camera_Direction(camera, seconds)) >= math.cos(CAMERA_HALF_FOV_RADIANS)
}

// Builds suspicion while the camera sees something and drains it when it does not; true at the moment it reaches the alarm threshold.
Camera_Update :: proc(camera: ^Security_Camera, sees: bool, delta_seconds: f32) -> (alarm: bool) {
	if camera.disabled {
		camera.detect_seconds = 0
		return false
	}
	if !sees {
		camera.detect_seconds = max(camera.detect_seconds - delta_seconds * CAMERA_DETECT_DECAY_FACTOR, 0)
		return false
	}
	camera.detect_seconds += delta_seconds
	if camera.detect_seconds < CAMERA_DETECT_SECONDS do return false
	camera.detect_seconds = 0
	return true
}

// The base-wide alarm: counts down; raising it again restarts the count rather than stacking.
Alarm :: struct {
	seconds_left: f32,
}

Alarm_Raise :: proc(alarm: ^Alarm) {
	alarm.seconds_left = ALARM_SECONDS
}

Alarm_Update :: proc(alarm: ^Alarm, delta_seconds: f32) {
	alarm.seconds_left = max(alarm.seconds_left - delta_seconds, 0)
}

Alarm_Active :: proc(alarm: Alarm) -> bool {
	return alarm.seconds_left > 0
}
