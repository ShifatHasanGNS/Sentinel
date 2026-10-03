package Gameplay

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
	testing.expect_value(t, len(battle.pickups), 1)
	testing.expect_value(t, battle.pickups[0].kind, Pickup_Kind.Ammo)
}
