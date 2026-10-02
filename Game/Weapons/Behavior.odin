package Weapons

Weapon_Stats :: struct {
	damage:                  f32, // Per hit, before hit-zone multipliers (explosions: at the centre).
	fire_interval_seconds:   f32,
	magazine_size:           int,
	reload_seconds:          f32,
	spread_degrees:          f32, // Half-angle of the cone shots are scattered in.
	muzzle_speed:            f32, // Metres per second; zero means the shot lands instantly (hitscan).
	range_meters:            f32,
	explosion_radius_meters: f32,
	automatic:               bool,
}

Weapon_Stats_For :: proc(kind: Weapon_Kind) -> Weapon_Stats {
	switch kind {
	case .Rifle: return {damage = 22, fire_interval_seconds = 0.1, magazine_size = 30, reload_seconds = 2, spread_degrees = 1.2, range_meters = 300, automatic = true}
	case .Sniper_Rifle: return {damage = 90, fire_interval_seconds = 1.2, magazine_size = 5, reload_seconds = 3, spread_degrees = 0.1, range_meters = 800}
	case .Pistol: return {damage = 18, fire_interval_seconds = 0.25, magazine_size = 12, reload_seconds = 1.5, spread_degrees = 2, range_meters = 120}
	case .Rocket_Launcher: return {damage = 160, fire_interval_seconds = 1, magazine_size = 1, reload_seconds = 3, spread_degrees = 0.3, muzzle_speed = 45, range_meters = 400, explosion_radius_meters = 5}
	case .Grenade: return {damage = 120, fire_interval_seconds = 1, magazine_size = 1, reload_seconds = 0, spread_degrees = 0, muzzle_speed = 14, range_meters = 60, explosion_radius_meters = 6}
	}
	unreachable()
}

Weapon_State :: struct {
	ammo:                     int, // In the magazine.
	reserve:                  int, // Carried.
	cooldown_seconds:         f32, // Time until the next shot is allowed; may sit one frame below zero to carry the rate exactly.
	reload_remaining_seconds: f32,
	trigger_was_down:         bool,
}

Weapon_State_Create :: proc(stats: Weapon_Stats, reserve_magazines: int) -> Weapon_State {
	return Weapon_State{ammo = stats.magazine_size, reserve = reserve_magazines * stats.magazine_size}
}

// Advances a weapon by one frame and says whether it fired. A reload starts on request or when the magazine is dry with the
// trigger held, takes reload_seconds, and moves rounds from the reserve; nothing fires while it runs. Semi-automatic weapons
// need the trigger released between shots. The rate is exact at any frame rate because each shot adds the interval to the
// cooldown instead of resetting it, but an idle trigger cannot bank more than a frame of credit.
Weapon_Update :: proc(state: ^Weapon_State, stats: Weapon_Stats, trigger_down, reload_pressed: bool, delta_seconds: f32) -> (fired: bool) {
	state.cooldown_seconds = max(state.cooldown_seconds - delta_seconds, -delta_seconds)
	advance_reload(state, stats, delta_seconds)
	wants_reload := reload_pressed || (trigger_down && state.ammo == 0)
	if wants_reload && state.reload_remaining_seconds == 0 && state.ammo < stats.magazine_size && state.reserve > 0 {
		state.reload_remaining_seconds = stats.reload_seconds
		if stats.reload_seconds == 0 do finish_reload(state, stats)
	}
	can_fire := state.reload_remaining_seconds == 0 && state.cooldown_seconds <= 0 && state.ammo > 0
	if can_fire && trigger_down && (stats.automatic || !state.trigger_was_down) {
		state.ammo -= 1
		state.cooldown_seconds += stats.fire_interval_seconds
		fired = true
	}
	state.trigger_was_down = trigger_down
	return fired
}

@(private = "file")
advance_reload :: proc(state: ^Weapon_State, stats: Weapon_Stats, delta_seconds: f32) {
	if state.reload_remaining_seconds <= 0 do return
	state.reload_remaining_seconds -= delta_seconds
	if state.reload_remaining_seconds <= 0 {
		state.reload_remaining_seconds = 0
		finish_reload(state, stats)
	}
}

@(private = "file")
finish_reload :: proc(state: ^Weapon_State, stats: Weapon_Stats) {
	moved := min(stats.magazine_size - state.ammo, state.reserve)
	state.ammo += moved
	state.reserve -= moved
}

// Share of an explosion's centre damage reaching something `distance` away: (1 - d/r)^2, zero at and beyond the radius.
Explosion_Falloff :: proc(distance_meters, radius_meters: f32) -> f32 {
	if distance_meters >= radius_meters do return 0
	remaining := 1 - distance_meters / radius_meters
	return remaining * remaining
}
