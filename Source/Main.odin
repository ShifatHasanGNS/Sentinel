package main

import "../Engine/Platform"
import "../Game/Sandbox"
import "../Game/Showroom"
import "core:os"

main :: proc() {
	config := Config_Parse(os.args[1:])
	interactive := config.capture_frames == 0
	window, window_ok := Platform.Window_Create("Sentinel", 1280, 720, interactive)
	if !window_ok do os.exit(1)
	defer Platform.Window_Destroy(&window)
	input := Platform.Input_Create(&window)
	if interactive && config.benchmark_frames == 0 do Platform.Input_Capture_Mouse(&input, true)
	if config.benchmark_frames > 0 do Platform.Window_Set_Vsync(false)

	if config.scene == "showroom" {
		run_showroom(&window, &input, config)
	} else {
		run_sandbox(&window, &input, config)
	}
}

run_sandbox :: proc(window: ^Platform.Window, input: ^Platform.Input, config: Config) {
	sandbox, ok := Sandbox.Sandbox_Create(window.framebuffer_width, window.framebuffer_height, config.time_hours)
	if !ok do os.exit(1)
	defer Sandbox.Sandbox_Destroy(&sandbox)
	Run_Loop(window, input, config, Scene{
		user = &sandbox,
		update = proc(user: rawptr, clock: Platform.Clock, input: ^Platform.Input, scripted_seconds: f32) {
			Sandbox.Sandbox_Update((^Sandbox.Sandbox)(user), clock, input, scripted_seconds)
		},
		render = proc(user: rawptr, window: Platform.Window) {
			Sandbox.Sandbox_Render((^Sandbox.Sandbox)(user), window)
		},
	})
}

run_showroom :: proc(window: ^Platform.Window, input: ^Platform.Input, config: Config) {
	showroom, ok := Showroom.Showroom_Create(window.framebuffer_width, window.framebuffer_height)
	if !ok do os.exit(1)
	defer Showroom.Showroom_Destroy(&showroom)
	Run_Loop(window, input, config, Scene{
		user = &showroom,
		update = proc(user: rawptr, clock: Platform.Clock, input: ^Platform.Input, scripted_seconds: f32) {
			Showroom.Showroom_Update((^Showroom.Showroom)(user), clock)
		},
		render = proc(user: rawptr, window: Platform.Window) {
			Showroom.Showroom_Render((^Showroom.Showroom)(user), window)
		},
	})
}
