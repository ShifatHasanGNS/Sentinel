package Gameplay

Hit_Zone :: enum {
	Head,
	Torso,
	Limb,
}

Health :: struct {
	current: f32,
	maximum: f32,
}

Health_Create :: proc(maximum: f32) -> Health {
	return Health{maximum, maximum}
}

Health_Is_Dead :: proc(health: Health) -> bool {
	return health.current <= 0
}

// Headshots hurt triple, limbs a little over half.
Zone_Multiplier :: proc(zone: Hit_Zone) -> f32 {
	switch zone {
	case .Head: return 3
	case .Torso: return 1
	case .Limb: return 0.6
	}
	unreachable()
}

// Applies a hit; returns true only for the hit that kills, so a death is reported exactly once.
Health_Apply_Damage :: proc(health: ^Health, base_damage: f32, zone: Hit_Zone) -> (died: bool) {
	if Health_Is_Dead(health^) || base_damage <= 0 do return false
	health.current = max(health.current - base_damage * Zone_Multiplier(zone), 0)
	return Health_Is_Dead(health^)
}

Health_Heal :: proc(health: ^Health, amount: f32) {
	if Health_Is_Dead(health^) || amount <= 0 do return
	health.current = min(health.current + amount, health.maximum)
}
