package Gameplay

import "../Weapons"
import la "core:math/linalg"

PICKUP_RADIUS_METERS :: 1.3
MEDKIT_HEAL :: 50.0
DROPPED_MAGAZINES :: 2

// Supplies lying on the ground, collected by walking over them (as in Project I.G.I.): dead soldiers drop rifle ammunition, and
// medical kits wait inside buildings.
Pickup_Kind :: enum {
	Ammo,
	Medkit,
}

Pickup :: struct {
	kind:     Pickup_Kind,
	position: [3]f32,
	taken:    bool,
}

Battle_Add_Pickup :: proc(battle: ^Battle, kind: Pickup_Kind, position: [3]f32) {
	append(&battle.pickups, Pickup{kind = kind, position = position})
}

// Takes whatever the player stands on. A medkit is left for later when health is already full; ammunition is always taken.
collect_pickups :: proc(battle: ^Battle) {
	player := &battle.player
	if Health_Is_Dead(player.health) do return
	for &pickup in battle.pickups {
		if pickup.taken do continue
		offset := pickup.position - player.controller.position
		if la.length([2]f32{offset.x, offset.z}) > PICKUP_RADIUS_METERS || abs(offset.y) > 1.5 do continue
		switch pickup.kind {
		case .Ammo:
			player.weapons[.Rifle].reserve += DROPPED_MAGAZINES * Weapons.Weapon_Stats_For(.Rifle).magazine_size
			pickup.taken = true
		case .Medkit:
			if player.health.current >= player.health.maximum do continue
			Health_Heal(&player.health, MEDKIT_HEAL)
			pickup.taken = true
		}
		player.pickup_flash = PICKUP_FLASH_SECONDS
	}
}
