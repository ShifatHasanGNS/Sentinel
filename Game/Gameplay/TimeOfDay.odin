package Gameplay

import "core:math"

LATITUDE_DEGREES :: 35.0
DECLINATION_DEGREES :: 15.0 // Sun's angle north of the celestial equator: a late-spring day, so noon stands 70 degrees high.
SUN_INTENSITY_NOON :: 4.0
MOON_INTENSITY :: 0.25

// Unit vector from the scene toward the sun in a frame with +X east, +Y up, +Z south. From spherical astronomy:
// with hour angle h (zero at noon, 15 degrees per hour), latitude phi and declination delta,
//   east = -cos(delta) sin(h),  up = sin(phi) sin(delta) + cos(phi) cos(delta) cos(h),
//   south = sin(phi) cos(delta) cos(h) - cos(phi) sin(delta).
Sun_Direction_To_Sun :: proc(hours: f32) -> [3]f32 {
	hour_angle := (hours - 12) * math.PI / 12
	latitude, declination := math.to_radians(f32(LATITUDE_DEGREES)), math.to_radians(f32(DECLINATION_DEGREES))
	return {
		-math.cos(declination) * math.sin(hour_angle),
		math.sin(latitude) * math.sin(declination) + math.cos(latitude) * math.cos(declination) * math.cos(hour_angle),
		math.sin(latitude) * math.cos(declination) * math.cos(hour_angle) - math.cos(latitude) * math.sin(declination),
	}
}

Sunlight :: struct {
	color:     [3]f32, // Linear RGB.
	intensity: f32,
}

// Sunlight dims to nothing as the sun reaches the horizon and turns orange: a low sun crosses more air,
// which scatters the blue out of the direct beam.
Sunlight_For_Elevation :: proc(elevation_sine: f32) -> Sunlight {
	warmth := math.smoothstep(f32(0), f32(0.5), elevation_sine)
	horizon_color := [3]f32{1, 0.45, 0.18}
	overhead_color := [3]f32{1, 0.96, 0.88}
	return Sunlight{math.lerp(horizon_color, overhead_color, warmth), SUN_INTENSITY_NOON * math.smoothstep(f32(-0.02), f32(0.35), elevation_sine)}
}

Moonlight :: struct {
	to_moon:   [3]f32,
	color:     [3]f32,
	intensity: f32,
}

// The moon stands opposite the sun and only counts when it is above the horizon and the sun is not.
Moonlight_For_Sun :: proc(to_sun: [3]f32) -> Moonlight {
	to_moon := -to_sun
	above_horizon := math.smoothstep(f32(0), f32(0.2), to_moon.y)
	night := 1 - math.smoothstep(f32(-0.1), f32(0.05), to_sun.y)
	return Moonlight{to_moon, {0.55, 0.65, 0.9}, MOON_INTENSITY * above_horizon * night}
}

Sky_Colors :: struct {
	zenith:  [3]f32,
	horizon: [3]f32,
	ground:  [3]f32,
}

// Gradient colours for ambient light (the visible sky is the atmosphere shader). Blend night, day and a dusk horizon by sun elevation.
Sky_Colors_For_Sun :: proc(to_sun: [3]f32) -> Sky_Colors {
	elevation := to_sun.y
	day := math.smoothstep(f32(-0.1), f32(0.25), elevation)
	twilight := math.smoothstep(f32(-0.2), f32(0), elevation) * (1 - math.smoothstep(f32(0), f32(0.35), elevation))
	zenith := math.lerp([3]f32{0.004, 0.007, 0.02}, [3]f32{0.12, 0.28, 0.65}, day)
	horizon := math.lerp([3]f32{0.01, 0.012, 0.02}, [3]f32{0.6, 0.72, 0.88}, day)
	horizon = math.lerp(horizon, [3]f32{0.85, 0.4, 0.18}, twilight * 0.9)
	return Sky_Colors{zenith, horizon, horizon * 0.12}
}

EXPOSURE_NIGHT :: 10.0

// Camera exposure for the sun's elevation (its sine): 1 in daylight, rising to EXPOSURE_NIGHT once the sun is well below
// the horizon, like the eye adapting to the dark. Log-linear in between so the change looks even.
Exposure_For_Elevation :: proc(elevation_sine: f32) -> f32 {
	darkness := math.smoothstep(f32(0.25), f32(-0.25), elevation_sine)
	return math.pow(f32(EXPOSURE_NIGHT), darkness)
}
