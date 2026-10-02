package Gameplay

import "../../Engine/Procedural"
import World "../../Engine/World"
import "../Base"
import "../Characters"
import "../Weapons"
import "core:math"
import "core:math/linalg"
import "core:testing"

flat :: proc(data: rawptr, x, z: f32) -> f32 {
	return 0
}

FLAT_GROUND :: World.Ground{height_at = flat}
WALL_BETWEEN := []World.Solid{{center = {0, 1.5, 10}, half_extents = {10, 1.5, 0.5}}}

// An enemy standing still 20 m ahead (+Z) of a player at the origin, facing the player.
duel :: proc(boxes: []World.Solid) -> Battle {
	battle := Battle_Create(FLAT_GROUND, boxes, {0, 0, 0}, 42)
	Battle_Add_Enemy(&battle, .Enemy, {0, 0, 20}, math.PI, nil)
	return battle
}

@(test)
test_five_rifle_hits_to_the_chest_kill_and_only_the_last_one_reports_it :: proc(t: ^testing.T) {
	battle := duel(nil)
	defer Battle_Destroy(&battle)
	origin := [3]f32{0, 1.6, 0}
	chest := Enemy_Chest_Position(battle.enemies[0])
	direction := linalg.normalize(chest - origin)
	damage := Weapons.Weapon_Stats_For(.Rifle).damage
	for shot in 1 ..= 5 {
		result := Resolve_Hitscan(&battle, origin, direction, damage, 300)
		testing.expect_value(t, result.kind, Shot_Kind.Enemy)
		testing.expect_value(t, result.zone, Hit_Zone.Torso)
		testing.expect_value(t, result.killed, shot == 5)
	}
	testing.expect(t, Health_Is_Dead(battle.enemies[0].health))
	testing.expect_value(t, battle.player.kills, 1)
	testing.expect(t, Resolve_Hitscan(&battle, origin, direction, damage, 300).kind != .Enemy) // Shots pass through the corpse.
	testing.expect_value(t, battle.player.kills, 1)
}

@(test)
test_a_headshot_does_triple_damage :: proc(t: ^testing.T) {
	battle := duel(nil)
	defer Battle_Destroy(&battle)
	origin := [3]f32{0, 1.6, 0}
	direction := linalg.normalize(Enemy_Head_Position(battle.enemies[0]) - origin)
	damage := Weapons.Weapon_Stats_For(.Rifle).damage
	first := Resolve_Hitscan(&battle, origin, direction, damage, 300)
	testing.expect_value(t, first.zone, Hit_Zone.Head)
	testing.expect(t, abs(battle.enemies[0].health.maximum - battle.enemies[0].health.current - damage * 3) < 1e-3)
	testing.expect(t, Resolve_Hitscan(&battle, origin, direction, damage, 300).killed) // 66 + 66 > 100.
}

@(test)
test_shots_that_miss_hit_the_world_or_nothing :: proc(t: ^testing.T) {
	battle := duel(nil)
	defer Battle_Destroy(&battle)
	beside := linalg.normalize([3]f32{3, 0, 20} - [3]f32{0, 1.6, 0})
	result := Resolve_Hitscan(&battle, {0, 1.6, 0}, beside, 22, 300)
	testing.expect(t, result.kind != .Enemy)
	testing.expect_value(t, battle.enemies[0].health.current, battle.enemies[0].health.maximum)
}

@(test)
test_a_wall_stops_bullets :: proc(t: ^testing.T) {
	battle := duel(WALL_BETWEEN)
	defer Battle_Destroy(&battle)
	origin := [3]f32{0, 1.6, 0}
	direction := linalg.normalize(Enemy_Chest_Position(battle.enemies[0]) - origin)
	result := Resolve_Hitscan(&battle, origin, direction, 22, 300)
	testing.expect_value(t, result.kind, Shot_Kind.World)
	testing.expect(t, abs(result.point.z - 9.5) < 0.2)
	testing.expect_value(t, battle.enemies[0].health.current, battle.enemies[0].health.maximum)
}

@(test)
test_the_enemy_returns_fire_only_when_it_has_a_clear_line :: proc(t: ^testing.T) {
	open := duel(nil)
	defer Battle_Destroy(&open)
	for _ in 0 ..< 300 do Battle_Update(&open, {}, 1.0 / 30)
	testing.expect(t, open.player.health.current < open.player.health.maximum)
	testing.expect_value(t, open.enemies[0].ai.state, Ai_State.Attack)

	covered := duel(WALL_BETWEEN)
	defer Battle_Destroy(&covered)
	for _ in 0 ..< 300 do Battle_Update(&covered, {}, 1.0 / 30)
	testing.expect_value(t, covered.player.health.current, covered.player.health.maximum)
	testing.expect_value(t, covered.enemies[0].ai.state, Ai_State.Patrol)
}

@(test)
test_explosion_damage_falls_off_with_distance_and_stops_at_the_radius :: proc(t: ^testing.T) {
	battle := Battle_Create(FLAT_GROUND, nil, {200, 0, 200}, 1)
	defer Battle_Destroy(&battle)
	for distance in ([4]f32{0, 3, 5.5, 8}) do Battle_Add_Enemy(&battle, .Rifleman, {distance, 0, 0}, 0, nil)
	Battle_Detonate(&battle, {0, 0.9, 0}, 6, 120)
	damage: [4]f32
	for enemy, index in battle.enemies do damage[index] = enemy.health.maximum - enemy.health.current
	testing.expect(t, damage[0] > damage[1] && damage[1] > damage[2] && damage[2] > 0)
	testing.expect_value(t, damage[3], 0) // Beyond the radius.
	testing.expect(t, battle.enemies[0].health.current <= 5) // At the centre a grenade is all but lethal to a 100-health soldier.
}

@(test)
test_the_player_cannot_walk_through_a_real_barracks :: proc(t: ^testing.T) {
	layout := Base.Layout_Create(5, 90)
	defer Base.Layout_Destroy(&layout)
	barracks := Base.Placement{kind = .Barracks, x = 0, z = 0, yaw_degrees = 0}
	boxes := Base.Placement_Solids(barracks)
	defer delete(boxes)
	for heading in 0 ..< 8 {
		angle := f32(heading) * math.PI / 4
		start := [3]f32{math.cos(angle) * 25, 0, math.sin(angle) * 25}
		battle := Battle_Create(FLAT_GROUND, boxes[:], start, 7)
		battle.player.yaw_radians = math.atan2(-(-start.x), -(-start.z)) // Facing the barracks.
		for _ in 0 ..< 600 do Battle_Update(&battle, Player_Input{move = {0, 1}}, 1.0 / 60)
		position := battle.player.controller.position
		inside := position.x > -9 && position.x < 9 && position.z > -3 && position.z < 3 && position.y < 2.8
		testing.expectf(t, !inside, "walked into the barracks from heading %d: (%.2f, %.2f)", heading, position.x, position.z)
		Battle_Destroy(&battle)
	}
}

@(test)
test_firing_uses_ammunition_and_reloading_refills_it :: proc(t: ^testing.T) {
	battle := Battle_Create(FLAT_GROUND, nil, {0, 0, 0}, 3)
	defer Battle_Destroy(&battle)
	stats := Weapons.Weapon_Stats_For(battle.player.current)
	for _ in 0 ..< 15 do Battle_Update(&battle, Player_Input{fire = true}, 1.0 / 60) // 0.25 s: a few rounds.
	spent := stats.magazine_size - battle.player.weapons[battle.player.current].ammo
	testing.expect(t, spent >= 2 && spent <= 4)
	for _ in 0 ..< 200 do Battle_Update(&battle, Player_Input{reload = true}, 1.0 / 60)
	testing.expect_value(t, battle.player.weapons[battle.player.current].ammo, stats.magazine_size)
}

@(test)
test_a_dead_player_cannot_act_until_respawned :: proc(t: ^testing.T) {
	battle := Battle_Create(FLAT_GROUND, nil, {5, 0, 5}, 3)
	defer Battle_Destroy(&battle)
	Health_Apply_Damage(&battle.player.health, 1000, .Torso)
	before := battle.player.controller.position
	for _ in 0 ..< 60 do Battle_Update(&battle, Player_Input{move = {0, 1}, fire = true}, 1.0 / 60)
	testing.expect_value(t, battle.player.controller.position, before)
	testing.expect_value(t, battle.player.weapons[battle.player.current].ammo, Weapons.Weapon_Stats_For(battle.player.current).magazine_size)
	Battle_Update(&battle, Player_Input{respawn = true}, 1.0 / 60)
	testing.expect(t, !Health_Is_Dead(battle.player.health))
	testing.expect_value(t, battle.player.controller.position, [3]f32{5, 0, 5})
}

@(test)
test_a_battle_is_deterministic_for_a_seed :: proc(t: ^testing.T) {
	healths: [2]f32
	for run in 0 ..< 2 {
		battle := duel(nil)
		for _ in 0 ..< 240 do Battle_Update(&battle, Player_Input{fire = true}, 1.0 / 30)
		healths[run] = battle.player.health.current + battle.enemies[0].health.current
		Battle_Destroy(&battle)
	}
	testing.expect_value(t, healths[0], healths[1])
}

// A player who stops being hit heals after the delay, but not before; being hit again restarts the wait.
@(test)
test_player_health_regenerates_after_a_quiet_spell_not_during_a_fight :: proc(t: ^testing.T) {
	battle := Battle_Create(FLAT_GROUND, nil, {0, 0, 0}, 42)
	defer Battle_Destroy(&battle)
	battle.player.health.current = 50
	for _ in 0 ..< int((PLAYER_REGEN_DELAY_SECONDS - 1) * 30) do Battle_Update(&battle, {}, 1.0 / 30)
	testing.expect_value(t, battle.player.health.current, 50) // Still inside the delay.
	for _ in 0 ..< 3 * 30 do Battle_Update(&battle, {}, 1.0 / 30)
	testing.expect(t, battle.player.health.current > 50 + PLAYER_REGEN_PER_SECOND) // Healing.
	for _ in 0 ..< 60 * 30 do Battle_Update(&battle, {}, 1.0 / 30)
	testing.expect_value(t, battle.player.health.current, battle.player.health.maximum) // Never above the maximum.
}

// 12 enemies in sight must not kill a player in a few seconds: the fight is survivable for at least ten.
@(test)
test_a_single_enemy_needs_many_seconds_to_kill_the_player :: proc(t: ^testing.T) {
	battle := duel(nil)
	defer Battle_Destroy(&battle)
	for _ in 0 ..< 10 * 30 do Battle_Update(&battle, {}, 1.0 / 30)
	testing.expect(t, !Health_Is_Dead(battle.player.health))
}
