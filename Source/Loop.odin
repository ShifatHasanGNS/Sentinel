package main

import "../Engine/GPU"
import "../Engine/Platform"
import "core:fmt"
import "core:slice"
import "vendor:glfw"

BENCHMARK_WARMUP_FRAMES :: 10
BENCHMARK_FRAME_SECONDS :: 1.0 / 60 // Scripted time advances by this per frame, whatever the real frame time.

// What the loop needs from a scene. scripted_seconds < 0 means the player is in control.
Scene :: struct {
	user:   rawptr,
	update: proc(user: rawptr, clock: Platform.Clock, input: ^Platform.Input, scripted_seconds: f32),
	render: proc(user: rawptr, window: Platform.Window),
	report: proc(user: rawptr), // Optional; called when a benchmark ends.
	finished: proc(user: rawptr) -> bool, // Optional; the loop ends when this returns true (the scene wants to be recreated).
	handles_escape: bool, // The scene reacts to Escape itself (a pause menu); the loop then leaves it alone.
	wants_quit: proc(user: rawptr) -> bool, // Optional; true makes the loop close the window.
	cursor_stays_free: proc(user: rawptr) -> bool, // Optional; true (a pause menu) stops a click from capturing the mouse.
}

Run_Loop :: proc(window: ^Platform.Window, input: ^Platform.Input, config: Config, scene: Scene) {
	clock: Platform.Clock
	fullscreen_was_down, cursor_was_down: bool
	frame_milliseconds: [dynamic]f32
	defer delete(frame_milliseconds)
	interactive := config.capture_frames == 0
	for frame := 1; !Platform.Window_Should_Close(window); frame += 1 {
		if interactive && frame == 1 do Platform.Window_Show(window) // Shown only once the world is built, so the window never hangs half-drawn.
		if interactive && Platform.Window_Is_Hidden(window^) { // Minimised: sleep until restored, and do not count the wait as game time.
			if input.captured do Platform.Input_Capture_Mouse(input, false)
			Platform.Window_Wait_Events(window)
			clock.previous_seconds = glfw.GetTime()
			frame -= 1
			continue
		}
		Platform.Clock_Tick(&clock)
		if config.capture_frames == 0 do Platform.Input_Update(input) // Captures must not depend on where the mouse happens to be.
		if !input.captured do input.mouse_delta = {} // A free cursor must not turn the view.
		// The mouse is free until the player clicks in the window, and is freed again when another window takes focus, so the
		// title bar, the corners and the window buttons are always reachable.
		if interactive && config.benchmark_frames == 0 {
			if input.captured && !input.focused do Platform.Input_Capture_Mouse(input, false)
			stays_free := scene.cursor_stays_free != nil && scene.cursor_stays_free(scene.user)
			if !input.captured && input.focused && input.click_edge && !stays_free do Platform.Input_Capture_By_Click(input)
		}
		// F11 toggles fullscreen; F9 frees the cursor (to resize, move or minimise the window) and captures it again.
		fullscreen_down, cursor_down := Platform.Input_Key_Down(input, .F11), Platform.Input_Key_Down(input, .F9)
		if fullscreen_down && !fullscreen_was_down do Platform.Window_Toggle_Fullscreen(window)
		if cursor_down && !cursor_was_down && config.capture_frames == 0 && config.benchmark_frames == 0 do Platform.Input_Capture_Mouse(input, !input.captured)
		fullscreen_was_down, cursor_was_down = fullscreen_down, cursor_down
		if !scene.handles_escape && Platform.Input_Key_Down(input, .Escape) do Platform.Window_Request_Close(window)
		scripted_seconds: f32 = f32(frame) * BENCHMARK_FRAME_SECONDS if config.benchmark_frames > 0 else -1
		scene.update(scene.user, clock, input, scripted_seconds)
		scene.render(scene.user, window^)
		if scene.finished != nil && scene.finished(scene.user) do break
		if scene.wants_quit != nil && scene.wants_quit(scene.user) do Platform.Window_Request_Close(window)
		if frame > BENCHMARK_WARMUP_FRAMES && config.benchmark_frames > 0 do append(&frame_milliseconds, clock.delta_seconds * 1000)
		if frame == config.capture_frames {
			GPU.Screenshot_Save(config.capture_path, int(window.framebuffer_width), int(window.framebuffer_height))
			break
		}
		if frame == config.benchmark_frames {
			report_benchmark(frame_milliseconds[:])
			if scene.report != nil do scene.report(scene.user)
			break
		}
		Platform.Window_Present(window)
		free_all(context.temp_allocator)
	}
}

@(private = "file")
report_benchmark :: proc(milliseconds: []f32) {
	if len(milliseconds) == 0 do return
	slice.sort(milliseconds)
	total: f32
	for value in milliseconds do total += value
	fmt.printfln("frames %d: average %.2f ms, median %.2f ms, 99th percentile %.2f ms, worst %.2f ms", len(milliseconds), total / f32(len(milliseconds)), milliseconds[len(milliseconds) / 2], milliseconds[len(milliseconds) * 99 / 100], milliseconds[len(milliseconds) - 1])
}
