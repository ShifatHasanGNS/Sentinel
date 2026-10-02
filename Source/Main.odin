package main

import "../Engine/Platform"
import "../Game/Sandbox"
import "../Game/Showroom"
import "core:os"

main :: proc() {
	config := Config_Parse(os.args[1:])
	interactive := config.capture_frames == 0
	benchmarking := config.benchmark_frames > 0
	width: i32 = 1920 if benchmarking else 1280
	height: i32 = 1080 if benchmarking else 720
	window, window_ok := Platform.Window_Create("Sentinel", width, height, interactive, !benchmarking)
	if !window_ok do os.exit(1)
	defer Platform.Window_Destroy(&window)
	input := Platform.Input_Create(&window)
	if interactive && config.benchmark_frames == 0 do Platform.Input_Capture_Mouse(&input, true)
	if config.benchmark_frames > 0 do Platform.Window_Set_Vsync(false)

	switch config.scene {
	case "showroom": run_showroom(&window, &input, config)
	case "catalogue": run_catalogue(&window, &input, config)
	case "soldiers": run_soldiers(&window, &input, config)
	case: run_sandbox(&window, &input, config)
	}
}

run_sandbox :: proc(window: ^Platform.Window, input: ^Platform.Input, config: Config) {
	sandbox, ok := Sandbox.Sandbox_Create(window.framebuffer_width, window.framebuffer_height, config.time_hours, config.view, config.demo)
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
		report = proc(user: rawptr) {
			Sandbox.Sandbox_Report((^Sandbox.Sandbox)(user))
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

run_catalogue :: proc(window: ^Platform.Window, input: ^Platform.Input, config: Config) {
	view, ok := Showroom.Catalogue_View_Create(window.framebuffer_width, window.framebuffer_height, config.object, config.time_hours)
	if !ok do os.exit(1)
	defer Showroom.Catalogue_View_Destroy(&view)
	Run_Loop(window, input, config, Scene{
		user = &view,
		update = proc(user: rawptr, clock: Platform.Clock, input: ^Platform.Input, scripted_seconds: f32) {
			Showroom.Catalogue_View_Update((^Showroom.Catalogue_View)(user), clock)
		},
		render = proc(user: rawptr, window: Platform.Window) {
			Showroom.Catalogue_View_Render((^Showroom.Catalogue_View)(user), window)
		},
	})
}

run_soldiers :: proc(window: ^Platform.Window, input: ^Platform.Input, config: Config) {
	lineup, ok := Showroom.Soldier_Lineup_Create(window.framebuffer_width, window.framebuffer_height, config.time_hours)
	if !ok do os.exit(1)
	defer Showroom.Soldier_Lineup_Destroy(&lineup)
	Run_Loop(window, input, config, Scene{
		user = &lineup,
		update = proc(user: rawptr, clock: Platform.Clock, input: ^Platform.Input, scripted_seconds: f32) {
			Showroom.Soldier_Lineup_Update((^Showroom.Soldier_Lineup)(user), clock)
		},
		render = proc(user: rawptr, window: Platform.Window) {
			Showroom.Soldier_Lineup_Render((^Showroom.Soldier_Lineup)(user), window)
		},
	})
}
