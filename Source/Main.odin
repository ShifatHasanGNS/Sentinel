package main

import "../Engine/GPU"
import "../Engine/Platform"
import "../Game/Showroom"
import "core:os"

main :: proc() {
	config := Config_Parse(os.args[1:])
	window, window_ok := Platform.Window_Create("Sentinel", 1280, 720, config.capture_frames == 0)
	if !window_ok do os.exit(1)
	defer Platform.Window_Destroy(&window)
	showroom, showroom_ok := Showroom.Showroom_Create(window.framebuffer_width, window.framebuffer_height)
	if !showroom_ok do os.exit(1)
	defer Showroom.Showroom_Destroy(&showroom)
	clock: Platform.Clock

	for frame := 1; !Platform.Window_Should_Close(&window); frame += 1 {
		Platform.Clock_Tick(&clock)
		Showroom.Showroom_Update(&showroom, clock)
		Showroom.Showroom_Render(&showroom, window)
		if frame == config.capture_frames {
			GPU.Screenshot_Save(config.capture_path, int(window.framebuffer_width), int(window.framebuffer_height))
			break
		}
		Platform.Window_Present(&window)
	}
}
