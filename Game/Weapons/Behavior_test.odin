package Weapons

import "core:testing"

SIMULATION_STEP :: 1.0 / 60

// Holds the trigger for `seconds` and counts shots, checking the ammunition invariants every frame.
hold_trigger :: proc(t: ^testing.T, state: ^Weapon_State, stats: Weapon_Stats, seconds: f32) -> (shots: int) {
	initial_total := state.ammo + state.reserve
	for _ in 0 ..< int(seconds / SIMULATION_STEP) {
		if Weapon_Update(state, stats, true, false, SIMULATION_STEP) do shots += 1
		testing.expect(t, state.ammo >= 0 && state.reserve >= 0 && state.ammo <= stats.magazine_size)
		testing.expect_value(t, state.ammo + state.reserve + shots, initial_total) // Every round is either held or fired.
	}
	return
}

@(test)
test_an_automatic_weapon_cannot_fire_faster_than_its_rate :: proc(t: ^testing.T) {
	stats := Weapon_Stats_For(.Rifle)
	state := Weapon_State_Create(stats, 5)
	shots := hold_trigger(t, &state, stats, 2)
	expected := int(2 / stats.fire_interval_seconds)
	testing.expect(t, shots >= expected && shots <= expected + 1)
}

@(test)
test_an_empty_magazine_reloads_by_itself_and_firing_resumes_after :: proc(t: ^testing.T) {
	stats := Weapon_Stats_For(.Rifle)
	state := Weapon_State_Create(stats, 3)
	shots := hold_trigger(t, &state, stats, 6)
	testing.expect(t, shots > stats.magazine_size) // Went past one magazine: it reloaded and kept firing.
	testing.expect(t, state.reserve < 3 * stats.magazine_size)
}

@(test)
test_nothing_fires_while_reloading :: proc(t: ^testing.T) {
	stats := Weapon_Stats_For(.Rifle)
	state := Weapon_State{ammo = 5, reserve = 60}
	Weapon_Update(&state, stats, false, true, SIMULATION_STEP) // Start a reload.
	testing.expect(t, state.reload_remaining_seconds > 0)
	for _ in 0 ..< int(stats.reload_seconds / SIMULATION_STEP) - 3 {
		testing.expect(t, !Weapon_Update(&state, stats, true, false, SIMULATION_STEP))
	}
	for _ in 0 ..< 10 do Weapon_Update(&state, stats, false, false, SIMULATION_STEP)
	testing.expect_value(t, state.ammo, stats.magazine_size)
	testing.expect_value(t, state.reserve, 60 - (stats.magazine_size - 5))
}

@(test)
test_a_semi_automatic_weapon_needs_a_new_trigger_pull_for_each_shot :: proc(t: ^testing.T) {
	stats := Weapon_Stats_For(.Pistol)
	state := Weapon_State_Create(stats, 3)
	held_shots := hold_trigger(t, &state, stats, 3)
	testing.expect_value(t, held_shots, 1)
	pulls := 0
	for _ in 0 ..< 6 {
		for _ in 0 ..< int(stats.fire_interval_seconds * 2 / SIMULATION_STEP) do Weapon_Update(&state, stats, false, false, SIMULATION_STEP) // Release, wait out the cooldown.
		if Weapon_Update(&state, stats, true, false, SIMULATION_STEP) do pulls += 1
	}
	testing.expect_value(t, pulls, 6)
}

@(test)
test_reloading_conserves_ammunition_and_respects_the_reserve :: proc(t: ^testing.T) {
	stats := Weapon_Stats_For(.Rifle)
	partial := Weapon_State{ammo = 0, reserve = 10}
	Weapon_Update(&partial, stats, false, true, SIMULATION_STEP)
	for _ in 0 ..< 200 do Weapon_Update(&partial, stats, false, false, SIMULATION_STEP)
	testing.expect_value(t, partial.ammo, 10)
	testing.expect_value(t, partial.reserve, 0)
	none := Weapon_State{ammo = 3, reserve = 0}
	Weapon_Update(&none, stats, false, true, SIMULATION_STEP)
	testing.expect(t, none.reload_remaining_seconds == 0) // Nothing to reload from.
	full := Weapon_State{ammo = stats.magazine_size, reserve = 30}
	Weapon_Update(&full, stats, false, true, SIMULATION_STEP)
	testing.expect(t, full.reload_remaining_seconds == 0) // Already full.
}

@(test)
test_a_dry_weapon_with_no_reserve_stays_silent :: proc(t: ^testing.T) {
	stats := Weapon_Stats_For(.Rifle)
	state := Weapon_State{ammo = 0, reserve = 0}
	shots := hold_trigger(t, &state, stats, 3)
	testing.expect_value(t, shots, 0)
}

@(test)
test_every_weapon_has_sane_stats :: proc(t: ^testing.T) {
	for kind in Weapon_Kind {
		stats := Weapon_Stats_For(kind)
		testing.expectf(t, stats.damage > 0 && stats.fire_interval_seconds > 0 && stats.magazine_size > 0 && stats.range_meters > 0, "%v: bad stats", kind)
		testing.expectf(t, stats.spread_degrees >= 0 && stats.reload_seconds >= 0 && stats.explosion_radius_meters >= 0, "%v: bad stats", kind)
	}
	testing.expect(t, Weapon_Stats_For(.Rifle).automatic && !Weapon_Stats_For(.Pistol).automatic)
	testing.expect(t, Weapon_Stats_For(.Rocket_Launcher).muzzle_speed > 0 && Weapon_Stats_For(.Rifle).muzzle_speed == 0) // Rockets fly; bullets are hitscan.
}

@(test)
test_explosion_damage_falls_off_to_zero_at_the_radius :: proc(t: ^testing.T) {
	testing.expect_value(t, Explosion_Falloff(0, 5), 1)
	testing.expect_value(t, Explosion_Falloff(5, 5), 0)
	testing.expect_value(t, Explosion_Falloff(9, 5), 0)
	previous: f32 = 2
	for step in 0 ..= 50 {
		value := Explosion_Falloff(f32(step) * 0.1, 5)
		testing.expect(t, value <= previous && value >= 0 && value <= 1)
		previous = value
	}
}
