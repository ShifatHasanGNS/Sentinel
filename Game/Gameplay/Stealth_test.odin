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
	Battle_Add_Enemy(&battle, .Enemy, {0, 0, -(FOOTSTEP_RADIUS_WALK + 26)}, math.PI, nil) // Beyond both the noise radius and the first soldier's shout.
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

// Seam: Battle_Update with the silenced pistol. A normal shot alerts a soldier 40 m away; a suppressed one does not, until he is close.
@(test)
test_a_silenced_shot_is_heard_only_from_close_by :: proc(t: ^testing.T) {
	for silenced in ([2]bool{false, true}) {
		battle := Battle_Create(FLAT_GROUND, nil, {0, 0, 0}, 5)
		Battle_Add_Enemy(&battle, .Enemy, {0, 0, 40}, 0, nil) // Facing away (+Z), 40 m behind the player's back... player faces -Z.
		battle.enemies[0].character.heading_radians = 0
		battle.player.current = .Silenced_Pistol if silenced else .Pistol
		battle.player.yaw_radians = math.PI // Face +Z toward him: he is in front but facing away, 40 m: beyond sight range scale.
		for _ in 0 ..< 5 do Battle_Update(&battle, Player_Input{fire = true}, 1.0 / 30)
		if silenced do testing.expect_value(t, battle.enemies[0].ai.state, Ai_State.Patrol)
		else do testing.expect_value(t, battle.enemies[0].ai.state, Ai_State.Alert)
		Battle_Destroy(&battle)
	}
}

@(test)
test_a_silenced_shot_leaves_no_muzzle_flash :: proc(t: ^testing.T) {
	battle := Battle_Create(FLAT_GROUND, nil, {0, 0, 0}, 5)
	defer Battle_Destroy(&battle)
	battle.player.current = .Silenced_Pistol
	Battle_Update(&battle, Player_Input{fire = true}, 1.0 / 30)
	flashes := 0
	for effect in battle.effects do if effect.kind == .Muzzle_Flash {
		flashes += 1
		testing.expect(t, effect.silenced)
	}
	testing.expect_value(t, flashes, 1)
}

// Seam: Battle_Update with several soldiers. One who spots the player calls out; only squad-mates within the shout radius react.
@(test)
test_a_soldier_who_spots_the_player_alerts_nearby_squad_mates_only :: proc(t: ^testing.T) {
	battle := Battle_Create(FLAT_GROUND, nil, {0, 0, 0}, 5)
	defer Battle_Destroy(&battle)
	Battle_Add_Enemy(&battle, .Enemy, {0, 0, 20}, math.PI, nil) // Faces the player: sees him.
	Battle_Add_Enemy(&battle, .Enemy, {12, 0, 24}, 0, nil) // Squad-mate within 22 m of the first, looking away from the player.
	Battle_Add_Enemy(&battle, .Enemy, {80, 0, 24}, 0, nil) // Far away.
	for _ in 0 ..< 3 do Battle_Update(&battle, {}, 1.0 / 30)
	testing.expect_value(t, battle.enemies[0].ai.state, Ai_State.Alert)
	testing.expect_value(t, battle.enemies[1].ai.state, Ai_State.Alert)
	testing.expect_value(t, battle.enemies[2].ai.state, Ai_State.Patrol)
}

// A patrolling soldier who walks up on a body raises the alarm, once; one facing the other way does not.
@(test)
test_bodies_are_discovered_by_soldiers_who_can_see_them_and_only_once :: proc(t: ^testing.T) {
	battle := Battle_Create(FLAT_GROUND, nil, {0, 0, -100}, 5)
	defer Battle_Destroy(&battle)
	Battle_Add_Enemy(&battle, .Enemy, {0, 0, 0}, 0, nil) // The victim.
	Battle_Add_Enemy(&battle, .Enemy, {0, 0, 8}, math.PI, nil) // 8 m away, facing the victim.
	Battle_Add_Enemy(&battle, .Enemy, {0, 0, -8}, math.PI, nil) // 8 m away on the other side, facing away (-Z).
	Enemy_Ai_Kill(&battle.enemies[0].ai)
	battle.enemies[0].health.current = 0
	Battle_Update(&battle, {}, 1.0 / 30)
	testing.expect_value(t, battle.enemies[1].ai.state, Ai_State.Alert)
	testing.expect(t, battle.enemies[0].body_found)
	testing.expect_value(t, battle.enemies[2].ai.state, Ai_State.Alert) // Reached by the discoverer's shout (within 22 m)...
	far_battle := Battle_Create(FLAT_GROUND, nil, {0, 0, -100}, 5)
	defer Battle_Destroy(&far_battle)
	Battle_Add_Enemy(&far_battle, .Enemy, {0, 0, 0}, 0, nil)
	Battle_Add_Enemy(&far_battle, .Enemy, {0, 0, 30}, math.PI, nil) // Too far to make out a body.
	far_battle.enemies[0].health.current = 0
	Enemy_Ai_Kill(&far_battle.enemies[0].ai)
	Battle_Update(&far_battle, {}, 1.0 / 30)
	testing.expect_value(t, far_battle.enemies[1].ai.state, Ai_State.Patrol)
}
