package Gameplay

import "core:testing"

// Seams: Target_Damage, and Battle's hitscan and explosions against targets.

@(test)
test_a_target_reports_its_destruction_exactly_once :: proc(t: ^testing.T) {
	target := Target_Create({0, 0, 0}, 1, 100)
	testing.expect(t, !Target_Damage(&target, 60))
	testing.expect_value(t, target.health, 40)
	testing.expect(t, Target_Damage(&target, 60)) // The hit that finishes it.
	testing.expect(t, target.destroyed)
	testing.expect(t, !Target_Damage(&target, 60)) // Further hits report nothing.
	testing.expect(t, !Target_Damage(&target, 0))
	fresh := Target_Create({0, 0, 0}, 1, 100)
	testing.expect(t, !Target_Damage(&fresh, -50)) // Negative damage never heals or destroys.
	testing.expect_value(t, fresh.health, 100)
}

@(test)
test_bullets_wear_a_target_down_and_a_wall_in_front_protects_it :: proc(t: ^testing.T) {
	battle := Battle_Create(FLAT_GROUND, nil, {0, 0, 0}, 3)
	defer Battle_Destroy(&battle)
	index := Battle_Add_Target(&battle, {0, 1.5, 30}, 2, 100)
	shots := 0
	for !battle.targets[index].destroyed && shots < 100 {
		result := Resolve_Hitscan(&battle, {0, 1.5, 0}, {0, 0, 1}, 22, 100)
		testing.expect_value(t, result.kind, Shot_Kind.Target)
		shots += 1
	}
	testing.expect_value(t, shots, 5) // 5 x 22 = 110 >= 100.
	covered := Battle_Create(FLAT_GROUND, WALL_BETWEEN, {0, 0, 0}, 3)
	defer Battle_Destroy(&covered)
	covered_index := Battle_Add_Target(&covered, {0, 1.5, 30}, 2, 100)
	result := Resolve_Hitscan(&covered, {0, 1.5, 0}, {0, 0, 1}, 22, 100)
	testing.expect_value(t, result.kind, Shot_Kind.World)
	testing.expect_value(t, covered.targets[covered_index].health, 100)
}

@(test)
test_an_explosion_damages_a_target_by_distance_to_its_surface :: proc(t: ^testing.T) {
	battle := Battle_Create(FLAT_GROUND, nil, {0, 0, -100}, 3)
	defer Battle_Destroy(&battle)
	near := Battle_Add_Target(&battle, {0, 0, 0}, 2, 1000)
	far := Battle_Add_Target(&battle, {0, 0, 20}, 2, 1000)
	Battle_Detonate(&battle, {0, 0, 4}, 5, 100) // 2 m from the near target's surface; the far one is out of reach.
	testing.expect(t, battle.targets[near].health < 1000)
	testing.expect_value(t, battle.targets[far].health, 1000)
	damage := 1000 - battle.targets[near].health
	// Falloff (1 - 2/5)^2 = 0.36, times the structure multiplier.
	testing.expect(t, abs(damage - 100 * 0.36 * TARGET_BLAST_MULTIPLIER) < 0.01)
}

@(test)
test_a_destroyed_target_is_ignored_by_later_shots :: proc(t: ^testing.T) {
	battle := Battle_Create(FLAT_GROUND, nil, {0, 0, 0}, 3)
	defer Battle_Destroy(&battle)
	index := Battle_Add_Target(&battle, {0, 1.5, 10}, 1, 10)
	Resolve_Hitscan(&battle, {0, 1.5, 0}, {0, 0, 1}, 50, 100)
	testing.expect(t, battle.targets[index].destroyed)
	result := Resolve_Hitscan(&battle, {0, 1.5, 0}, {0, 0, 1}, 50, 100)
	testing.expect(t, result.kind != .Target)
}
