package Mission

import "core:fmt"
import "core:strconv"
import "core:strings"

WEAPON_SLOTS :: 8

// What a checkpoint remembers: how far the mission got, and the player's state at that moment. Stored as plain text, one `key value...`
// per line, so a damaged file is readable and a missing key just keeps its default.
Checkpoint :: struct {
	valid:           bool,
	objectives_done: [Objective]bool,
	position:        [3]f32,
	yaw:             f32,
	health:          f32,
	ammo:            [WEAPON_SLOTS]i32,
	reserve:         [WEAPON_SLOTS]i32,
	elapsed_seconds: f32,
	radar_destroyed: bool,
}

// The persistent record across playthroughs.
Profile :: struct {
	best_seconds: f32, // 0 when no mission has been completed.
	completions:  int,
	checkpoint:   Checkpoint,
}

Save_Format :: proc(profile: Profile, allocator := context.temp_allocator) -> string {
	builder := strings.builder_make(allocator)
	fmt.sbprintfln(&builder, "best %f", profile.best_seconds)
	fmt.sbprintfln(&builder, "completions %d", profile.completions)
	checkpoint := profile.checkpoint
	if !checkpoint.valid do return strings.to_string(builder)
	fmt.sbprintfln(&builder, "checkpoint 1")
	for done, objective in checkpoint.objectives_done do if done do fmt.sbprintfln(&builder, "done %d", int(objective))
	fmt.sbprintfln(&builder, "position %f %f %f", checkpoint.position.x, checkpoint.position.y, checkpoint.position.z)
	fmt.sbprintfln(&builder, "yaw %f", checkpoint.yaw)
	fmt.sbprintfln(&builder, "health %f", checkpoint.health)
	fmt.sbprintfln(&builder, "elapsed %f", checkpoint.elapsed_seconds)
	fmt.sbprintfln(&builder, "radar %d", int(checkpoint.radar_destroyed))
	for slot in 0 ..< WEAPON_SLOTS do fmt.sbprintfln(&builder, "weapon %d %d %d", slot, checkpoint.ammo[slot], checkpoint.reserve[slot])
	return strings.to_string(builder)
}

// Reads what Save_Format wrote. Unknown lines, missing values and nonsense numbers are skipped, never fatal: a save file is user data.
Save_Parse :: proc(text: string) -> (profile: Profile) {
	remaining := text
	for line in strings.split_lines_iterator(&remaining) {
		fields := strings.fields(line, context.temp_allocator)
		if len(fields) < 2 do continue
		number :: proc(fields: []string, index: int) -> (value: f32, ok: bool) {
			if index >= len(fields) do return 0, false
			parsed, parsed_ok := strconv.parse_f32(fields[index])
			return parsed, parsed_ok
		}
		switch fields[0] {
		case "best":
			if value, ok := number(fields, 1); ok && value >= 0 do profile.best_seconds = value
		case "completions":
			if value, ok := number(fields, 1); ok && value >= 0 do profile.completions = int(value)
		case "checkpoint": profile.checkpoint.valid = fields[1] == "1"
		case "done":
			if value, ok := number(fields, 1); ok && int(value) >= 0 && int(value) < len(Objective) do profile.checkpoint.objectives_done[Objective(int(value))] = true
		case "position":
			x, ok_x := number(fields, 1)
			y, ok_y := number(fields, 2)
			z, ok_z := number(fields, 3)
			if ok_x && ok_y && ok_z do profile.checkpoint.position = {x, y, z}
		case "yaw":
			if value, ok := number(fields, 1); ok do profile.checkpoint.yaw = value
		case "health":
			if value, ok := number(fields, 1); ok && value > 0 do profile.checkpoint.health = value
		case "elapsed":
			if value, ok := number(fields, 1); ok && value >= 0 do profile.checkpoint.elapsed_seconds = value
		case "radar":
			if value, ok := number(fields, 1); ok do profile.checkpoint.radar_destroyed = value != 0
		case "weapon":
			slot, ok_slot := number(fields, 1)
			ammo, ok_ammo := number(fields, 2)
			reserve, ok_reserve := number(fields, 3)
			if ok_slot && ok_ammo && ok_reserve && int(slot) >= 0 && int(slot) < WEAPON_SLOTS && ammo >= 0 && reserve >= 0 {
				profile.checkpoint.ammo[int(slot)], profile.checkpoint.reserve[int(slot)] = i32(ammo), i32(reserve)
			}
		}
	}
	return
}

// A mission result: the best time keeps the smaller of the two; a first completion sets it.
Profile_Record_Completion :: proc(profile: ^Profile, seconds: f32) -> (new_best: bool) {
	profile.completions += 1
	profile.checkpoint = {}
	if profile.best_seconds <= 0 || seconds < profile.best_seconds {
		profile.best_seconds = seconds
		return true
	}
	return false
}
