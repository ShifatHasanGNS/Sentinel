package Sandbox

import "../../Engine/Audio"
import "../Gameplay"
import "../Mission"
import "../Vehicles"
import "../Weapons"
import "core:math"
import la "core:math/linalg"

ENEMIES_TRACKED :: 64
ENEMY_STEP_METERS :: f32(2.1)
ENEMY_HEARING_METERS :: f32(35.0)
HACK_BEEP_SECONDS :: f32(0.32)
BIRD_SECONDS_MIN :: f32(4.0)
BIRD_SECONDS_SPAN :: f32(8.0)
WIND_VOLUME :: f32(0.2)
CRICKET_VOLUME :: f32(0.1)

// What the sound system remembers from the previous frame, so it can tell when something just happened (a hit taken, a landing, a
// weapon switch) instead of replaying a cue every frame.
Feedback_State :: struct {
	damage_flash:    f32,
	hit_marker:      f32,
	current_weapon:  Weapons.Weapon_Kind,
	ammo:            int,
	on_ground:       bool,
	fall_speed:      f32,
	player_dead:     bool,
	was_driving:     bool,
	flashlight:      bool,
	map_open:        bool,
	binoculars:      bool,
	hack_seconds:    f32,
	hack_timer:      f32,
	enemy_positions: [ENEMIES_TRACKED][3]f32,
	enemy_walked:    [ENEMIES_TRACKED]f32,
	enemy_dead:      [ENEMIES_TRACKED]bool,
	bird_timer:      f32,
	random_state:    u32,
	started:         bool,
}

// A value in [0, 1) from a small linear congruential generator: ambience needs variety, not quality randomness.
@(private = "file")
random_unit :: proc(state: ^Feedback_State) -> f32 {
	state.random_state = state.random_state * 1664525 + 1013904223
	return f32(state.random_state >> 8) / 16777216.0
}

// The tank's cannon booms like a launcher; every other vehicle gun (carrier, helicopter) rattles like a rifle. A shot that did not come
// from the occupied vehicle keeps the sound it was given.
vehicle_gun_sound :: proc(play: ^Play, default: ^Audio.Sound, position: [3]f32) -> ^Audio.Sound {
	index, driving := play.driving.?
	if !driving do return default
	vehicle := play.vehicles[index]
	origin, _ := Vehicles.Vehicle_Muzzle(vehicle)
	if la.length(origin - position) > 3 do return default
	if vehicle.kind == .Battle_Tank do return &play.sound.launcher
	return &play.sound.rifle
}

// One-shot cues for what the player does and what happens to them. Each fires on the frame the thing changes.
feedback_sounds :: proc(sandbox: ^Sandbox, delta_seconds: f32) {
	play := &sandbox.play
	bank := &play.sound
	state := &bank.feedback
	player := play.battle.player
	weapon := player.weapons[player.current]
	driving := play.driving != nil
	if !state.started { // The first frame only records the starting values.
		state.started = true
		state.random_state = 2463534242
		state.bird_timer = BIRD_SECONDS_MIN
		state.current_weapon, state.ammo, state.on_ground = player.current, weapon.ammo, player.controller.on_ground
		state.flashlight, state.map_open, state.binoculars, state.was_driving = play.flashlight_on, play.map_open, play.binoculars, driving
		for enemy, index in play.battle.enemies do if index < ENEMIES_TRACKED {
			state.enemy_positions[index], state.enemy_dead[index] = enemy.character.position, !Gameplay.Enemy_Is_Alive(enemy)
		}
	}
	player_feedback(play, state, player, weapon, driving)
	toggle_feedback(play, state, driving)
	hack_feedback(play, state, delta_seconds)
	enemy_feedback(play, state)
}

@(private = "file")
player_feedback :: proc(play: ^Play, state: ^Feedback_State, player: Gameplay.Player, weapon: Weapons.Weapon_State, driving: bool) {
	bank := &play.sound
	dead := Gameplay.Health_Is_Dead(player.health)
	if player.damage_flash > state.damage_flash + 0.3 && !dead do play_here(play, &bank.thud, 0.75, 0.85) // A round hit the player.
	if dead && !state.player_dead do play_here(play, &bank.heavy_thud, 1.0, 0.8)
	if player.hit_marker > state.hit_marker + 0.05 do play_here(play, &bank.beep, 0.35, 1.4) // Your shot hit an enemy.
	if player.current != state.current_weapon do play_here(play, &bank.click, 0.35, 0.8)
	if weapon.ammo == 0 && state.ammo > 0 && player.current == state.current_weapon do play_here(play, &bank.click, 0.5, 0.65) // Magazine empty.
	if driving != state.was_driving do play_here(play, &bank.heavy_thud, 0.55, 1.25) // A door shutting.
	// Landing is judged by how fast the player was falling when the ground arrived; a jump leaves with a small step.
	controller := player.controller
	if !controller.on_ground do state.fall_speed = max(state.fall_speed, -controller.velocity.y)
	if controller.on_ground && !state.on_ground && state.fall_speed > 2.5 && !driving {
		play_here(play, &bank.thud, min(0.25 + 0.07 * state.fall_speed, 0.85), 0.7)
	}
	if !controller.on_ground && state.on_ground && controller.velocity.y > 2 && !driving do play_here(play, &bank.step_b, 0.25, 1.3)
	if controller.on_ground do state.fall_speed = 0
	state.damage_flash, state.hit_marker, state.current_weapon, state.ammo = player.damage_flash, player.hit_marker, player.current, weapon.ammo
	state.on_ground, state.player_dead, state.was_driving = controller.on_ground, dead, driving
}

@(private = "file")
toggle_feedback :: proc(play: ^Play, state: ^Feedback_State, driving: bool) {
	bank := &play.sound
	if play.flashlight_on != state.flashlight do play_here(play, &bank.click, 0.3, 1.25)
	if play.map_open != state.map_open do play_here(play, &bank.click, 0.3, 0.95)
	if play.binoculars != state.binoculars do play_here(play, &bank.click, 0.3, 1.05)
	state.flashlight, state.map_open, state.binoculars = play.flashlight_on, play.map_open, play.binoculars
}

// While the terminal is being hacked it beeps faster and higher as the progress bar fills, and a longer low tone marks the break-in.
@(private = "file")
hack_feedback :: proc(play: ^Play, state: ^Feedback_State, delta_seconds: f32) {
	hacked := play.mission.state.hack_seconds
	if hacked > state.hack_seconds && hacked < Mission.HACK_SECONDS {
		state.hack_timer += delta_seconds
		progress := hacked / Mission.HACK_SECONDS
		if state.hack_timer >= HACK_BEEP_SECONDS * (1 - 0.6 * progress) {
			state.hack_timer = 0
			play_here(play, &play.sound.beep, 0.3, 0.8 + 0.9 * progress)
		}
	} else do state.hack_timer = HACK_BEEP_SECONDS
	state.hack_seconds = hacked
}

// Soldiers' footsteps within earshot, and the thud of one falling.
@(private = "file")
enemy_feedback :: proc(play: ^Play, state: ^Feedback_State) {
	bank := &play.sound
	eye := Gameplay.Player_Eye(play.battle.player)
	for enemy, index in play.battle.enemies {
		if index >= ENEMIES_TRACKED do break
		position := enemy.character.position
		alive := Gameplay.Enemy_Is_Alive(enemy)
		if !alive && !state.enemy_dead[index] do play_at(play, &bank.heavy_thud, 0.9, position, 1.1)
		if alive {
			step := la.length([2]f32{position.x - state.enemy_positions[index].x, position.z - state.enemy_positions[index].z})
			state.enemy_walked[index] = 0 if step > 4 else state.enemy_walked[index] + step // A teleport (respawn) is not a walk.
			if state.enemy_walked[index] >= ENEMY_STEP_METERS && la.length(position - eye) < ENEMY_HEARING_METERS {
				state.enemy_walked[index] = 0
				play_at(play, &bank.step_a if index % 2 == 0 else &bank.step_b, 0.32, position, 0.8 + 0.05 * f32(index % 4))
			}
		}
		state.enemy_positions[index], state.enemy_dead[index] = position, !alive
	}
}

// The world's background: wind all day, crickets after dark (louder the darker it is), and a bird call now and then in daylight
// from a random spot around the player.
ambience :: proc(sandbox: ^Sandbox, delta_seconds: f32) {
	play := &sandbox.play
	bank := &play.sound
	state := &bank.feedback
	mixer := &bank.device.mixer
	sun_height := Gameplay.Sun_Direction_To_Sun(sandbox.hours).y
	darkness := clamp((0.08 - sun_height) / 0.2, 0, 1)
	daylight := clamp((sun_height - 0.15) / 0.3, 0, 1)
	if bank.wind_voice == 0 do bank.wind_voice = Audio.Mixer_Play(mixer, &bank.wind, WIND_VOLUME, 0, 1, true)
	else do Audio.Mixer_Set(mixer, bank.wind_voice, WIND_VOLUME * (0.6 + 0.4 * daylight), 0, 1)
	if darkness > 0.05 {
		volume := CRICKET_VOLUME * darkness
		if bank.cricket_voice == 0 do bank.cricket_voice = Audio.Mixer_Play(mixer, &bank.crickets, volume, 0, 1, true)
		else do Audio.Mixer_Set(mixer, bank.cricket_voice, volume, 0, 1)
	} else if bank.cricket_voice != 0 {
		Audio.Mixer_Stop(mixer, bank.cricket_voice)
		bank.cricket_voice = 0
	}
	state.bird_timer -= delta_seconds
	if state.bird_timer > 0 || daylight < 0.2 do return
	state.bird_timer = BIRD_SECONDS_MIN + BIRD_SECONDS_SPAN * random_unit(state)
	angle := random_unit(state) * 2 * math.PI
	distance := 25 + 40 * random_unit(state)
	eye := Gameplay.Player_Eye(play.battle.player)
	position := eye + {math.cos(angle) * distance, 6 + 8 * random_unit(state), math.sin(angle) * distance}
	sound := &bank.bird_high if random_unit(state) > 0.5 else &bank.bird_low
	play_at(play, sound, 0.9 * daylight, position, 0.9 + 0.25 * random_unit(state))
}
