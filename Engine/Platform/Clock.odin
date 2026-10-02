package Platform

import "vendor:glfw"

FRAME_SECONDS_MAX :: 0.1

Clock :: struct {
	previous_seconds: f64,
	delta_seconds:    f32,
	elapsed_seconds:  f32,
}

// Delta is capped so a stall (window drag, breakpoint) cannot teleport the simulation.
Clock_Tick :: proc(clock: ^Clock) {
	now := glfw.GetTime()
	clock.delta_seconds = f32(min(now - clock.previous_seconds, FRAME_SECONDS_MAX))
	clock.previous_seconds = now
	clock.elapsed_seconds += clock.delta_seconds
}
