package Gameplay

import "core:math"
import "core:math/linalg"
import "core:testing"

STEP :: 1.0 / 30

WAYPOINTS := [3][3]f32{{0, 0, 0}, {10, 0, 0}, {10, 0, 10}}

run :: proc(ai: ^Enemy_Ai, senses: Ai_Senses, seconds: f32) -> (last: Ai_Output) {
	for _ in 0 ..< int(seconds / STEP) {
		last = Enemy_Ai_Update(ai, senses, WAYPOINTS[:], STEP)
		ai.position += last.move_direction * last.speed * STEP
	}
	return
}

blind :: proc() -> Ai_Senses {
	return Ai_Senses{player_position = {100, 0, 100}}
}

seen :: proc(player: [3]f32) -> Ai_Senses {
	return Ai_Senses{player_position = player, sees_player = true}
}

@(test)
test_vision_needs_range_field_of_view_and_a_clear_line :: proc(t: ^testing.T) {
	eye, forward := [3]f32{0, 1.6, 0}, [3]f32{0, 0, 1}
	testing.expect(t, Can_See(eye, forward, {0, 1.6, 30}, true)) // Ahead, in range.
	testing.expect(t, !Can_See(eye, forward, {0, 1.6, 30}, false)) // A wall in between.
	testing.expect(t, !Can_See(eye, forward, {0, 1.6, -30}, true)) // Behind.
	testing.expect(t, !Can_See(eye, forward, {30, 1.6, 5}, true)) // Far to the side, outside the cone.
	testing.expect(t, !Can_See(eye, forward, {0, 1.6, SIGHT_RANGE_METERS + 5}, true)) // Too far.
	edge := linalg.normalize([3]f32{math.sin(math.to_radians(f32(FIELD_OF_VIEW_DEGREES) / 2 - 3)), 0, math.cos(math.to_radians(f32(FIELD_OF_VIEW_DEGREES) / 2 - 3))})
	testing.expect(t, Can_See(eye, forward, eye + edge * 20, true)) // Just inside the cone's edge.
}

@(test)
test_an_unalerted_enemy_patrols_its_waypoints_in_a_loop :: proc(t: ^testing.T) {
	ai := Enemy_Ai_Create({0, 0, 0}, 1)
	visited: [3]bool
	for _ in 0 ..< 1200 {
		output := Enemy_Ai_Update(&ai, blind(), WAYPOINTS[:], STEP)
		ai.position += output.move_direction * output.speed * STEP
		for waypoint, index in WAYPOINTS do if linalg.length(ai.position - waypoint) < ARRIVAL_RADIUS_METERS do visited[index] = true
		testing.expect_value(t, ai.state, Ai_State.Patrol)
		testing.expect(t, !output.shoot)
		if output.speed > 0 do testing.expect(t, abs(output.speed - PATROL_SPEED) < 1e-5)
	}
	testing.expect(t, visited[0] && visited[1] && visited[2])
}

@(test)
test_seeing_the_player_alerts_then_after_a_reaction_delay_attacks :: proc(t: ^testing.T) {
	ai := Enemy_Ai_Create({0, 0, 0}, 3)
	player := [3]f32{0, 0, 20}
	output := Enemy_Ai_Update(&ai, seen(player), WAYPOINTS[:], STEP)
	testing.expect_value(t, ai.state, Ai_State.Alert)
	testing.expect(t, output.speed == 0 && !output.shoot) // Frozen and silent while it reacts.
	elapsed: f32
	for ai.state == .Alert && elapsed < 2 {
		output = Enemy_Ai_Update(&ai, seen(player), WAYPOINTS[:], STEP)
		elapsed += STEP
		if ai.state == .Alert do testing.expect(t, !output.shoot && output.speed == 0) // No shot while still reacting.
	}
	testing.expect(t, elapsed >= REACTION_SECONDS_MIN - STEP && elapsed <= REACTION_SECONDS_MAX + 2 * STEP)
	testing.expect_value(t, ai.state, Ai_State.Attack) // In range with the player in view: straight to attacking.
}

@(test)
test_a_distant_player_is_chased_until_in_range_then_shot_at :: proc(t: ^testing.T) {
	ai := Enemy_Ai_Create({0, 0, 0}, 5)
	player := [3]f32{0, 0, ATTACK_RANGE_METERS + 40}
	run(&ai, seen(player), 1.5)
	testing.expect_value(t, ai.state, Ai_State.Chase)
	start_z := ai.position.z
	run(&ai, seen(player), 2)
	testing.expect(t, ai.position.z > start_z + 2 * CHASE_SPEED * 0.8) // Closing in at chase speed.
	for _ in 0 ..< 600 {
		output := Enemy_Ai_Update(&ai, seen(player), WAYPOINTS[:], STEP)
		ai.position += output.move_direction * output.speed * STEP
		if ai.state == .Attack {
			testing.expect(t, output.speed == 0 && output.shoot)
			break
		}
	}
	testing.expect_value(t, ai.state, Ai_State.Attack)
	testing.expect(t, linalg.length(player - ai.position) <= ATTACK_RANGE_METERS + 1)
}

@(test)
test_losing_sight_leads_to_the_last_known_spot_then_a_search_then_patrol :: proc(t: ^testing.T) {
	ai := Enemy_Ai_Create({0, 0, 0}, 7)
	player := [3]f32{0, 0, 60}
	run(&ai, seen(player), 3)
	testing.expect_value(t, ai.state, Ai_State.Chase)
	for _ in 0 ..< int(LOSE_TRACK_SECONDS * 2 / STEP) {
		output := Enemy_Ai_Update(&ai, blind(), WAYPOINTS[:], STEP)
		ai.position += output.move_direction * output.speed * STEP
		testing.expect(t, !output.shoot) // Never shoots at what it cannot see.
		if ai.state == .Search do break
	}
	testing.expect_value(t, ai.state, Ai_State.Search)
	run(&ai, blind(), SEARCH_SECONDS + 1)
	testing.expect_value(t, ai.state, Ai_State.Patrol)
}

@(test)
test_a_heard_shot_sends_the_enemy_to_investigate_without_ever_shooting :: proc(t: ^testing.T) {
	ai := Enemy_Ai_Create({0, 0, 0}, 9)
	shot_at := [3]f32{30, 0, 0}
	senses := Ai_Senses{player_position = {500, 0, 0}, heard_shot = true, shot_position = shot_at}
	Enemy_Ai_Update(&ai, senses, WAYPOINTS[:], STEP)
	testing.expect_value(t, ai.state, Ai_State.Alert)
	for _ in 0 ..< 300 {
		output := Enemy_Ai_Update(&ai, blind(), WAYPOINTS[:], STEP)
		ai.position += output.move_direction * output.speed * STEP
		testing.expect(t, !output.shoot)
	}
	testing.expect(t, ai.position.x > 8) // Headed for the sound.
}

@(test)
test_the_dead_do_nothing_whatever_they_sense :: proc(t: ^testing.T) {
	ai := Enemy_Ai_Create({0, 0, 0}, 11)
	run(&ai, seen({0, 0, 10}), 2)
	Enemy_Ai_Kill(&ai)
	for _ in 0 ..< 100 {
		output := Enemy_Ai_Update(&ai, seen({0, 0, 5}), WAYPOINTS[:], STEP)
		testing.expect(t, output.speed == 0 && !output.shoot && ai.state == .Dead)
	}
}

// Property: over many pseudo-random sensory frames, a shot is only ever fired in the Attack state with the player in view.
@(test)
test_it_never_shoots_unless_attacking_with_the_player_in_view :: proc(t: ^testing.T) {
	ai := Enemy_Ai_Create({0, 0, 0}, 13)
	player: [3]f32
	for frame in 0 ..< 3000 {
		roll := math.mod(f32(frame) * 0.6180339, 1)
		player = {math.sin(f32(frame) * 0.01) * 50, 0, math.cos(f32(frame) * 0.013) * 50}
		senses := Ai_Senses{player_position = player, sees_player = roll < 0.4, heard_shot = roll > 0.93, shot_position = player}
		output := Enemy_Ai_Update(&ai, senses, WAYPOINTS[:], STEP)
		ai.position += output.move_direction * output.speed * STEP
		if output.shoot do testing.expect(t, ai.state == .Attack && senses.sees_player)
	}
}

@(test)
test_reaction_time_is_bounded_deterministic_and_varies_by_seed :: proc(t: ^testing.T) {
	first, again, other := Enemy_Ai_Create({}, 21), Enemy_Ai_Create({}, 21), Enemy_Ai_Create({}, 22)
	testing.expect_value(t, first.reaction_seconds, again.reaction_seconds)
	testing.expect(t, first.reaction_seconds != other.reaction_seconds)
	for seed in 0 ..< u32(100) {
		reaction := Enemy_Ai_Create({}, seed).reaction_seconds
		testing.expect(t, reaction >= REACTION_SECONDS_MIN && reaction <= REACTION_SECONDS_MAX)
	}
}
