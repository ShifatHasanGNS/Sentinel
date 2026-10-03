package Gameplay

import "../Weapons"
import la "core:math/linalg"

PICKUP_RADIUS_METERS :: 1.3
MEDKIT_HEAL :: 50.0
DROPPED_MAGAZINES :: 2
WEAPON_DROP_MAGAZINES :: 1

// Supplies lying on the ground, collected by walking over them (as in Project I.G.I.): dead soldiers drop ammunition for the weapon
// they carried (a sniper's is for the sniper rifle), and
// medical kits wait inside buildings.
Pickup_Kind :: enum {
	Ammo,
	Medkit,
	Weapon, // A dropped weapon: walking over it supplies that weapon's ammunition (the player already has the whole arsenal).
}

Pickup :: struct {
	kind:     Pickup_Kind,
	position: [3]f32,
	taken:    bool,
	weapon:   Weapons.Weapon_Kind, // Which weapon's ammunition (Ammo only).
}

Battle_Add_Pickup :: proc(battle: ^Battle, kind: Pickup_Kind, position: [3]f32, weapon: Weapons.Weapon_Kind = .Rifle) {
	append(&battle.pickups, Pickup{kind = kind, position = position, weapon = weapon})
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
			player.weapons[pickup.weapon].reserve += DROPPED_MAGAZINES * Weapons.Weapon_Stats_For(pickup.weapon).magazine_size
			pickup.taken = true
		case .Weapon:
			state := &player.weapons[pickup.weapon]
			state.reserve += Weapons.Weapon_Stats_For(pickup.weapon).magazine_size * WEAPON_DROP_MAGAZINES
			pickup.taken = true
		case .Medkit:
			if player.health.current >= player.health.maximum do continue
			Health_Heal(&player.health, MEDKIT_HEAL)
			pickup.taken = true
		}
		player.pickup_flash = PICKUP_FLASH_SECONDS
	}
}
