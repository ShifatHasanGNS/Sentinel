package Characters

import "core:math"

GAIT_DUTY_FACTOR :: 0.6 // Fraction of the cycle a foot is on the ground; above 0.5, so one foot is always down.

// How far a foot travels along the ground in stance: grows with speed, as people take longer steps when they hurry.
Gait_Stride_Meters :: proc(speed: f32) -> f32 {
	return clamp(0.35 + 0.15 * speed, 0.35, 0.9)
}

// During stance the foot moves back relative to the body at exactly the body's speed, covering `stride` in duty * T, so
// T = stride / (duty * speed) and the foot stays fixed on the ground.
Gait_Cycle_Seconds :: proc(speed: f32) -> f32 {
	assert(speed > 0, "Gait_Cycle_Seconds: speed must be positive")
	return Gait_Stride_Meters(speed) / (GAIT_DUTY_FACTOR * speed)
}

// How much of a gait cycle passes in delta_seconds at this speed (zero when standing: no division by a zero speed).
Gait_Phase_Advance :: proc(speed, delta_seconds: f32) -> f32 {
	if speed <= 0 do return 0
	return delta_seconds / Gait_Cycle_Seconds(speed)
}

// One foot's path over a cycle (phase in turns, wrapping), as (forward offset from under the hip, height above the ground).
// Stance: slide linearly from +stride/2 to -stride/2 on the ground. Swing: ease from -stride/2 to +stride/2 along a raised arc.
Gait_Foot :: proc(phase, stride_meters, lift_meters: f32) -> (forward, height: f32) {
	cycle_position := phase - math.floor(phase)
	if cycle_position < GAIT_DUTY_FACTOR {
		return stride_meters * (0.5 - cycle_position / GAIT_DUTY_FACTOR), 0
	}
	swing := (cycle_position - GAIT_DUTY_FACTOR) / (1 - GAIT_DUTY_FACTOR)
	return stride_meters * (-0.5 + math.smoothstep(f32(0), f32(1), swing)), lift_meters * math.sin(math.PI * swing)
}
