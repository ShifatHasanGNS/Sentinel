package Gameplay

import World "../../Engine/World"
import "../Characters"
import "../Weapons"
import "core:math"
import la "core:math/linalg"

ENEMY_HEALTH :: 100
ENEMY_FIRE_INTERVAL_SECONDS :: 0.35 // Enemies fire in bursts slower than the rifle can, so a fight is survivable.
ENEMY_DAMAGE :: 4
ENEMY_TURN_RADIANS_PER_SECOND :: 3.5 // Slow enough that flanking works.
ENEMY_EYE_HEIGHT_METERS :: 1.6
HEAD_HIT_RADIUS_METERS :: 0.13
TORSO_HIT_RADIUS_METERS :: 0.2
LIMB_HIT_RADIUS_METERS :: 0.07

Enemy :: struct {
	character:     Characters.Character,
	ai:            Enemy_Ai,
	health:        Health,
	controller:    World.Controller,
	weapon:        Weapons.Weapon_State,
	waypoints:     [dynamic][3]f32,
	seed:          u32,
	shot_counter:  u32,
	death_seconds: f32,
	body_found:    bool, // Another soldier has come across this corpse.
}

Enemy_Weapon_Stats :: proc() -> (stats: Weapons.Weapon_Stats) {
	stats = Weapons.Weapon_Stats_For(.Rifle)
	stats.fire_interval_seconds = ENEMY_FIRE_INTERVAL_SECONDS
	return stats
}

Enemy_Is_Alive :: proc(enemy: Enemy) -> bool {
	return !Health_Is_Dead(enemy.health)
}

Enemy_Chest_Position :: proc(enemy: Enemy) -> [3]f32 {
	return Characters.Character_Pose(enemy.character).joints[.Chest]
}

Enemy_Head_Position :: proc(enemy: Enemy) -> [3]f32 {
	return Characters.Character_Pose(enemy.character).joints[.Head]
}

Enemy_Eye :: proc(enemy: Enemy) -> [3]f32 {
	return enemy.controller.position + {0, ENEMY_EYE_HEIGHT_METERS, 0}
}

Enemy_Forward :: proc(enemy: Enemy) -> [3]f32 {
	return {math.sin(enemy.character.heading_radians), 0, math.cos(enemy.character.heading_radians)}
}

// Body parts as spheres and capsules around the posed skeleton: the head, the torso, and each limb bone.
Hit_Shape :: struct {
	from:   [3]f32,
	to:     [3]f32,
	radius: f32,
	zone:   Hit_Zone,
}

Enemy_Hit_Shapes :: proc(enemy: Enemy) -> (shapes: [10]Hit_Shape) {
	joints := Characters.Character_Pose(enemy.character).joints
	shapes[0] = {joints[.Head], joints[.Head], HEAD_HIT_RADIUS_METERS, .Head}
	shapes[1] = {joints[.Pelvis], joints[.Chest], TORSO_HIT_RADIUS_METERS, .Torso}
	limbs := [8][2]Characters.Joint{
		{.Hip_Left, .Knee_Left}, {.Knee_Left, .Ankle_Left}, {.Hip_Right, .Knee_Right}, {.Knee_Right, .Ankle_Right},
		{.Shoulder_Left, .Elbow_Left}, {.Elbow_Left, .Hand_Left}, {.Shoulder_Right, .Elbow_Right}, {.Elbow_Right, .Hand_Right},
	}
	for limb, index in limbs do shapes[2 + index] = {joints[limb[0]], joints[limb[1]], LIMB_HIT_RADIUS_METERS, .Limb}
	return
}

// The nearest body part a ray strikes, if any.
Enemy_Raycast :: proc(enemy: Enemy, origin, direction: [3]f32) -> (distance: f32, zone: Hit_Zone, hit: bool) {
	distance = math.INF_F32
	for shape in Enemy_Hit_Shapes(enemy) {
		result := World.Ray_Capsule(origin, direction, shape.from, shape.to, shape.radius)
		if result.hit && result.distance < distance do distance, zone, hit = result.distance, shape.zone, true
	}
	return
}

// Rotates toward a target angle by at most max_step, taking the short way round.
turn_toward :: proc(current, target, max_step: f32) -> f32 {
	difference := math.mod(target - current + math.PI, 2 * math.PI)
	if difference < 0 do difference += 2 * math.PI
	difference -= math.PI
	return current + clamp(difference, -max_step, max_step)
}

Enemy_Create :: proc(variant: Characters.Soldier_Variant, position: [3]f32, heading_radians: f32, waypoints: [][3]f32, seed: u32) -> (enemy: Enemy) {
	enemy.character = Characters.Character{variant = variant, position = position, heading_radians = heading_radians}
	enemy.ai = Enemy_Ai_Create(position, seed)
	enemy.health = Health_Create(ENEMY_HEALTH)
	enemy.controller = World.Controller_Create(position)
	enemy.weapon = Weapons.Weapon_State_Create(Enemy_Weapon_Stats(), 1000)
	enemy.seed = seed
	for waypoint in waypoints do append(&enemy.waypoints, waypoint)
	return enemy
}

Enemy_Destroy :: proc(enemy: ^Enemy) {
	delete(enemy.waypoints)
}

