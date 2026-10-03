package Sandbox

import "../Gameplay"
import "../Mission"
import "../Weapons"
import "core:fmt"
import "core:os"

SAVE_DIRECTORY :: "Saves"

// SENTINEL_SAVE_DIR redirects the save file (the scripted --autoplay check uses it so it never touches a real save).
save_directory :: proc() -> string {
	if override := os.get_env("SENTINEL_SAVE_DIR", context.temp_allocator); override != "" do return override
	return SAVE_DIRECTORY
}

save_path :: proc() -> string {
	return fmt.tprintf("%s/Profile.txt", save_directory())
}

// Reads the profile from disk, or an empty one when there is none or it cannot be read.
profile_load :: proc() -> Mission.Profile {
	data, error := os.read_entire_file(save_path(), context.temp_allocator)
	if error != nil do return {}
	return Mission.Save_Parse(string(data))
}

profile_write :: proc(profile: Mission.Profile) {
	os.make_directory(save_directory())
	text := Mission.Save_Format(profile)
	_ = os.write_entire_file(save_path(), transmute([]byte)text) // A failed save (read-only disk) must not stop the game.
}

// Captures where the player stands and what they carry, with how far the mission has got.
checkpoint_capture :: proc(play: ^Play) -> (checkpoint: Mission.Checkpoint) {
	player := play.battle.player
	checkpoint.valid = true
	checkpoint.objectives_done = play.mission.state.done
	checkpoint.position = player.controller.position
	checkpoint.yaw = player.yaw_radians
	checkpoint.health = player.health.current
	checkpoint.elapsed_seconds = play.mission.state.elapsed_seconds
	checkpoint.radar_destroyed = play.battle.targets[play.mission.radar_target].destroyed
	for weapon in Weapons.Weapon_Kind {
		slot := int(weapon)
		if slot >= Mission.WEAPON_SLOTS do continue
		checkpoint.ammo[slot], checkpoint.reserve[slot] = i32(player.weapons[weapon].ammo), i32(player.weapons[weapon].reserve)
	}
	return
}

// Puts the player back at the checkpoint with its health and ammunition (what a respawn does).
checkpoint_apply_to_player :: proc(play: ^Play, checkpoint: Mission.Checkpoint) {
	player := &play.battle.player
	player.controller.position = checkpoint.position
	player.controller.velocity = {}
	player.yaw_radians = checkpoint.yaw
	player.health.current = max(checkpoint.health, Gameplay.PLAYER_HEALTH * 0.5) // A respawn never starts you nearly dead.
	for weapon in Weapons.Weapon_Kind {
		slot := int(weapon)
		if slot >= Mission.WEAPON_SLOTS do continue
		player.weapons[weapon].ammo, player.weapons[weapon].reserve = int(checkpoint.ammo[slot]), int(checkpoint.reserve[slot])
	}
}

// Restores the mission as the checkpoint left it: objectives, the destroyed radar, the freed hostage, the clock.
checkpoint_apply_to_mission :: proc(play: ^Play, checkpoint: Mission.Checkpoint) {
	mission := &play.mission
	mission.state.done = checkpoint.objectives_done
	mission.state.elapsed_seconds = checkpoint.elapsed_seconds
	mission.state.status = .Active
	if checkpoint.radar_destroyed do play.battle.targets[mission.radar_target].destroyed = true
	if checkpoint.objectives_done[.Rescue_Hostage] do mission.hostage.rescued = true
}

// Called every frame: a new objective writes a checkpoint; finishing the mission records the time; a respawn returns to the checkpoint.
save_update :: proc(play: ^Play) {
	mission := &play.mission
	if !play.save_enabled do return
	player_dead := Gameplay.Health_Is_Dead(play.battle.player.health)
	if play.was_dead && !player_dead && play.profile.checkpoint.valid do checkpoint_apply_to_player(play, play.profile.checkpoint)
	play.was_dead = player_dead
	if mission.state.status == .Complete {
		if !play.completion_saved {
			play.completion_saved = true
			play.new_best = Mission.Profile_Record_Completion(&play.profile, mission.state.elapsed_seconds, mission.state.variant)
			profile_write(play.profile)
		}
		return
	}
	if mission.state.just_completed != {} && mission.state.status == .Active && mission.state.variant == .Rescue { // Checkpoints belong to the rescue mission.
		play.profile.checkpoint = checkpoint_capture(play)
		profile_write(play.profile)
	}
}

// "BEST 5:12" (and a new-best notice) on the mission-complete screen.
best_time_text :: proc(play: ^Play) -> string {
	best := play.profile.best_seconds if play.mission.state.variant == .Rescue else play.profile.night_best_seconds
	if best <= 0 do return ""
	seconds := int(best)
	label := "NEW BEST" if play.new_best else "BEST"
	return fmt.tprintf("%s %d:%02d", label, seconds / 60, seconds % 60)
}
