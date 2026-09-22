// Patrol Mode's node/light animation formulas, and the app-level Mode enum.
package main

import "core:math"

Mode :: enum {
	Patrol,
	Inspection,
}

MODE_NAME := [Mode]string{.Patrol = "Patrol", .Inspection = "Inspection"}

PATROL_FLOODLIGHT_SWEEP_RATE :: 0.5 // rad/s, argument to sin()
PATROL_FLOODLIGHT_SWEEP_AMPLITUDE :: math.PI * 50.0 / 180.0 // +-50 degrees

PATROL_RADAR_SPIN_RATE :: 0.35 // rad/s, continuous (not sine-bounded)

PATROL_BEACON_BLINK_RATE :: 1.2 // rad/s
PATROL_BEACON_BLINK_SHARPNESS :: 4.0

PATROL_TURRET_SCAN_RATE :: 0.15 // rad/s, argument to sin()
PATROL_TURRET_SCAN_AMPLITUDE :: math.PI * 25.0 / 180.0 // +-25 degrees

PATROL_JEEP_DIP_RATE :: 0.25 // rad/s, argument to cos()
PATROL_JEEP_DIP_AMPLITUDE :: math.PI * 6.0 / 180.0 // 6 degrees, downward only

PATROL_FENCE_FLICKER_RATE_A :: 3.7 // rad/s
PATROL_FENCE_FLICKER_RATE_B :: 8.3 // rad/s
PATROL_FENCE_FLICKER_AMPLITUDE :: 0.15 // fraction of base intensity

Patrol_Floodlight_Sweep_Angle :: proc(t: f32) -> f32 {
	return math.sin(t*PATROL_FLOODLIGHT_SWEEP_RATE) * PATROL_FLOODLIGHT_SWEEP_AMPLITUDE
}

Patrol_Radar_Spin_Angle :: proc(t: f32) -> f32 {
	return t * PATROL_RADAR_SPIN_RATE
}

// [PROGRESS-DEMO] Unused on this branch: Library/Lights (its caller) was removed.
Patrol_Beacon_Intensity_Factor :: proc(t: f32) -> f32 {
	return math.pow(max(math.sin(t*PATROL_BEACON_BLINK_RATE), 0), PATROL_BEACON_BLINK_SHARPNESS)
}

Patrol_Turret_Scan_Angle :: proc(t: f32) -> f32 {
	return math.sin(t*PATROL_TURRET_SCAN_RATE) * PATROL_TURRET_SCAN_AMPLITUDE
}

Patrol_Jeep_Dip_Angle :: proc(t: f32) -> f32 {
	return PATROL_JEEP_DIP_AMPLITUDE * (0.5 - 0.5*math.cos(t*PATROL_JEEP_DIP_RATE))
}

// [PROGRESS-DEMO] Unused on this branch: Library/Lights (its caller) was removed.
Patrol_Fence_Flicker_Factor :: proc(t: f32) -> f32 {
	return 1.0 + PATROL_FENCE_FLICKER_AMPLITUDE*(0.6*math.sin(t*PATROL_FENCE_FLICKER_RATE_A)+0.4*math.sin(t*PATROL_FENCE_FLICKER_RATE_B))
}

PATROL_MIN_SPEED_SCALE :: 0.1
PATROL_MAX_SPEED_SCALE :: 8.0
PATROL_SPEED_STEP_FACTOR :: 1.25
