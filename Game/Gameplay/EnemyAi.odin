package Gameplay

import "../../Engine/Procedural"
import "core:math"
import la "core:math/linalg"

PATROL_SPEED :: 1.4
CHASE_SPEED :: 3.6
ATTACK_RANGE_METERS :: 35.0
SIGHT_RANGE_METERS :: 80.0
FIELD_OF_VIEW_DEGREES :: 110.0
ARRIVAL_RADIUS_METERS :: 1.0
REACTION_SECONDS_MIN :: 0.25
REACTION_SECONDS_MAX :: 0.75
SEARCH_SECONDS :: 3.0
LOSE_TRACK_SECONDS :: 5.0
ATTACK_RELEASE_FACTOR :: 1.2 // Attack ends only when the player is this much farther than the attack range: no flicker at the edge.

Ai_State :: enum {
	Patrol,
	Alert, // Has noticed something and is reacting: frozen, facing it, not yet shooting.
	Chase,
	Attack,
	Search, // At the last known spot, looking around.
	Dead,
}

Enemy_Ai :: struct {
	state:            Ai_State,
	state_seconds:    f32,
	unseen_seconds:   f32,
	position:         [3]f32,
	heading_radians:  f32,
	waypoint_index:   int,
	last_known:       [3]f32, // Where the player (or a shot) was last noticed.
	reaction_seconds: f32, // How long this enemy takes to react; varies by seed so a squad does not act in unison.
}

// What the enemy perceives this frame. sees_player must already include the line-of-sight raycast (see Can_See).
Ai_Senses :: struct {
	player_position: [3]f32,
	sees_player:     bool,
	heard_shot:      bool,
	shot_position:   [3]f32,
}

Ai_Output :: struct {
	move_direction: [3]f32, // Unit vector, or zero when standing.
	speed:          f32,
	face_direction: [3]f32,
	shoot:          bool,
}

Enemy_Ai_Create :: proc(position: [3]f32, seed: u32) -> Enemy_Ai {
	unit := Procedural.Hash_To_Unit_Float(Procedural.Hash_U32(seed))
	return Enemy_Ai{position = position, reaction_seconds = math.lerp(f32(REACTION_SECONDS_MIN), f32(REACTION_SECONDS_MAX), unit)}
}

Enemy_Ai_Kill :: proc(ai: ^Enemy_Ai) {
	ai.state = .Dead
}

// Something at `position` just hurt or startled the enemy: an unaware one turns to it; one already fighting keeps fighting.
Enemy_Ai_Notice :: proc(ai: ^Enemy_Ai, position: [3]f32) {
	if ai.state != .Patrol && ai.state != .Search do return
	ai.last_known = position
	ai.state = .Alert
	ai.state_seconds = 0
}

// The geometric part of sight: within range, within the cone about the facing direction, and nothing in the way.
Can_See :: proc(eye, forward, target: [3]f32, line_is_clear: bool) -> bool {
	to_target := target - eye
	distance := la.length(to_target)
	if !line_is_clear || distance > SIGHT_RANGE_METERS do return false
	if distance < 1e-4 do return true
	return la.dot(to_target / distance, la.normalize(forward)) >= math.cos(math.to_radians(f32(FIELD_OF_VIEW_DEGREES) / 2))
}

Enemy_Ai_Update :: proc(ai: ^Enemy_Ai, senses: Ai_Senses, waypoints: []([3]f32), delta_seconds: f32) -> (output: Ai_Output) {
	ai.state_seconds += delta_seconds
	if ai.state == .Dead do return
	ai.unseen_seconds = 0 if senses.sees_player else ai.unseen_seconds + delta_seconds
	if senses.sees_player do ai.last_known = senses.player_position
	// A transition hands the frame to the new state at once, so the output always belongs to the state the enemy ends up in.
	for _ in 0 ..< 2 {
		before := ai.state
		output = run_state(ai, senses, waypoints)
		if ai.state == before do break
	}
	if la.length(output.face_direction) > 1e-4 do ai.heading_radians = math.atan2(output.face_direction.x, output.face_direction.z)
	return output
}

@(private = "file")
run_state :: proc(ai: ^Enemy_Ai, senses: Ai_Senses, waypoints: []([3]f32)) -> Ai_Output {
	switch ai.state {
	case .Patrol: return patrol(ai, senses, waypoints)
	case .Alert: return alert(ai, senses)
	case .Chase: return chase(ai, senses)
	case .Attack: return attack(ai, senses)
	case .Search: return search(ai, senses)
	case .Dead: return {}
	}
	unreachable()
}

@(private = "file")
enter :: proc(ai: ^Enemy_Ai, state: Ai_State) {
	ai.state = state
	ai.state_seconds = 0
}

@(private = "file")
horizontal_direction :: proc(from, to: [3]f32) -> [3]f32 {
	direction := [3]f32{to.x - from.x, 0, to.z - from.z}
	if la.length(direction) < 1e-4 do return {}
	return la.normalize(direction)
}

@(private = "file")
horizontal_distance :: proc(a, b: [3]f32) -> f32 {
	return la.length([2]f32{a.x - b.x, a.z - b.z})
}

@(private = "file")
patrol :: proc(ai: ^Enemy_Ai, senses: Ai_Senses, waypoints: []([3]f32)) -> Ai_Output {
	if senses.sees_player {
		enter(ai, .Alert)
		return Ai_Output{face_direction = horizontal_direction(ai.position, senses.player_position)}
	}
	if senses.heard_shot {
		ai.last_known = senses.shot_position
		enter(ai, .Alert)
		return Ai_Output{face_direction = horizontal_direction(ai.position, senses.shot_position)}
	}
	if len(waypoints) == 0 do return {}
	if horizontal_distance(ai.position, waypoints[ai.waypoint_index]) < ARRIVAL_RADIUS_METERS do ai.waypoint_index = (ai.waypoint_index + 1) % len(waypoints)
	direction := horizontal_direction(ai.position, waypoints[ai.waypoint_index])
	return Ai_Output{move_direction = direction, speed = PATROL_SPEED, face_direction = direction}
}

// Standing frozen is the player's window to act: the enemy has noticed but not yet responded.
@(private = "file")
alert :: proc(ai: ^Enemy_Ai, senses: Ai_Senses) -> Ai_Output {
	facing := horizontal_direction(ai.position, ai.last_known)
	if ai.state_seconds >= ai.reaction_seconds {
		in_range := horizontal_distance(ai.position, senses.player_position) <= ATTACK_RANGE_METERS
		enter(ai, .Attack if senses.sees_player && in_range else .Chase)
	}
	return Ai_Output{face_direction = facing}
}

@(private = "file")
chase :: proc(ai: ^Enemy_Ai, senses: Ai_Senses) -> Ai_Output {
	if senses.sees_player && horizontal_distance(ai.position, senses.player_position) <= ATTACK_RANGE_METERS {
		enter(ai, .Attack)
		return Ai_Output{face_direction = horizontal_direction(ai.position, senses.player_position)}
	}
	arrived := horizontal_distance(ai.position, ai.last_known) < ARRIVAL_RADIUS_METERS
	if !senses.sees_player && (arrived || ai.unseen_seconds >= LOSE_TRACK_SECONDS) {
		enter(ai, .Search)
		return {}
	}
	direction := horizontal_direction(ai.position, ai.last_known)
	return Ai_Output{move_direction = direction, speed = CHASE_SPEED, face_direction = direction}
}

// Stand and shoot while the player is in view and in range; anything less sends the enemy back to chasing.
@(private = "file")
attack :: proc(ai: ^Enemy_Ai, senses: Ai_Senses) -> Ai_Output {
	too_far := horizontal_distance(ai.position, senses.player_position) > ATTACK_RANGE_METERS * ATTACK_RELEASE_FACTOR
	if !senses.sees_player || too_far {
		enter(ai, .Chase)
		return Ai_Output{face_direction = horizontal_direction(ai.position, ai.last_known)}
	}
	return Ai_Output{face_direction = horizontal_direction(ai.position, senses.player_position), shoot = true}
}

@(private = "file")
search :: proc(ai: ^Enemy_Ai, senses: Ai_Senses) -> Ai_Output {
	if senses.sees_player {
		enter(ai, .Alert)
		return Ai_Output{face_direction = horizontal_direction(ai.position, senses.player_position)}
	}
	if ai.state_seconds >= SEARCH_SECONDS do enter(ai, .Patrol)
	return {}
}
