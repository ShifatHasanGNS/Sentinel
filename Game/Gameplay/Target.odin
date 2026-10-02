package Gameplay

// A structure the mission wants destroyed (the radar dish): a sphere with health that bullets and blasts wear down.
TARGET_BLAST_MULTIPLIER :: 2.0 // Explosives hurt structures more than they hurt people.

Target :: struct {
	position:  [3]f32,
	radius:    f32,
	health:    f32,
	maximum:   f32,
	destroyed: bool,
}

Target_Create :: proc(position: [3]f32, radius, health: f32) -> Target {
	assert(radius > 0 && health > 0, "Target_Create: needs a size and health")
	return Target{position = position, radius = radius, health = health, maximum = health}
}

// Returns true only for the hit that destroys it, so the destruction is reported exactly once.
Target_Damage :: proc(target: ^Target, amount: f32) -> (destroyed_now: bool) {
	if target.destroyed || amount <= 0 do return false
	target.health = max(target.health - amount, 0)
	if target.health > 0 do return false
	target.destroyed = true
	return true
}
