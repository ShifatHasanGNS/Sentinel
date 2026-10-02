package Gameplay

import "core:testing"

@(test)
test_damage_depends_on_where_the_hit_lands :: proc(t: ^testing.T) {
	head, torso, limb := Health_Create(1000), Health_Create(1000), Health_Create(1000)
	Health_Apply_Damage(&head, 20, .Head)
	Health_Apply_Damage(&torso, 20, .Torso)
	Health_Apply_Damage(&limb, 20, .Limb)
	testing.expect(t, abs(1000 - head.current - 60) < 1e-4) // Headshots do triple damage.
	testing.expect(t, abs(1000 - torso.current - 20) < 1e-4)
	testing.expect(t, abs(1000 - limb.current - 12) < 1e-4)
}

@(test)
test_health_never_goes_below_zero_and_only_one_hit_kills :: proc(t: ^testing.T) {
	health := Health_Create(100)
	testing.expect(t, !Health_Apply_Damage(&health, 60, .Torso))
	testing.expect(t, Health_Apply_Damage(&health, 60, .Torso)) // The killing blow.
	testing.expect_value(t, health.current, 0)
	testing.expect(t, Health_Is_Dead(health))
	testing.expect(t, !Health_Apply_Damage(&health, 60, .Head)) // Already dead: no second death.
	testing.expect_value(t, health.current, 0)
}

@(test)
test_zero_damage_changes_nothing :: proc(t: ^testing.T) {
	health := Health_Create(100)
	testing.expect(t, !Health_Apply_Damage(&health, 0, .Head))
	testing.expect_value(t, health.current, 100)
}

@(test)
test_healing_is_capped_at_the_maximum :: proc(t: ^testing.T) {
	health := Health_Create(100)
	Health_Apply_Damage(&health, 40, .Torso)
	Health_Heal(&health, 10)
	testing.expect_value(t, health.current, 70)
	Health_Heal(&health, 1000)
	testing.expect_value(t, health.current, 100)
	dead := Health{current = 0, maximum = 100}
	Health_Heal(&dead, 50)
	testing.expect_value(t, dead.current, 0) // The dead stay dead.
}
