// Patrol.odin — Patrol Mode's node/light animation formulas (roadmap step
// 9, CLAUDE.md §7/§9; Prompts.md Session 12) and the app-level Mode enum
// Source/Main.odin switches on with Tab.
//
// The camera PATH itself lives in Library/Camera/Camera.odin
// (Patrol_Camera_Pose) instead of here — that package's own header has
// anticipated a "Patrol_Camera_At"-shaped addition since Session 2, and the
// path is theme-agnostic math (a circle, a height bob, a drifting look
// target) with no SENTINEL-specific node knowledge. Everything in THIS
// file, by contrast, is deliberately SENTINEL-specific (named node/light
// knowledge that Library/Camera and Library/Lights' own Build_Rig must
// never leak into their general-purpose APIs, CLAUDE.md §13.1) — floodlight
// sweep, radar spin, beacon blink, and the optional "life touches" (turret
// scan, jeep headlight dip, one fence lamp flicker) — which is why it lives
// in Source/, not a Library package.
//
// Every Patrol_* proc below is a PURE function: (time) -> (angle | factor),
// no Scene/Light access, no side effects. Source/Main.odin's main loop
// reads these values and writes them into scene.Nodes/light_rig itself —
// the craft skill's "push ifs up, centralize state mutation in the parent"
// principle: this file computes WHAT should change, Main.odin's loop is the
// ONE place that actually changes it (the same split Library/Scene/
// Transform.odin's Local_Matrix (compute) vs. Main.odin's node loop
// (mutate) already uses).
package main

import "core:math"

// Mode is the app-level state Tab switches between (this session's task).
// Both modes draw through the exact same render path (CLAUDE.md §2 item
// 9) — only what DRIVES the camera and a handful of node/light transforms
// differs (the task's own wording), which is why every Patrol_* animation
// below is only ever APPLIED while current_mode == .Patrol (Source/
// Main.odin's main loop) rather than running unconditionally regardless of
// mode.
Mode :: enum {
	Patrol,
	Inspection,
}

MODE_NAME := [Mode]string{.Patrol = "Patrol", .Inspection = "Inspection"}

// PATROL_FLOODLIGHT_SWEEP_RATE/AMPLITUDE carry over Session 8's temporary
// demo-animation values unchanged (that session's DEMO_FLOODLIGHT_SWEEP_
// RATE/AMPLITUDE, Source/Main.odin, now deleted along with the rest of
// that temporary block) — already tuned to look reasonable there, no
// reason to re-pick them just because the code moved to its real home.
PATROL_FLOODLIGHT_SWEEP_RATE :: 0.5 // rad/s, argument to sin()
PATROL_FLOODLIGHT_SWEEP_AMPLITUDE :: math.PI * 50.0 / 180.0 // +-50 degrees

// Continuous, not sine-bounded — "rotates continuously" (this session's
// task) — so this is a plain rate, not an amplitude/rate pair the way
// every sine-driven angle below is.
PATROL_RADAR_SPIN_RATE :: 0.35 // rad/s

// Beacon blink: "intensity = a smooth/sharp function of a runtime sine (no
// lookup table)" (this session's task, verbatim). max(sin, 0) already
// gives one bright half-cycle followed by one fully-dark half-cycle per
// period — a literal "blink", not a continuous breathing glow — and
// raising THAT to a power > 1 sharpens the bright half further into a
// brief flash instead of a slow fade in/out, which reads more like a
// warning beacon and less like a pulsing lamp.
PATROL_BEACON_BLINK_RATE :: 1.2 // rad/s
PATROL_BEACON_BLINK_SHARPNESS :: 4.0

// --- Optional life touches (this session's task explicitly marks these
// optional, and explicitly says to keep the tank HULL and the jeep ROOT
// static in Patrol — only the turret and the two jeep headlight NODES
// animate, never scene.Nodes[tank_hull]/scene.Nodes[jeep] themselves). ---

PATROL_TURRET_SCAN_RATE :: 0.15 // rad/s, argument to sin()
PATROL_TURRET_SCAN_AMPLITUDE :: math.PI * 25.0 / 180.0 // +-25 degrees

// A "dip" reads as periodically tilting DOWN and back to level, never past
// level upward — a raised-cosine (0.5 - 0.5*cos(...)) stays in [0, 1]
// rather than a plain sine's [-1, 1], which is exactly that shape: rests
// at 0 (level), eases down to the full dip, eases back to level, never
// negative (never tilts up past level).
PATROL_JEEP_DIP_RATE :: 0.25 // rad/s, argument to cos()
PATROL_JEEP_DIP_AMPLITUDE :: math.PI * 6.0 / 180.0 // 6 degrees, downward only

// One fence lamp flickers (Source/Main.odin picks the first one Library/
// Lights.Build_Rig appends, via find_light_by_parent); the other 7 stay at
// their fixed Lights.FENCE_LAMP_INTENSITY. Two sine terms at a
// non-integer frequency ratio (3.7 : 8.3) sum to a semi-irregular
// waveform — still a pure, deterministic formula (CLAUDE.md §2 item 5, no
// lookup table, no random-number generator), but visually closer to a real
// flickering bulb than one clean sine would be. This is the same "combine
// a couple of periodic terms instead of one" idea Shaders/Scene.glsl's
// hash21 already uses for area-light jitter, applied here to a light's
// INTENSITY instead of a sample position.
PATROL_FENCE_FLICKER_RATE_A :: 3.7 // rad/s
PATROL_FENCE_FLICKER_RATE_B :: 8.3 // rad/s
PATROL_FENCE_FLICKER_AMPLITUDE :: 0.15 // fraction of base intensity

// Patrol_Floodlight_Sweep_Angle drives the Watchtower Floodlight Head's own
// Y rotation — the two floodlight spot lights are children of that node
// (Library/Lights.Build_Rig), so they sweep for free through the
// hierarchy, exactly this session's task wording ("the two spots follow
// through the hierarchy").
Patrol_Floodlight_Sweep_Angle :: proc(t: f32) -> f32 {
	return math.sin(t*PATROL_FLOODLIGHT_SWEEP_RATE) * PATROL_FLOODLIGHT_SWEEP_AMPLITUDE
}

Patrol_Radar_Spin_Angle :: proc(t: f32) -> f32 {
	return t * PATROL_RADAR_SPIN_RATE
}

// Patrol_Beacon_Intensity_Factor returns a [0, 1] multiplier for the
// beacon light's own base Intensity (Library/Lights.BEACON_INTENSITY) —
// see the rate/sharpness constants' own comments above for the shape.
Patrol_Beacon_Intensity_Factor :: proc(t: f32) -> f32 {
	return math.pow(max(math.sin(t*PATROL_BEACON_BLINK_RATE), 0), PATROL_BEACON_BLINK_SHARPNESS)
}

Patrol_Turret_Scan_Angle :: proc(t: f32) -> f32 {
	return math.sin(t*PATROL_TURRET_SCAN_RATE) * PATROL_TURRET_SCAN_AMPLITUDE
}

Patrol_Jeep_Dip_Angle :: proc(t: f32) -> f32 {
	return PATROL_JEEP_DIP_AMPLITUDE * (0.5 - 0.5*math.cos(t*PATROL_JEEP_DIP_RATE))
}

// Patrol_Fence_Flicker_Factor returns a multiplier CENTRED ON 1.0 (unlike
// the beacon's [0, 1] blink factor) — the target light's own base
// intensity times this factor should read as "flickering around its
// normal brightness", not "fading between off and on".
Patrol_Fence_Flicker_Factor :: proc(t: f32) -> f32 {
	return 1.0 + PATROL_FENCE_FLICKER_AMPLITUDE*(0.6*math.sin(t*PATROL_FENCE_FLICKER_RATE_A)+0.4*math.sin(t*PATROL_FENCE_FLICKER_RATE_B))
}

// PATROL_MIN_SPEED_SCALE/MAX_SPEED_SCALE bound Source/Main.odin's `,`/`.`
// speed-adjust keys (this session's task: "speed keys") — multiplicative
// steps (x1.25 / /1.25 per press, not +/- a fixed amount) so the control
// feels proportional across a wide range, the same reasoning a media
// player's speed control usually uses.
PATROL_MIN_SPEED_SCALE :: 0.1
PATROL_MAX_SPEED_SCALE :: 8.0
PATROL_SPEED_STEP_FACTOR :: 1.25
