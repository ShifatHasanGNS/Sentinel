package Gameplay

import "core:math"

CROUCH_VISIBILITY :: 0.55
STILL_VISIBILITY :: 0.8
WALK_VISIBILITY :: 1.0
SPRINT_VISIBILITY :: 1.25
STILL_SPEED_MAX :: 0.3 // Slower than this counts as standing still.
FOOTSTEP_RADIUS_SPRINT :: 18.0
FOOTSTEP_RADIUS_WALK :: 9.0
FOOTSTEP_RADIUS_CROUCH_WALK :: 3.0
SHOT_RADIUS_METERS :: 70.0
CROUCH_SPEED_FACTOR :: 0.5

// How easy the player is to spot, as a multiplier on how far enemies and cameras see: crouching and keeping still both help,
// running hurts.
Visibility :: proc(crouching: bool, speed: f32) -> f32 {
	movement: f32 = WALK_VISIBILITY
	switch {
	case speed <= STILL_SPEED_MAX: movement = STILL_VISIBILITY
	case speed > WALK_SPEED * 1.2: movement = SPRINT_VISIBILITY
	}
	return movement * (CROUCH_VISIBILITY if crouching else 1)
}

// How far the player's own noise carries: a shot is loud, footsteps scale with how fast and how softly they fall.
Noise_Radius :: proc(crouching: bool, speed: f32, firing: bool) -> f32 {
	if firing do return SHOT_RADIUS_METERS
	switch {
	case speed <= STILL_SPEED_MAX: return 0
	case crouching: return FOOTSTEP_RADIUS_CROUCH_WALK
	case speed > WALK_SPEED * 1.2: return FOOTSTEP_RADIUS_SPRINT
	}
	return FOOTSTEP_RADIUS_WALK
}

Player_Visibility :: proc(player: Player) -> f32 {
	speed := horizontal_speed(player)
	return Visibility(player.controller.crouching, speed)
}

Player_Noise_Radius :: proc(player: Player, firing: bool) -> f32 {
	return Noise_Radius(player.controller.crouching, horizontal_speed(player), firing)
}

@(private = "file")
horizontal_speed :: proc(player: Player) -> f32 {
	return math.sqrt(player.controller.velocity.x * player.controller.velocity.x + player.controller.velocity.z * player.controller.velocity.z)
}
