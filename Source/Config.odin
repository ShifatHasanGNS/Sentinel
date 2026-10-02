package main

import "core:strconv"

Config :: struct {
	capture_frames: int,
	capture_path:   string,
}

// Supported: --capture <frames> <path>
Config_Parse :: proc(arguments: []string) -> (config: Config) {
	for index := 0; index < len(arguments); index += 1 {
		if arguments[index] == "--capture" && index + 2 < len(arguments) {
			config.capture_frames, _ = strconv.parse_int(arguments[index + 1])
			config.capture_path = arguments[index + 2]
			index += 2
		}
	}
	return config
}
