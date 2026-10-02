package Gameplay

import World "../../Engine/World"
import "../Weapons"
import "core:math"
import la "core:math/linalg"

PLAYER_EYE_HEIGHT_METERS :: 1.65
PLAYER_CROUCH_EYE_HEIGHT_METERS :: 0.95
WALK_SPEED :: 4.0
SPRINT_SPEED :: 6.5
PLAYER_HEALTH :: 100
PLAYER_REGEN_DELAY_SECONDS :: 5.0 // Health returns only after this long without being hit.
PLAYER_REGEN_PER_SECOND :: 8.0
PITCH_LIMIT_RADIANS :: 1.5
DAMAGE_FLASH_DECAY_PER_SECOND :: 2.0
HIT_MARKER_SECONDS :: 0.18

Player :: struct {
	controller:   World.Controller,
	yaw_radians:  f32, // Zero looks along -Z; positive turns toward -X.
	pitch_radians: f32,
	health:       Health,
	weapons:      [Weapons.Weapon_Kind]Weapons.Weapon_State,
	current:      Weapons.Weapon_Kind,
	spawn:        [3]f32,
	damage_flash: f32, // 1 when just hurt, fading to 0.
	seconds_since_damage: f32,
	armor:        f32, // Fraction of enemy fire absorbed: 0 on foot, high inside an armored vehicle.
	hit_marker:   f32, // Seconds left of the hit confirmation.
	kills:        int,
	shots_fired:  u32,
}

Player_Input :: struct {
	move:    [2]f32, // x: strafe right, y: forward; each in [-1, 1].
	look:    [2]f32, // Radians to turn this frame: x yaw (positive turns left), y pitch (positive looks up).
	jump:    bool,
	fire:    bool,
	reload:  bool,
	sprint:  bool,
	crouch:  bool, // Held: stay low (slower, quieter, harder to see).
	respawn: bool,
	select:  Maybe(Weapons.Weapon_Kind),
}

Player_Create :: proc(spawn: [3]f32) -> (player: Player) {
	player.spawn = spawn
	Player_Respawn(&player)
	return player
}

// Full health, a full loadout, back at the spawn point.
Player_Respawn :: proc(player: ^Player) {
	player.controller = World.Controller_Create(player.spawn)
	player.health = Health_Create(PLAYER_HEALTH)
	player.damage_flash, player.hit_marker, player.seconds_since_damage, player.armor = 0, 0, 0, 0
	for kind in Weapons.Weapon_Kind {
		stats := Weapons.Weapon_Stats_For(kind)
		reserve_magazines := 6 if kind == .Rifle || kind == .Pistol else 4
		player.weapons[kind] = Weapons.Weapon_State_Create(stats, reserve_magazines)
	}
	player.current = .Rifle
}

Player_Eye :: proc(player: Player) -> [3]f32 {
	height: f32 = PLAYER_CROUCH_EYE_HEIGHT_METERS if player.controller.crouching else PLAYER_EYE_HEIGHT_METERS
	return player.controller.position + {0, height, 0}
}

Player_Forward :: proc(player: Player) -> [3]f32 {
	return {-math.sin(player.yaw_radians) * math.cos(player.pitch_radians), math.sin(player.pitch_radians), -math.cos(player.yaw_radians) * math.cos(player.pitch_radians)}
}

// Horizontal wish velocity from the move input and the facing: forward along the view, strafe to its right.
Player_Wish_Velocity :: proc(player: Player, input: Player_Input) -> [2]f32 {
	forward := [2]f32{-math.sin(player.yaw_radians), -math.cos(player.yaw_radians)}
	right := [2]f32{math.cos(player.yaw_radians), -math.sin(player.yaw_radians)}
	direction := forward * input.move.y + right * input.move.x
	if la.length(direction) > 1 do direction = la.normalize(direction)
	if player.controller.crouching do return direction * (WALK_SPEED * CROUCH_SPEED_FACTOR)
	return direction * (SPRINT_SPEED if input.sprint else WALK_SPEED)
}

Player_Look :: proc(player: ^Player, look: [2]f32) {
	player.yaw_radians += look.x
	player.pitch_radians = clamp(player.pitch_radians + look.y, -PITCH_LIMIT_RADIANS, PITCH_LIMIT_RADIANS)
}
