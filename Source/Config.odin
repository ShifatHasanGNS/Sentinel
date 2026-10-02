package main

import "core:strconv"

Config :: struct {
	scene:            string, // "sandbox", "showroom", "catalogue" or "soldiers".
	view:             string, // Sandbox starting camera: base, gate, yard, airfield, command (default: overview).
	object:           string, // With --scene catalogue: show only this object (e.g. Jeep).
	capture_frames:   int,
	capture_path:     string,
	benchmark_frames: int,
	time_hours:       f32, // Negative: let the day cycle run.
}

// Flags: --scene <name>, --view <name>, --object <name>, --capture <frames> <path>, --benchmark <frames>, --time <hours>
Config_Parse :: proc(arguments: []string) -> (config: Config) {
	config = Config{scene = "sandbox", time_hours = -1}
	for index := 0; index < len(arguments); index += 1 {
		switch arguments[index] {
		case "--scene":
			if index + 1 < len(arguments) {config.scene = arguments[index + 1]; index += 1}
		case "--view":
			if index + 1 < len(arguments) {config.view = arguments[index + 1]; index += 1}
		case "--object":
			if index + 1 < len(arguments) {config.object = arguments[index + 1]; index += 1}
		case "--capture":
			if index + 2 < len(arguments) {
				config.capture_frames, _ = strconv.parse_int(arguments[index + 1])
				config.capture_path = arguments[index + 2]
				index += 2
			}
		case "--benchmark":
			if index + 1 < len(arguments) {config.benchmark_frames, _ = strconv.parse_int(arguments[index + 1]); index += 1}
		case "--time":
			if index + 1 < len(arguments) {config.time_hours, _ = strconv.parse_f32(arguments[index + 1]); index += 1}
		}
	}
	return config
}
