package Gameplay

import "../Base"
import World "../../Engine/World"
import "core:math"
import "core:testing"

// Seam: Battle_Update with the real base's watchtowers and their ladders: a player pushing forward, as a person would.

tower_battle :: proc(layout: Base.Layout, solids: []World.Solid, ladders: []World.Solid, ladder: World.Solid, distance: f32) -> Battle {
	outward := World.rotate_about_y({0, 0, 1}, ladder.yaw_radians)
	start := ladder.center + outward * distance
	battle := Battle_Create(FLAT_GROUND, solids, {start.x, 0, start.z}, 1)
	for other in ladders do append(&battle.collision.ladders, other)
	battle.player.yaw_radians = math.atan2(outward.x, outward.z) // The player's forward is (-sin yaw, -cos yaw): into the wall.
	return battle
}

@(test)
test_every_watchtower_ladder_is_climbed_to_its_lookout_and_back_down :: proc(t: ^testing.T) {
	layout := Base.Layout_Create(5, 90)
	defer Base.Layout_Destroy(&layout)
	solids := Base.Layout_Solids(layout, 0)
	defer delete(solids)
	ladders := Base.Layout_Ladders(layout, 0)
	defer delete(ladders)
	testing.expect_value(t, len(ladders), 4)
	for ladder, index in ladders {
		battle := tower_battle(layout, solids[:], ladders[:], ladder, 3)
		defer Battle_Destroy(&battle)
		seconds: f32
		for seconds < 20 && !(battle.player.controller.on_ground && battle.player.controller.position.y > 6.1) {
			Battle_Update(&battle, Player_Input{move = {0, 1}}, 1.0 / 60)
			seconds += 1.0 / 60
		}
		position := battle.player.controller.position
		testing.expectf(t, battle.player.controller.on_ground && abs(position.y - 6.2) < 0.08, "ladder %d: ended at height %.2f after %.1f s", index, position.y, seconds)
		testing.expectf(t, seconds > 5 && seconds < 14, "ladder %d: the climb took %.1f s", index, seconds) // 6.3 m at about 1.1 m/s plus the transitions.
		testing.expect(t, !battle.player.on_ladder)
		// Turn around at the top, face out over the edge, take hold with E, and climb down.
		battle.player.yaw_radians += math.PI
		for _ in 0 ..< 40 do Battle_Update(&battle, Player_Input{}, 1.0 / 60) // The hold-off after topping out passes.
		Battle_Update(&battle, Player_Input{use = true}, 1.0 / 60)
		testing.expect(t, battle.player.on_ladder)
		down: f32
		for down < 20 && !(battle.player.controller.on_ground && battle.player.controller.position.y < 0.3) {
			Battle_Update(&battle, Player_Input{move = {0, -1}}, 1.0 / 60) // Back is down on a ladder.
			down += 1.0 / 60
		}
		testing.expectf(t, battle.player.controller.on_ground && battle.player.controller.position.y < 0.3, "ladder %d: ended at height %.2f going down", index, battle.player.controller.position.y)
	}
}

@(test)
test_a_climber_cannot_shoot_or_reload_but_can_again_on_the_lookout :: proc(t: ^testing.T) {
	layout := Base.Layout_Create(5, 90)
	defer Base.Layout_Destroy(&layout)
	solids := Base.Layout_Solids(layout, 0)
	defer delete(solids)
	ladders := Base.Layout_Ladders(layout, 0)
	defer delete(ladders)
	battle := tower_battle(layout, solids[:], ladders[:], ladders[0], 1.0)
	defer Battle_Destroy(&battle)
	ammo := battle.player.weapons[battle.player.current].ammo
	for _ in 0 ..< 60 do Battle_Update(&battle, Player_Input{move = {0, 1}, fire = true}, 1.0 / 60)
	testing.expect(t, battle.player.on_ladder)
	testing.expect_value(t, battle.player.weapons[battle.player.current].ammo, ammo)
}

@(test)
test_walking_past_a_ladder_does_not_grab_it :: proc(t: ^testing.T) {
	layout := Base.Layout_Create(5, 90)
	defer Base.Layout_Destroy(&layout)
	solids := Base.Layout_Solids(layout, 0)
	defer delete(solids)
	ladders := Base.Layout_Ladders(layout, 0)
	defer delete(ladders)
	ladder := ladders[0]
	battle := tower_battle(layout, solids[:], ladders[:], ladder, 2.5)
	defer Battle_Destroy(&battle)
	battle.player.yaw_radians += math.PI / 2 // Facing sideways along the tower: strafing and walking past.
	for _ in 0 ..< 180 do Battle_Update(&battle, Player_Input{move = {0, 1}}, 1.0 / 60)
	testing.expect(t, !battle.player.on_ladder && battle.player.controller.position.y < 0.01)
}
