package Sandbox

import "../../Engine/Audio"
import World "../../Engine/World"
import "../Gameplay"
import "../Mission"
import "../Weapons"
import "core:math"
import la "core:math/linalg"

FOOTSTEP_METERS :: f32(1.9) // Walking; a step falls this far apart.
SPRINT_FOOTSTEP_METERS :: f32(2.6)
ROLLOFF_METERS :: f32(10.0)

// Every sound the game makes, generated at startup, and the voices that must be adjusted while they play.
Sound_Bank :: struct {
	device:        ^Audio.Device,
	rifle, sniper, pistol, launcher, explosion, silenced: Audio.Sound,
	step_a, step_b, click, impact, ricochet, chime, creak: Audio.Sound,
	engine_light, engine_heavy, rotor, alarm: Audio.Sound,
	engine_voice, rotor_voice, alarm_voice: u32,
	step_distance: f32,
	step_flip:     bool,
	was_reloading: bool,
	ladder_rung:   int,
	ladder_phase:  World.Ladder_Phase,
}

sound_create :: proc(enabled: bool) -> (bank: Sound_Bank) {
	if !enabled do return
	device, ok := Audio.Device_Create()
	if !ok do return
	bank.device = device
	bank.rifle = Audio.Synth_Gunshot(0.05, 90, 6000, 1.0, 11)
	bank.sniper = Audio.Synth_Gunshot(0.11, 55, 4500, 1.3, 12)
	bank.pistol = Audio.Synth_Gunshot(0.03, 140, 5000, 0.8, 13)
	bank.launcher = Audio.Synth_Gunshot(0.16, 45, 2500, 1.2, 14)
	bank.explosion = Audio.Synth_Explosion(15)
	bank.silenced = Audio.Synth_Gunshot(0.02, 110, 1100, 0.5, 25)
	bank.step_a, bank.step_b = Audio.Synth_Footstep(0.35, 16), Audio.Synth_Footstep(0.3, 17)
	bank.click = Audio.Synth_Click(18)
	bank.impact, bank.ricochet = Audio.Synth_Impact(false, 19), Audio.Synth_Impact(true, 20)
	bank.chime = Audio.Synth_Chime(660)
	bank.creak = Audio.Synth_Creak(21)
	bank.engine_light, bank.engine_heavy = Audio.Synth_Engine(34, 22), Audio.Synth_Engine(20, 23)
	bank.rotor = Audio.Synth_Rotor(24)
	bank.alarm = Audio.Synth_Alarm()
	return bank
}

sound_destroy :: proc(bank: ^Sound_Bank) {
	if bank.device == nil do return
	Audio.Device_Destroy(bank.device)
	for sound in ([]^Audio.Sound{&bank.rifle, &bank.sniper, &bank.pistol, &bank.launcher, &bank.explosion, &bank.silenced, &bank.step_a, &bank.step_b, &bank.click, &bank.impact, &bank.ricochet, &bank.chime, &bank.creak, &bank.engine_light, &bank.engine_heavy, &bank.rotor, &bank.alarm}) {
		Audio.Sound_Destroy(sound)
	}
	bank^ = {}
}

// How loud and how far left or right a sound at `position` is for a listener at `eye` facing `yaw` (the player's yaw: 0 looks along
// -Z, right is (cos yaw, -sin yaw)). Loudness falls as 1 / (1 + (d / 10)^1.3), a little steeper than the inverse-distance law so far
// gunfire fades to a murmur; pan is the sideways part of the direction to the source.
spatialize :: proc(base_volume: f32, position, eye: [3]f32, yaw: f32) -> (volume, pan: f32) {
	offset := position - eye
	distance := la.length(offset)
	volume = base_volume / (1 + math.pow(distance / ROLLOFF_METERS, 1.3))
	if distance < 0.5 do return volume, 0
	right := [2]f32{math.cos(yaw), -math.sin(yaw)}
	pan = (offset.x * right.x + offset.z * right.y) / distance
	return volume, pan
}

@(private = "file")
play_at :: proc(play: ^Play, sound: ^Audio.Sound, base_volume: f32, position: [3]f32, pitch: f32 = 1) {
	eye := Gameplay.Player_Eye(play.battle.player)
	volume, pan := spatialize(base_volume, position, eye, play.battle.player.yaw_radians)
	if volume < 0.01 do return
	Audio.Mixer_Play(&play.sound.device.mixer, sound, volume, pan, pitch)
}

@(private = "file")
play_here :: proc(play: ^Play, sound: ^Audio.Sound, volume: f32, pitch: f32 = 1) {
	Audio.Mixer_Play(&play.sound.device.mixer, sound, volume, 0, pitch)
}

weapon_sound :: proc(bank: ^Sound_Bank, kind: Weapons.Weapon_Kind) -> ^Audio.Sound {
	#partial switch kind {
	case .Sniper_Rifle: return &bank.sniper
	case .Pistol: return &bank.pistol
	case .Rocket_Launcher, .Grenade: return &bank.launcher
	case .Silenced_Pistol: return &bank.silenced
	}
	return &bank.rifle
}

// One frame of sound: the battle's new effects (shots, impacts, blasts) heard from where they happened; the player's footsteps and
// reload; engines and rotor following the vehicle; the alarm loop; and a chime when an objective completes.
sound_update :: proc(sandbox: ^Sandbox, delta_seconds: f32) {
	play := &sandbox.play
	if play.sound.device == nil do return
	player := play.battle.player
	for effect in play.battle.effects {
		if effect.age > delta_seconds * 1.5 do continue
		switch effect.kind {
		case .Muzzle_Flash:
			own := la.length(effect.position - Gameplay.Player_Eye(player)) < 2
			sound := weapon_sound(&play.sound, player.current) if own else &play.sound.rifle
			if play.driving != nil && own do sound = &play.sound.rifle
			if effect.silenced do sound = &play.sound.silenced
			play_at(play, sound, 0.9, effect.position, 1 if own else 0.95 + 0.1 * f32(int(effect.position.x * 7) % 3))
		case .Impact:
			play_at(play, &play.sound.impact, 0.5, effect.position, 0.85 + 0.3 * f32(int(effect.position.z * 5) % 3) / 2)
			if int(effect.position.x * 3 + effect.position.z) % 4 == 0 do play_at(play, &play.sound.ricochet, 0.35, effect.position)
		case .Explosion:
			play_at(play, &play.sound.explosion, 1.6, effect.position)
		case .Tracer:
		}
	}
	footsteps(play, delta_seconds)
	ladder_sounds(play)
	reload_click(play)
	vehicle_sounds(play)
	alarm_loop(play)
	for objective in Mission.Objective {
		if objective in play.mission.state.just_completed do play_here(play, &play.sound.chime, 0.7)
	}
	if player.pickup_flash > PICKUP_CHIME_THRESHOLD && play.last_pickup_flash <= PICKUP_CHIME_THRESHOLD do play_here(play, &play.sound.chime, 0.5, 1.5)
	play.last_pickup_flash = player.pickup_flash
}

PICKUP_CHIME_THRESHOLD :: f32(1.45)

@(private = "file")
footsteps :: proc(play: ^Play, delta_seconds: f32) {
	player := play.battle.player
	bank := &play.sound
	if play.driving != nil || !player.controller.on_ground {
		bank.step_distance = 0
		return
	}
	speed := la.length([2]f32{player.controller.velocity.x, player.controller.velocity.z})
	bank.step_distance += speed * delta_seconds
	stride := SPRINT_FOOTSTEP_METERS if speed > Gameplay.WALK_SPEED * 1.2 else FOOTSTEP_METERS
	if player.controller.crouching do stride *= 0.8
	if bank.step_distance < stride do return
	bank.step_distance -= stride
	bank.step_flip = !bank.step_flip
	volume: f32 = 0.35 if !player.controller.crouching else 0.12
	if speed > Gameplay.WALK_SPEED * 1.2 do volume = 0.5
	play_here(play, &bank.step_a if bank.step_flip else &bank.step_b, volume, 0.9 + 0.2 * f32(int(player.controller.position.x * 13) % 3) / 2)
}

@(private = "file")
reload_click :: proc(play: ^Play) {
	state := play.battle.player.weapons[play.battle.player.current]
	reloading := state.reload_remaining_seconds > 0
	if reloading && !play.sound.was_reloading do play_here(play, &play.sound.click, 0.6)
	if !reloading && play.sound.was_reloading do play_here(play, &play.sound.click, 0.7, 1.3)
	play.sound.was_reloading = reloading
}

// The occupied vehicle's engine loop (pitched by speed; a tank is lower and heavier) or the helicopter's rotor beat (volume by rotor
// speed, pitch by how hard it is working).
@(private = "file")
vehicle_sounds :: proc(play: ^Play) {
	bank := &play.sound
	mixer := &bank.device.mixer
	index, driving := play.driving.?
	if !driving {
		if bank.engine_voice != 0 {Audio.Mixer_Stop(mixer, bank.engine_voice); bank.engine_voice = 0}
		if bank.rotor_voice != 0 {Audio.Mixer_Stop(mixer, bank.rotor_voice); bank.rotor_voice = 0}
		return
	}
	vehicle := play.vehicles[index]
	if vehicle.spec.is_aircraft {
		volume := 0.8 * vehicle.air.rotor
		pitch := 0.6 + 0.6 * vehicle.air.rotor + 0.1 * math.abs(vehicle.air.velocity.y) / 6
		if bank.rotor_voice == 0 do bank.rotor_voice = Audio.Mixer_Play(mixer, &bank.rotor, volume, 0, pitch, true)
		else do Audio.Mixer_Set(mixer, bank.rotor_voice, volume, 0, pitch)
		return
	}
	heavy := vehicle.spec.handling.tracked || vehicle.kind == .Cargo_Truck || vehicle.kind == .Armored_Carrier
	speed_fraction := math.abs(vehicle.body.speed) / vehicle.spec.handling.speed_forward_max
	volume := 0.25 + 0.3 * speed_fraction
	pitch := 0.7 + 0.9 * speed_fraction
	sound := &bank.engine_heavy if heavy else &bank.engine_light
	if bank.engine_voice == 0 do bank.engine_voice = Audio.Mixer_Play(mixer, sound, volume, 0, pitch, true)
	else do Audio.Mixer_Set(mixer, bank.engine_voice, volume, 0, pitch)
}

@(private = "file")
alarm_loop :: proc(play: ^Play) {
	bank := &play.sound
	mixer := &bank.device.mixer
	active := Mission.Alarm_Active(play.alarm)
	if active && bank.alarm_voice == 0 do bank.alarm_voice = Audio.Mixer_Play(mixer, &bank.alarm, 0.35, 0, 1, true)
	if !active && bank.alarm_voice != 0 {
		Audio.Mixer_Stop(mixer, bank.alarm_voice)
		bank.alarm_voice = 0
	}
}

door_sound :: proc(play: ^Play, position: [3]f32) {
	if play.sound.device == nil do return
	play_at(play, &play.sound.creak, 0.6, position)
}

// A low metallic knock each time a foot reaches a new rung, a heavier one on taking hold and on stepping off.
@(private = "file")
ladder_sounds :: proc(play: ^Play) {
	grip := play.battle.player.controller.grip
	bank := &play.sound
	if grip.phase == .Climbing && grip.rung != bank.ladder_rung && abs(grip.speed) > 0.1 do play_here(play, &bank.click, 0.28, 0.5 + 0.04 * f32(grip.rung % 3))
	if grip.phase != bank.ladder_phase && (grip.phase == .Mounting || bank.ladder_phase == .Topping_Out || (bank.ladder_phase != .None && grip.phase == .None)) {
		play_here(play, &bank.step_a, 0.45, 0.8)
	}
	bank.ladder_rung, bank.ladder_phase = grip.rung, grip.phase
}
