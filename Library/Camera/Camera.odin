// Package Camera — free-fly camera, projections, and the Patrol path.
package Camera

import "core:math"
import la "core:math/linalg"

// Conventions: right-handed, +Y up, view looks down -Z; column-vectors
// (p' = M*p); Matrix4f32 is column-major (matches GLSL, no transpose
// needed); angles in radians internally; rotation follows the right-hand
// rule; NDC z in [-1, +1] for both projections.

WORLD_UP :: la.Vector3f32{0, 1, 0}

// avoids Right() degenerating to zero at +/-90 degrees
PITCH_LIMIT_RADIANS :: 89.0 * math.PI / 180.0

// floor so the ortho volume can't collapse to/through zero
MIN_ORTHO_HALF_HEIGHT :: 0.1

// <1 so scrolling forward (GLFW positive y-offset) zooms in
ORTHO_ZOOM_FACTOR_PER_SCROLL_STEP :: 0.9

Projection_Mode :: enum {
	Perspective,
	Orthographic,
}

Camera :: struct {
	position:          la.Vector3f32,
	yaw:               f32, // radians; forward = (0, 0, -1) at yaw = pitch = 0
	pitch:             f32, // radians; clamped to +/- PITCH_LIMIT_RADIANS
	fov_y:             f32, // radians
	near:              f32,
	far:               f32,
	projection:        Projection_Mode,
	ortho_half_height: f32, // half-width = this * aspect
	move_speed:        f32, // world units/second
	sprint_multiplier: f32,
	look_sensitivity:  f32, // radians of yaw/pitch per pixel
}

DEFAULT_FOV_Y_DEGREES :: 45.0
DEFAULT_NEAR :: 0.1
DEFAULT_FAR :: 100.0
DEFAULT_ORTHO_HALF_HEIGHT :: 5.0
DEFAULT_MOVE_SPEED :: 4.0
DEFAULT_SPRINT_MULTIPLIER :: 3.0
DEFAULT_LOOK_SENSITIVITY :: 0.0025

Default_Camera :: proc(position: la.Vector3f32) -> Camera {
	return Camera {
		position          = position,
		yaw               = 0,
		pitch             = 0,
		fov_y             = math.to_radians(f32(DEFAULT_FOV_Y_DEGREES)),
		near              = DEFAULT_NEAR,
		far               = DEFAULT_FAR,
		projection        = .Perspective,
		ortho_half_height = DEFAULT_ORTHO_HALF_HEIGHT,
		move_speed        = DEFAULT_MOVE_SPEED,
		sprint_multiplier = DEFAULT_SPRINT_MULTIPLIER,
		look_sensitivity  = DEFAULT_LOOK_SENSITIVITY,
	}
}

Camera_Looking_At :: proc(position, target: la.Vector3f32) -> Camera {
	cam := Default_Camera(position)
	cam.yaw, cam.pitch = yaw_pitch_looking_at(position, target)
	return cam
}

// closed-form inverse of Forward's own formula
@(private = "file")
yaw_pitch_looking_at :: proc(position, target: la.Vector3f32) -> (yaw, pitch: f32) {
	direction := la.normalize(target - position)
	pitch = math.asin(clamp(direction.y, -1, 1))
	yaw = math.atan2(-direction.x, -direction.z)
	return
}

// closed form for R_y(yaw) * R_x(pitch) * (0, 0, -1)
Forward :: proc(cam: ^Camera) -> la.Vector3f32 {
	cos_pitch := math.cos(cam.pitch)
	return la.Vector3f32 {
		-cos_pitch * math.sin(cam.yaw),
		math.sin(cam.pitch),
		-cos_pitch * math.cos(cam.yaw),
	}
}

Right :: proc(cam: ^Camera) -> la.Vector3f32 {
	return la.normalize(la.cross(Forward(cam), WORLD_UP))
}

Up :: proc(cam: ^Camera) -> la.Vector3f32 {
	return la.cross(Right(cam), Forward(cam))
}

View_Matrix :: proc(cam: ^Camera) -> la.Matrix4f32 {
	return la.matrix4_look_at(cam.position, cam.position + Forward(cam), WORLD_UP)
}

Projection_Matrix :: proc(cam: ^Camera, aspect: f32) -> la.Matrix4f32 {
	switch cam.projection {
	case .Perspective:
		return la.matrix4_perspective(cam.fov_y, aspect, cam.near, cam.far)
	case .Orthographic:
		half_height := cam.ortho_half_height
		half_width := half_height * aspect
		return la.matrix_ortho3d(-half_width, half_width, -half_height, half_height, cam.near, cam.far)
	}
	unreachable()
}

// GLFW cursor y grows downward, so the y term is negated to make "mouse up" pitch up
Apply_Look_Delta :: proc(cam: ^Camera, cursor_delta_x, cursor_delta_y: f32) {
	cam.yaw -= cursor_delta_x * cam.look_sensitivity
	cam.pitch -= cursor_delta_y * cam.look_sensitivity
	cam.pitch = clamp(cam.pitch, -PITCH_LIMIT_RADIANS, PITCH_LIMIT_RADIANS)
}

Apply_Move :: proc(cam: ^Camera, move_forward, move_right, move_up, dt_seconds: f32, sprint: bool) {
	if move_forward == 0 && move_right == 0 && move_up == 0 do return

	direction := Forward(cam) * move_forward + Right(cam) * move_right + WORLD_UP * move_up
	direction = la.normalize(direction)

	speed := cam.move_speed
	if sprint do speed *= cam.sprint_multiplier

	cam.position = cam.position + direction * speed * dt_seconds
}

// perspective -> orthographic syncs ortho_half_height to the current view distance
Toggle_Projection :: proc(cam: ^Camera, focus: la.Vector3f32) {
	switch cam.projection {
	case .Perspective:
		distance := la.length(focus - cam.position)
		cam.ortho_half_height = distance * math.tan(cam.fov_y * 0.5)
		cam.projection = .Orthographic
	case .Orthographic:
		cam.projection = .Perspective
	}
}

Zoom_Ortho :: proc(cam: ^Camera, scroll_delta_y: f32) {
	cam.ortho_half_height *= math.pow(f32(ORTHO_ZOOM_FACTOR_PER_SCROLL_STEP), scroll_delta_y)
	cam.ortho_half_height = max(cam.ortho_half_height, MIN_ORTHO_HALF_HEIGHT)
}

// clears the fence's own corner distance (14*sqrt(2) ~= 19.8) at every angle
PATROL_RADIUS :: 24.0

PATROL_HEIGHT :: 9.0
PATROL_HEIGHT_BOB_AMPLITUDE :: 1.2
PATROL_HEIGHT_BOB_RATE :: 0.3 // rad/s

PATROL_ANGULAR_SPEED :: 0.0698 // rad/s, ~90s per lap

PATROL_LOOK_TARGET_DRIFT_RADIUS :: 2.5
// non-integer rate ratio so the drift path never repeats
PATROL_LOOK_TARGET_DRIFT_RATE_X :: 0.11
PATROL_LOOK_TARGET_DRIFT_RATE_Z :: 0.077

Patrol_Path_Position :: proc(angle: f32) -> la.Vector3f32 {
	return la.Vector3f32{PATROL_RADIUS * math.cos(angle), 0, PATROL_RADIUS * math.sin(angle)}
}

Patrol_Look_Target :: proc(time_seconds: f32) -> la.Vector3f32 {
	return la.Vector3f32{
		math.cos(time_seconds * PATROL_LOOK_TARGET_DRIFT_RATE_X) * PATROL_LOOK_TARGET_DRIFT_RADIUS,
		0,
		math.sin(time_seconds * PATROL_LOOK_TARGET_DRIFT_RATE_Z) * PATROL_LOOK_TARGET_DRIFT_RADIUS,
	}
}

Patrol_Camera_Pose :: proc(time_seconds: f32) -> (position: la.Vector3f32, yaw, pitch: f32) {
	angle := time_seconds * PATROL_ANGULAR_SPEED
	path_position := Patrol_Path_Position(angle)
	height := PATROL_HEIGHT + math.sin(time_seconds*PATROL_HEIGHT_BOB_RATE)*PATROL_HEIGHT_BOB_AMPLITUDE
	position = la.Vector3f32{path_position.x, height, path_position.z}
	yaw, pitch = yaw_pitch_looking_at(position, Patrol_Look_Target(time_seconds))
	return
}

// exact for a circle centred at the origin: nearest point lies on the ray through it
Patrol_Nearest_Angle :: proc(world_position: la.Vector3f32) -> f32 {
	return math.atan2(world_position.z, world_position.x)
}
