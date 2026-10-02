package World

import "core:math"

// A critically damped spring: the fastest return to its target that never overshoots. With x = value - target, v = velocity and
// angular frequency w, the exact solution over a step dt is
//   c1 = x, c2 = v + w x
//   x' = (c1 + c2 dt) e^(-w dt)
//   v' = (c2 - w (c1 + c2 dt)) e^(-w dt)
// Being exact, it is stable for any dt and gives the same result however time is sliced.
Spring :: struct {
	value:    f32,
	velocity: f32,
}

Spring_Step :: proc(spring: ^Spring, target, angular_frequency, delta_seconds: f32) {
	assert(angular_frequency > 0 && delta_seconds >= 0, "Spring_Step: frequency must be positive and time non-negative")
	offset := spring.value - target
	c2 := spring.velocity + angular_frequency * offset
	decay := math.exp(-angular_frequency * delta_seconds)
	spring.value = target + (offset + c2 * delta_seconds) * decay
	spring.velocity = (c2 - angular_frequency * (offset + c2 * delta_seconds)) * decay
}

Spring3 :: struct {
	value:    [3]f32,
	velocity: [3]f32,
}

Spring3_Step :: proc(spring: ^Spring3, target: [3]f32, angular_frequency, delta_seconds: f32) {
	for axis in 0 ..< 3 {
		single := Spring{spring.value[axis], spring.velocity[axis]}
		Spring_Step(&single, target[axis], angular_frequency, delta_seconds)
		spring.value[axis], spring.velocity[axis] = single.value, single.velocity
	}
}
