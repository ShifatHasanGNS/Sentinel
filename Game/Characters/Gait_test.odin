package Characters

import "core:math"
import "core:testing"

@(test)
test_the_foot_path_is_continuous_and_periodic :: proc(t: ^testing.T) {
	stride, lift: f32 = 1, 0.12
	for boundary in ([3]f32{0, GAIT_DUTY_FACTOR, 1}) {
		before_x, before_y := Gait_Foot(boundary - 1e-4, stride, lift)
		after_x, after_y := Gait_Foot(boundary + 1e-4, stride, lift)
		testing.expect(t, abs(before_x - after_x) < 1e-3 && abs(before_y - after_y) < 1e-3)
	}
	for phase in ([4]f32{0.1, 0.35, 0.7, 0.95}) {
		x, y := Gait_Foot(phase, stride, lift)
		next_x, next_y := Gait_Foot(phase + 1, stride, lift)
		testing.expect(t, abs(x - next_x) < 1e-5 && abs(y - next_y) < 1e-5)
	}
}

// Walk a body forward at constant speed; throughout a stance a foot's world position must not move: no skating.
@(test)
test_stance_feet_do_not_slide_over_the_ground :: proc(t: ^testing.T) {
	for speed in ([3]f32{1, 2.5, 5}) {
		stride, cycle := Gait_Stride_Meters(speed), Gait_Cycle_Seconds(speed)
		for stance_cycle in 0 ..< 2 {
			first_world_x: f32
			for step in 0 ..= 50 {
				phase := 0.02 + (GAIT_DUTY_FACTOR - 0.04) * f32(step) / 50
				seconds := (f32(stance_cycle) + phase) * cycle
				forward, height := Gait_Foot(phase, stride, 0.1)
				world_x := speed * seconds + forward
				if step == 0 do first_world_x = world_x
				testing.expect_value(t, height, 0)
				testing.expect(t, abs(world_x - first_world_x) < 1e-3)
			}
		}
	}
}

@(test)
test_at_least_one_foot_is_always_on_the_ground :: proc(t: ^testing.T) {
	for step in 0 ..< 200 {
		phase := f32(step) / 200
		_, left_height := Gait_Foot(phase, 1, 0.1)
		_, right_height := Gait_Foot(phase + 0.5, 1, 0.1)
		testing.expect(t, left_height == 0 || right_height == 0)
		testing.expect(t, left_height >= 0 && right_height >= 0)
	}
}

@(test)
test_the_swing_peaks_at_the_lift_height_mid_swing :: proc(t: ^testing.T) {
	lift: f32 = 0.15
	mid_swing: f32 = GAIT_DUTY_FACTOR + (1 - GAIT_DUTY_FACTOR) / 2
	_, height := Gait_Foot(mid_swing, 1, lift)
	testing.expect(t, abs(height - lift) < 1e-4)
	for step in 0 ..< 100 {
		_, sample := Gait_Foot(f32(step) / 100, 1, lift)
		testing.expect(t, sample <= lift + 1e-5)
	}
}

@(test)
test_faster_walking_takes_longer_strides_at_a_higher_cadence :: proc(t: ^testing.T) {
	testing.expect(t, Gait_Stride_Meters(1) < Gait_Stride_Meters(2) && Gait_Stride_Meters(2) < Gait_Stride_Meters(4))
	testing.expect(t, Gait_Cycle_Seconds(1) > Gait_Cycle_Seconds(2) && Gait_Cycle_Seconds(2) > Gait_Cycle_Seconds(4))
	for speed in ([3]f32{0.5, 1.5, 4}) { // A cycle covers the stride divided by the duty factor in distance.
		testing.expect(t, abs(speed * Gait_Cycle_Seconds(speed) * GAIT_DUTY_FACTOR - Gait_Stride_Meters(speed)) < 1e-4)
	}
}

@(test)
test_phase_advance_completes_a_cycle_in_one_cycle_time_and_is_zero_when_standing :: proc(t: ^testing.T) {
	testing.expect_value(t, Gait_Phase_Advance(0, 0.1), 0)
	for speed in ([3]f32{0.8, 3, 6}) do testing.expect(t, abs(Gait_Phase_Advance(speed, Gait_Cycle_Seconds(speed)) - 1) < 1e-4)
}
