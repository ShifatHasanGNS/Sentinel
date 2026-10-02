package World

import "core:math"
import "core:testing"

@(test)
test_a_displaced_spring_follows_the_analytic_critically_damped_curve :: proc(t: ^testing.T) {
	omega: f32 = 12
	for seconds in ([5]f32{0.05, 0.1, 0.25, 0.5, 1}) {
		spring := Spring{value = 1}
		Spring_Step(&spring, 0, omega, seconds)
		expected := (1 + omega * seconds) * math.exp(-omega * seconds) // x(t) = (x0 + w x0 t) e^(-wt) for rest start
		testing.expect(t, abs(spring.value - expected) < 1e-5)
	}
}

// The exact solution is independent of how time is sliced: one big step equals a hundred small ones.
@(test)
test_step_size_does_not_matter :: proc(t: ^testing.T) {
	one := Spring{value = 2, velocity = -3}
	many := one
	Spring_Step(&one, 0.5, 9, 1)
	for _ in 0 ..< 100 do Spring_Step(&many, 0.5, 9, 0.01)
	testing.expect(t, abs(one.value - many.value) < 1e-4 && abs(one.velocity - many.velocity) < 1e-3)
}

@(test)
test_a_released_spring_never_overshoots_its_target :: proc(t: ^testing.T) {
	spring := Spring{value = 1}
	previous := spring.value
	for _ in 0 ..< 200 {
		Spring_Step(&spring, 0, 15, 0.01)
		testing.expect(t, spring.value >= 0 && spring.value <= previous)
		previous = spring.value
	}
	testing.expect(t, spring.value < 0.01)
}

// A velocity impulse from rest produces one bounded excursion, x(t) = v t e^(-wt), peaking at t = 1/w with value v / (w e).
@(test)
test_an_impulse_peaks_at_the_analytic_height_then_decays :: proc(t: ^testing.T) {
	omega, impulse: f32 = 10, 4
	spring := Spring{velocity = impulse}
	peak: f32
	for _ in 0 ..< 300 {
		Spring_Step(&spring, 0, omega, 0.005)
		peak = max(peak, spring.value)
	}
	testing.expect(t, abs(peak - impulse / (omega * math.E)) < 2e-3)
	testing.expect(t, abs(spring.value) < 0.01)
}

@(test)
test_energy_never_increases :: proc(t: ^testing.T) {
	omega: f32 = 8
	spring := Spring{value = 0.7, velocity = 5}
	energy :: proc(spring: Spring, omega: f32) -> f32 {
		return 0.5 * spring.velocity * spring.velocity + 0.5 * omega * omega * spring.value * spring.value
	}
	previous := energy(spring, omega)
	for _ in 0 ..< 200 {
		Spring_Step(&spring, 0, omega, 0.01)
		current := energy(spring, omega)
		testing.expect(t, current <= previous + 1e-4)
		previous = current
	}
}

@(test)
test_a_spring_at_rest_on_its_target_stays_put_and_huge_steps_are_stable :: proc(t: ^testing.T) {
	still := Spring{value = 3}
	Spring_Step(&still, 3, 10, 0.016)
	testing.expect_value(t, still.value, 3)
	testing.expect_value(t, still.velocity, 0)
	far := Spring{value = 100, velocity = 50}
	Spring_Step(&far, 0, 10, 60)
	testing.expect(t, abs(far.value) < 1e-6 && abs(far.velocity) < 1e-6)
}

@(test)
test_a_vector_spring_moves_each_axis_independently :: proc(t: ^testing.T) {
	spring := Spring3{value = {1, -2, 0}}
	Spring3_Step(&spring, {0, 0, 0}, 10, 0.1)
	single_x, single_y := Spring{value = 1}, Spring{value = -2}
	Spring_Step(&single_x, 0, 10, 0.1)
	Spring_Step(&single_y, 0, 10, 0.1)
	testing.expect(t, abs(spring.value.x - single_x.value) < 1e-6 && abs(spring.value.y - single_y.value) < 1e-6 && spring.value.z == 0)
}
