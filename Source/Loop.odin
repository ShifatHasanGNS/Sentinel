package main

import "../Engine/GPU"
import "../Engine/Platform"
import "core:fmt"
import "core:slice"

BENCHMARK_WARMUP_FRAMES :: 10
BENCHMARK_FRAME_SECONDS :: 1.0 / 60 // Scripted time advances by this per frame, whatever the real frame time.

// What the loop needs from a scene. scripted_seconds < 0 means the player is in control.
Scene :: struct {
	user:   rawptr,
	update: proc(user: rawptr, clock: Platform.Clock, input: ^Platform.Input, scripted_seconds: f32),
	render: proc(user: rawptr, window: Platform.Window),
	report: proc(user: rawptr), // Optional; called when a benchmark ends.
	finished: proc(user: rawptr) -> bool, // Optional; the loop ends when this returns true (the scene wants to be recreated).
}

Run_Loop :: proc(window: ^Platform.Window, input: ^Platform.Input, config: Config, scene: Scene) {
	clock: Platform.Clock
	frame_milliseconds: [dynamic]f32
	defer delete(frame_milliseconds)
	for frame := 1; !Platform.Window_Should_Close(window); frame += 1 {
		Platform.Clock_Tick(&clock)
		if config.capture_frames == 0 do Platform.Input_Update(input) // Captures must not depend on where the mouse happens to be.
		if Platform.Input_Key_Down(input, .Escape) do Platform.Window_Request_Close(window)
		scripted_seconds: f32 = f32(frame) * BENCHMARK_FRAME_SECONDS if config.benchmark_frames > 0 else -1
		scene.update(scene.user, clock, input, scripted_seconds)
		scene.render(scene.user, window^)
		if scene.finished != nil && scene.finished(scene.user) do break
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
