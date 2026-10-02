package Gameplay

import "core:math"
import "core:testing"

// Seam: Visibility and Noise_Radius, and how the battle uses them.

@(test)
test_crouching_and_keeping_still_help_and_running_hurts_visibility :: proc(t: ^testing.T) {
	testing.expect_value(t, Visibility(false, WALK_SPEED), 1.0)
	testing.expect(t, Visibility(true, WALK_SPEED * CROUCH_SPEED_FACTOR) < Visibility(false, WALK_SPEED))
	testing.expect(t, Visibility(false, 0) < Visibility(false, WALK_SPEED)) // Standing still.
	testing.expect(t, Visibility(false, SPRINT_SPEED) > Visibility(false, WALK_SPEED))
	testing.expect(t, Visibility(true, 0) < Visibility(true, 2)) // Even crouched, moving shows more than still.
	testing.expect(t, Visibility(true, 0) < 0.5 && Visibility(false, SPRINT_SPEED) > 1.2)
}

@(test)
test_noise_grows_with_speed_and_shots_are_loudest :: proc(t: ^testing.T) {
	testing.expect_value(t, Noise_Radius(false, 0, false), 0) // Silent when still.
	crouch_walk := Noise_Radius(true, 2, false)
	walk := Noise_Radius(false, WALK_SPEED, false)
	sprint := Noise_Radius(false, SPRINT_SPEED, false)
	testing.expect(t, 0 < crouch_walk && crouch_walk < walk && walk < sprint)
	testing.expect(t, sprint < Noise_Radius(false, 0, true)) // A shot carries farthest, even from a standing start.
	testing.expect_value(t, Noise_Radius(true, 0, true), SHOT_RADIUS_METERS)
}

// Walking, the player is seen at 70% of the sight range; crouched, not.
@(test)
test_a_crouched_player_slips_past_what_a_standing_one_cannot :: proc(t: ^testing.T) {
	eye, forward := [3]f32{0, 1.6, 0}, [3]f32{0, 0, 1}
	far := [3]f32{0, 1.6, SIGHT_RANGE_METERS * 0.7}
	testing.expect(t, Can_See(eye, forward, far, true, Visibility(false, WALK_SPEED))) // Walking: seen at 70% of sight range.
	testing.expect(t, !Can_See(eye, forward, far, true, Visibility(true, 2))) // Crouched: not.
}

// In the battle: an enemy hears footsteps within the noise radius, not beyond it, and not when the player is still.
@(test)
test_enemies_hear_footsteps_only_within_the_noise_radius :: proc(t: ^testing.T) {
	battle := Battle_Create(FLAT_GROUND, nil, {0, 0, 0}, 5)
	defer Battle_Destroy(&battle)
	Battle_Add_Enemy(&battle, .Enemy, {0, 0, -(FOOTSTEP_RADIUS_WALK - 2)}, math.PI, nil) // The player walks toward them from behind, so only hearing can notice.
	Battle_Add_Enemy(&battle, .Enemy, {0, 0, -(FOOTSTEP_RADIUS_WALK + 6)}, math.PI, nil)
	for &enemy in battle.enemies do enemy.character.heading_radians = math.PI // Facing -Z, away from the player at the origin behind them.
	for _ in 0 ..< 5 do Battle_Update(&battle, Player_Input{}, 1.0 / 30) // Standing still: silent.
	testing.expect_value(t, battle.enemies[0].ai.state, Ai_State.Patrol)
	for _ in 0 ..< 3 do Battle_Update(&battle, Player_Input{move = {0, 1}}, 1.0 / 30) // Walking.
	testing.expect_value(t, battle.enemies[0].ai.state, Ai_State.Alert)
	testing.expect_value(t, battle.enemies[1].ai.state, Ai_State.Patrol)
}

@(test)
test_crouching_slows_the_player_and_lowers_the_eye :: proc(t: ^testing.T) {
	battle := Battle_Create(FLAT_GROUND, nil, {0, 0, 0}, 5)
	defer Battle_Destroy(&battle)
	standing_eye := Player_Eye(battle.player).y
	for _ in 0 ..< 30 do Battle_Update(&battle, Player_Input{crouch = true, move = {0, 1}, sprint = true}, 1.0 / 30)
	testing.expect(t, battle.player.controller.crouching)
	testing.expect(t, Player_Eye(battle.player).y < standing_eye - 0.5)
	travelled := -battle.player.controller.position.z // Facing -Z.
	testing.expect(t, abs(travelled - WALK_SPEED * CROUCH_SPEED_FACTOR) < 0.2) // One second at half walking speed, sprint ignored.
}
