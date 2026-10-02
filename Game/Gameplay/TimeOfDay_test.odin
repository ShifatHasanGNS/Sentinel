package Gameplay

import "core:math"
import "core:math/linalg"
import "core:testing"

luminance :: proc(color: [3]f32) -> f32 {
	return 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b
}

@(test)
test_sun_vector_is_a_unit_vector_that_peaks_at_noon_toward_the_south :: proc(t: ^testing.T) {
	highest, highest_hour: f32 = -2, 0
	for step in 0 ..< 96 {
		hours := f32(step) * 0.25
		sun := Sun_Direction_To_Sun(hours)
		testing.expect(t, abs(linalg.length(sun) - 1) < 1e-5)
		if sun.y > highest do highest, highest_hour = sun.y, hours
	}
	testing.expect_value(t, highest_hour, 12)
	noon := Sun_Direction_To_Sun(12)
	testing.expect(t, abs(noon.x) < 1e-5 && noon.z > 0 && noon.y > 0.9) // South in the northern hemisphere: +Z.
}

@(test)
test_sun_rises_in_the_east_sets_in_the_west_and_is_below_the_horizon_at_midnight :: proc(t: ^testing.T) {
	testing.expect(t, Sun_Direction_To_Sun(6).x > 0.9)
	testing.expect(t, Sun_Direction_To_Sun(18).x < -0.9)
	testing.expect(t, Sun_Direction_To_Sun(0).y < -0.3)
	for hours in ([3]f32{23, 0, 1}) do testing.expect(t, Sun_Direction_To_Sun(hours).y < 0)
}

@(test)
test_sun_elevation_rises_until_noon_and_mirrors_after :: proc(t: ^testing.T) {
	for step in 0 ..< 48 {
		hours := f32(step) * 0.25
		testing.expect(t, Sun_Direction_To_Sun(hours + 0.25).y > Sun_Direction_To_Sun(hours).y)
	}
	for offset in ([4]f32{1, 3, 5, 7.5}) {
		morning, afternoon := Sun_Direction_To_Sun(12 - offset), Sun_Direction_To_Sun(12 + offset)
		testing.expect(t, abs(morning.y - afternoon.y) < 1e-5 && abs(morning.x + afternoon.x) < 1e-5 && abs(morning.z - afternoon.z) < 1e-5)
	}
}

@(test)
test_sunlight_fades_at_the_horizon_and_warms_toward_it :: proc(t: ^testing.T) {
	previous: f32 = -1
	for step in 0 ..= 40 {
		elevation_sine := -0.3 + f32(step) * 0.04 // From well below the horizon to nearly overhead.
		light := Sunlight_For_Elevation(elevation_sine)
		testing.expect(t, light.intensity >= 0 && light.intensity <= SUN_INTENSITY_NOON)
		testing.expect(t, light.intensity >= previous)
		testing.expect(t, light.color.r >= 0 && light.color.g >= 0 && light.color.b >= 0 && light.color.r <= 1 && light.color.b <= 1)
		previous = light.intensity
	}
	testing.expect_value(t, Sunlight_For_Elevation(-0.3).intensity, 0)
	low, high := Sunlight_For_Elevation(0.05), Sunlight_For_Elevation(0.95)
	testing.expect(t, low.color.r / low.color.b > 1.5) // Orange near the horizon.
	testing.expect(t, abs(high.color.r - high.color.b) < 0.2) // Nearly white overhead.
}

@(test)
test_the_moon_stands_opposite_the_sun_and_only_lights_the_night :: proc(t: ^testing.T) {
	noon_moon := Moonlight_For_Sun(Sun_Direction_To_Sun(12))
	midnight_sun := Sun_Direction_To_Sun(0)
	midnight_moon := Moonlight_For_Sun(midnight_sun)
	testing.expect_value(t, noon_moon.intensity, 0)
	testing.expect(t, midnight_moon.intensity > 0 && midnight_moon.intensity < SUN_INTENSITY_NOON * 0.1)
	testing.expect(t, linalg.dot(midnight_moon.to_moon, midnight_sun) < -0.999)
}

@(test)
test_sky_colours_are_dark_at_night_blue_at_noon_and_red_at_the_horizon_at_dusk :: proc(t: ^testing.T) {
	noon, dusk, night := Sky_Colors_For_Sun(Sun_Direction_To_Sun(12)), Sky_Colors_For_Sun(Sun_Direction_To_Sun(18.4)), Sky_Colors_For_Sun(Sun_Direction_To_Sun(0))
	for colors in ([3][3][3]f32{{noon.zenith, noon.horizon, noon.ground}, {dusk.zenith, dusk.horizon, dusk.ground}, {night.zenith, night.horizon, night.ground}}) {
		for color in colors do testing.expect(t, color.r >= 0 && color.g >= 0 && color.b >= 0)
	}
	testing.expect(t, luminance(night.zenith) < 0.05 * luminance(noon.zenith))
	testing.expect(t, noon.zenith.b > noon.zenith.r * 1.5)
	testing.expect(t, dusk.horizon.r > dusk.horizon.b)
}

// Eye adaptation: the camera exposure rises as the sun sets so night scenes stay readable, and is 1 in full daylight.
@(test)
test_exposure_is_one_in_daylight_and_rises_smoothly_toward_night :: proc(t: ^testing.T) {
	testing.expect_value(t, Exposure_For_Elevation(0.9), 1)
	testing.expect_value(t, Exposure_For_Elevation(0.3), 1)
	testing.expect(t, Exposure_For_Elevation(-0.5) >= EXPOSURE_NIGHT - 1e-4 && Exposure_For_Elevation(-0.5) <= EXPOSURE_NIGHT + 1e-4)
	previous: f32 = 0
	for step in 0 ..= 40 {
		exposure := Exposure_For_Elevation(0.9 - f32(step) * 0.035) // From noon down below the horizon.
		testing.expect(t, exposure >= 1 && exposure <= EXPOSURE_NIGHT)
		testing.expect(t, exposure >= previous)
		previous = exposure
	}
}
