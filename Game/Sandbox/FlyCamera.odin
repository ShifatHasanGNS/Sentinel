package Sandbox

import "../../Engine/Platform"
import "core:math"

FLY_SPEED_METERS_PER_SECOND :: 18.0
FLY_BOOST :: 5.0
MOUSE_RADIANS_PER_PIXEL :: 0.0025
PITCH_LIMIT_RADIANS :: 1.55

Fly_Camera :: struct {
	position:      [3]f32,
	yaw_radians:   f32, // Zero looks along -Z (north); positive turns toward -X.
	pitch_radians: f32,
}

Fly_Camera_Forward :: proc(camera: Fly_Camera) -> [3]f32 {
	return {
		-math.sin(camera.yaw_radians) * math.cos(camera.pitch_radians),
		math.sin(camera.pitch_radians),
		-math.cos(camera.yaw_radians) * math.cos(camera.pitch_radians),
	}
}

Fly_Camera_Update :: proc(camera: ^Fly_Camera, input: ^Platform.Input, delta_seconds: f32) {
	camera.yaw_radians -= input.mouse_delta.x * MOUSE_RADIANS_PER_PIXEL
	camera.pitch_radians = clamp(camera.pitch_radians - input.mouse_delta.y * MOUSE_RADIANS_PER_PIXEL, -PITCH_LIMIT_RADIANS, PITCH_LIMIT_RADIANS)
	forward := Fly_Camera_Forward(camera^)
	right := [3]f32{-forward.z, 0, forward.x} / max(math.sqrt(forward.x * forward.x + forward.z * forward.z), 1e-4)
	speed: f32 = FLY_SPEED_METERS_PER_SECOND * (FLY_BOOST if Platform.Input_Key_Down(input, .Left_Shift) else 1)
	move: [3]f32
	if Platform.Input_Key_Down(input, .W) do move += forward
	if Platform.Input_Key_Down(input, .S) do move -= forward
	if Platform.Input_Key_Down(input, .D) do move += right
	if Platform.Input_Key_Down(input, .A) do move -= right
	if Platform.Input_Key_Down(input, .Space) || Platform.Input_Key_Down(input, .E) do move.y += 1
	if Platform.Input_Key_Down(input, .Left_Control) || Platform.Input_Key_Down(input, .Q) do move.y -= 1
	camera.position += move * speed * delta_seconds
}

// A camera at `position` looking at `target`.
Fly_Camera_Looking_At :: proc(position, target: [3]f32) -> Fly_Camera {
	direction := target - position
	horizontal := math.sqrt(direction.x * direction.x + direction.z * direction.z)
	return Fly_Camera{position = position, yaw_radians = math.atan2(-direction.x, -direction.z), pitch_radians = math.atan2(direction.y, horizontal)}
}
