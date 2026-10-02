package Procedural

import "core:math"
import "core:testing"

SAMPLE_COUNT :: 4096

// Deterministic scatter of sample positions, independent of the noise under test.
sample_position :: proc(index: int) -> [3]f32 {
	golden := f32(0.6180339887)
	return {
		f32(index) * golden * 7.13 - 20,
		f32(index) * golden * 3.71 + 5,
		math.mod(f32(index) * golden * 11.9, 40) - 20,
	}
}

@(test)
test_gradient_noise_is_deterministic_and_seed_dependent :: proc(t: ^testing.T) {
	differs_between_seeds := false
	for index in 0 ..< 256 {
		position := sample_position(index)
		testing.expect_value(t, Noise_Gradient_3(position, 7), Noise_Gradient_3(position, 7))
		if Noise_Gradient_3(position, 7) != Noise_Gradient_3(position, 8) do differs_between_seeds = true
	}
	testing.expect(t, differs_between_seeds)
}

@(test)
test_gradient_noise_stays_within_unit_range :: proc(t: ^testing.T) {
	for index in 0 ..< SAMPLE_COUNT {
		value := Noise_Gradient_3(sample_position(index), 3)
		testing.expectf(t, abs(value) <= 1, "sample %d out of range: %f", index, value)
	}
}

// Gradient (Perlin) noise is zero at every integer lattice point by construction.
@(test)
test_gradient_noise_is_zero_at_lattice_points :: proc(t: ^testing.T) {
	for x in -3 ..< 3 do for y in -3 ..< 3 do for z in -3 ..< 3 {
		testing.expect_value(t, Noise_Gradient_3({f32(x), f32(y), f32(z)}, 5), 0)
	}
}

@(test)
test_gradient_noise_is_continuous :: proc(t: ^testing.T) {
	step: f32 = 1e-3
	slope_bound: f32 = 6
	for index in 0 ..< SAMPLE_COUNT {
		position := sample_position(index)
		change := abs(Noise_Gradient_3(position + {step, 0, 0}, 9) - Noise_Gradient_3(position, 9))
		testing.expectf(t, change <= slope_bound * step, "jump of %f at sample %d", change, index)
	}
}

@(test)
test_noise_is_not_constant :: proc(t: ^testing.T) {
	lowest, highest: f32 = 1, -1
	for index in 0 ..< SAMPLE_COUNT {
		value := Noise_Gradient_3(sample_position(index), 3)
		lowest, highest = min(lowest, value), max(highest, value)
	}
	testing.expect(t, highest - lowest > 0.8)
}

@(test)
test_fbm_with_one_octave_equals_base_noise :: proc(t: ^testing.T) {
	for index in 0 ..< 64 {
		position := sample_position(index)
		testing.expect_value(t, Noise_Fbm_3(position, 4, 1), Noise_Gradient_3(position, 4))
	}
}

@(test)
test_fbm_stays_within_unit_range_and_adds_detail :: proc(t: ^testing.T) {
	step: f32 = 0.02
	rougher_count := 0
	for index in 0 ..< SAMPLE_COUNT {
		position := sample_position(index)
		testing.expect(t, abs(Noise_Fbm_3(position, 4, 6)) <= 1)
		smooth_change := abs(Noise_Fbm_3(position + {step, 0, 0}, 4, 1) - Noise_Fbm_3(position, 4, 1))
		detailed_change := abs(Noise_Fbm_3(position + {step, 0, 0}, 4, 6) - Noise_Fbm_3(position, 4, 6))
		if detailed_change > smooth_change do rougher_count += 1
	}
	testing.expect(t, rougher_count > SAMPLE_COUNT / 2)
}
