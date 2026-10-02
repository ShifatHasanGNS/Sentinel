package Characters

import World "../../Engine/World"
import "core:math"

HIT_SPRING_FREQUENCY :: 14.0 // Angular frequency of the hit reaction: back to rest in about a third of a second.
HIT_IMPULSE_METERS_PER_SECOND :: 2.2

// One soldier in the world: who they are, where they stand and how they move.
Character :: struct {
	variant:         Soldier_Variant,
	position:        [3]f32, // Ground point under the pelvis.
	heading_radians: f32,
	speed:           f32,
	gait_phase:      f32,
	aiming:          bool,
	aim_direction:   [3]f32,
	crouch:          f32,
	hit_lean:        World.Spring3, // The chest's displacement from a hit, springing back to zero.
	hide_weapon:     bool, // The owner draws the weapon itself (the player's body holds whichever weapon is selected).
}

// Advances animation state: the gait runs with speed, the hit spring relaxes.
Character_Step :: proc(character: ^Character, delta_seconds: f32) {
	character.gait_phase += Gait_Phase_Advance(character.speed, delta_seconds)
	character.gait_phase -= math.floor(character.gait_phase)
	World.Spring3_Step(&character.hit_lean, {}, HIT_SPRING_FREQUENCY, delta_seconds)
}

// Pushes the character along `direction` (a unit vector): the chest jolts and springs back.
Character_Hit :: proc(character: ^Character, direction: [3]f32) {
	character.hit_lean.velocity += direction * HIT_IMPULSE_METERS_PER_SECOND
}

Character_Pose :: proc(character: Character) -> Pose {
	return Pose_Solve(Pose_Input{
		position = character.position,
		heading_radians = character.heading_radians,
		speed = character.speed,
		gait_phase = character.gait_phase,
		aiming = character.aiming,
		aim_direction = character.aim_direction,
		crouch = character.crouch,
		lean = character.hit_lean.value,
	})
}
