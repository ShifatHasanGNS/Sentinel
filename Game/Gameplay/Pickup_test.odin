package Gameplay

import "../Base"
import World "../../Engine/World"
import "../Weapons"
import "core:math"
import "core:testing"

// Seam: Battle_Update collecting pickups, and the ammunition a killed soldier drops.

@(test)
test_walking_over_ammo_adds_two_rifle_magazines_once :: proc(t: ^testing.T) {
	battle := Battle_Create(FLAT_GROUND, nil, {0, 0, 0}, 1)
	defer Battle_Destroy(&battle)
	Battle_Add_Pickup(&battle, .Ammo, {0, 0, -3})
	before := battle.player.weapons[.Rifle].reserve
	Battle_Update(&battle, {}, 1.0 / 30)
	testing.expect_value(t, battle.player.weapons[.Rifle].reserve, before) // Not reached yet.
	for _ in 0 ..< 30 do Battle_Update(&battle, Player_Input{move = {0, 1}}, 1.0 / 30) // Walk 4 m along -Z, over it.
	testing.expect_value(t, battle.player.weapons[.Rifle].reserve, before + 60)
	testing.expect(t, battle.pickups[0].taken)
	for _ in 0 ..< 30 do Battle_Update(&battle, Player_Input{move = {0, -1}}, 1.0 / 30) // Back over the spot: nothing more.
	testing.expect_value(t, battle.player.weapons[.Rifle].reserve, before + 60)
}

@(test)
test_a_medkit_waits_until_it_is_needed :: proc(t: ^testing.T) {
	battle := Battle_Create(FLAT_GROUND, nil, {0, 0, 0}, 1)
	defer Battle_Destroy(&battle)
	Battle_Add_Pickup(&battle, .Medkit, {0, 0, 0})
	Battle_Update(&battle, {}, 1.0 / 30)
	testing.expect(t, !battle.pickups[0].taken) // Full health: left on the floor.
	battle.player.health.current = 30
	Battle_Update(&battle, {}, 1.0 / 30)
	testing.expect(t, battle.pickups[0].taken)
	testing.expect(t, battle.player.health.current >= 80)
}

@(test)
test_a_killed_soldier_drops_ammunition :: proc(t: ^testing.T) {
	battle := duel(nil)
	defer Battle_Destroy(&battle)
	for _ in 0 ..< 10 do Resolve_Hitscan(&battle, {0, 1.5, 0}, {0, 0, 1}, 50, 100)
	testing.expect(t, !Enemy_Is_Alive(battle.enemies[0]))
	testing.expect_value(t, len(battle.pickups), 2) // His spare magazines and his weapon.
	testing.expect_value(t, battle.pickups[0].kind, Pickup_Kind.Ammo)
	testing.expect_value(t, battle.pickups[1].kind, Pickup_Kind.Weapon)
}

@(test)
test_a_sniper_drops_sniper_rifle_ammunition :: proc(t: ^testing.T) {
	battle := Battle_Create(FLAT_GROUND, nil, {0, 0, 0}, 1)
	defer Battle_Destroy(&battle)
	Battle_Add_Enemy(&battle, .Sniper, {0, 0, 20}, 3.14159, nil)
	for _ in 0 ..< 10 do Resolve_Hitscan(&battle, {0, 1.5, 0}, {0, 0, 1}, 50, 100)
	testing.expect_value(t, battle.pickups[0].weapon, Weapons.Weapon_Kind.Sniper_Rifle)
}

// Seam: Battle_Update with a thrown grenade. It must not explode on touching the ground; it bounces, settles near where it landed,
// and goes off when the fuse runs out.
@(test)
test_a_grenade_bounces_and_waits_for_its_fuse :: proc(t: ^testing.T) {
	battle := Battle_Create(FLAT_GROUND, nil, {0, 0, 0}, 1)
	defer Battle_Destroy(&battle)
	append(&battle.projectiles, Projectile_Entity{body = {position = {0, 1.5, 0}, velocity = {0, 2, -8}}, kind = .Grenade})
	for _ in 0 ..< 45 do Battle_Update(&battle, {}, 1.0 / 30) // 1.5 s: it has hit the ground by now.
	testing.expect_value(t, len(battle.projectiles), 1)
	testing.expect(t, battle.projectiles[0].position.y >= 0 && battle.projectiles[0].position.y < 0.5)
	for _ in 0 ..< 45 do Battle_Update(&battle, {}, 1.0 / 30)
	testing.expect_value(t, len(battle.projectiles), 0) // Exploded at 2.5 s.
	exploded := false
	for effect in battle.effects do if effect.kind == .Explosion do exploded = true
	testing.expect(t, exploded)
}

// Seam: Battle_Update with the real base. A player standing 3 m in front of a watchtower's ladder, facing the tower and pushing
// forward as a person would, climbs to the lookout.
@(test)
test_the_player_climbs_a_real_watchtower_ladder_by_walking_forward :: proc(t: ^testing.T) {
	layout := Base.Layout_Create(5, 90)
	defer Base.Layout_Destroy(&layout)
	solids := Base.Layout_Solids(layout, 0)
	defer delete(solids)
	ladders := Base.Layout_Ladders(layout, 0)
	defer delete(ladders)
	for ladder in ladders {
		outward := World.rotate_about_y({0, 0, 1}, ladder.yaw_radians)
		start := ladder.center + outward * 3
		battle := Battle_Create(FLAT_GROUND, solids[:], {start.x, 0, start.z}, 1)
		for solid in ladders do append(&battle.collision.ladders, solid)
		// Face the ladder: the player's forward is (-sin yaw, -cos yaw), which must equal -outward.
		battle.player.yaw_radians = math.atan2(outward.x, outward.z)
		for _ in 0 ..< 60 * 8 do Battle_Update(&battle, Player_Input{move = {0, 1}}, 1.0 / 60)
		testing.expectf(t, battle.player.controller.position.y > 6.0, "player stopped at height %.2f at (%.1f, %.1f)", battle.player.controller.position.y, battle.player.controller.position.x, battle.player.controller.position.z)
		Battle_Destroy(&battle)
	}
}

// Seam: Battle_Update on a ladder. However the player faces (even with their back to it, or sideways) forward climbs and back descends.
@(test)
test_on_a_ladder_forward_is_up_whichever_way_the_player_faces :: proc(t: ^testing.T) {
	for facing in ([3]f32{0, math.PI / 2, math.PI}) { // Toward the ladder, sideways, away from it.
		battle := Battle_Create(FLAT_GROUND, nil, {0, 0, 1}, 1)
		defer Battle_Destroy(&battle)
		append(&battle.collision.boxes, World.Box_Solid({-2, 0, -4}, {2, 3, 0}))
		append(&battle.collision.ladders, World.Solid{center = {0, 1.6, 0.15}, half_extents = {0.3, 1.6, 0.1}})
		battle.player.yaw_radians = facing // Yaw 0 looks along -Z, toward the wall.
		for _ in 0 ..< 60 * 2 do Battle_Update(&battle, Player_Input{move = {0, 1}}, 1.0 / 60)
		testing.expectf(t, battle.player.controller.position.y > 1.5, "facing %.2f: only reached %.2f", facing, battle.player.controller.position.y)
		for _ in 0 ..< 60 * 3 do Battle_Update(&battle, Player_Input{move = {0, -1}}, 1.0 / 60)
		testing.expectf(t, battle.player.controller.position.y < 0.2, "facing %.2f: did not climb back down (%.2f)", facing, battle.player.controller.position.y)
	}
}
