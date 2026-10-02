package World

import "core:math"
import "core:testing"

// Seam: Ground_Vehicle_Step(vehicle, handling, input, world, ground, ignore_solid, dt).

CAR :: Vehicle_Handling{
	speed_forward_max = 20, speed_reverse_max = 6, acceleration = 5, brake = 12, drag = 2,
	wheel_base = 3, steer_angle_max = 0.5, half_width = 1, half_length = 2, height = 1.8,
}
TANK :: Vehicle_Handling{
	speed_forward_max = 10, speed_reverse_max = 4, acceleration = 3, brake = 8, drag = 3,
	turn_rate_max = 1.2, tracked = true, half_width = 1.5, half_length = 3.5, height = 2.5,
}

drive :: proc(vehicle: ^Ground_Vehicle, handling: Vehicle_Handling, input: Vehicle_Input, world: Collision_World, ground: Ground, seconds: f32, ignore := -1) {
	for _ in 0 ..< int(seconds * 60) do Ground_Vehicle_Step(vehicle, handling, input, world, ground, ignore, 1.0 / 60)
}

@(test)
test_throttle_accelerates_to_the_top_speed_and_no_further :: proc(t: ^testing.T) {
	world: Collision_World
	vehicle: Ground_Vehicle
	drive(&vehicle, CAR, {throttle = 1}, world, FLAT, 1)
	testing.expect(t, abs(vehicle.speed - 5) < 0.1) // 5 m/s^2 for one second.
	drive(&vehicle, CAR, {throttle = 1}, world, FLAT, 10)
	testing.expect_value(t, vehicle.speed, 20)
	drive(&vehicle, CAR, {throttle = -1}, world, FLAT, 20)
	testing.expect_value(t, vehicle.speed, -6) // Reverse is slower.
}

@(test)
test_a_released_throttle_coasts_to_rest_and_the_brake_stops_sooner :: proc(t: ^testing.T) {
	world: Collision_World
	coasting, braking := Ground_Vehicle{speed = 10}, Ground_Vehicle{speed = 10}
	drive(&coasting, CAR, {}, world, FLAT, 2)
	drive(&braking, CAR, {brake = true}, world, FLAT, 2)
	testing.expect(t, abs(coasting.speed - 6) < 0.1) // Drag 2 m/s^2.
	testing.expect_value(t, braking.speed, 0)
	drive(&coasting, CAR, {}, world, FLAT, 10)
	testing.expect_value(t, coasting.speed, 0)
}

// Driving along +Z (yaw 0), a right turn goes toward -X (the vehicle's right when facing +Z).
@(test)
test_a_car_turns_only_while_moving_and_right_means_right :: proc(t: ^testing.T) {
	world: Collision_World
	still: Ground_Vehicle
	drive(&still, CAR, {steer = 1}, world, FLAT, 2)
	testing.expect_value(t, still.yaw_radians, 0) // No rolling, no turning.
	moving := Ground_Vehicle{speed = 8}
	drive(&moving, CAR, {throttle = 0.4, steer = 0.3}, world, FLAT, 1)
	testing.expect(t, moving.position.x < -0.5 && moving.position.z > 6) // Curved off to the right while going forward.
	testing.expect(t, moving.yaw_radians < 0)
	reversing := Ground_Vehicle{speed = -4}
	drive(&reversing, CAR, {steer = 1}, world, FLAT, 1)
	testing.expect(t, reversing.yaw_radians > 0) // Reversing with the wheel right swings the nose left.
}

@(test)
test_a_tracked_vehicle_pivots_in_place :: proc(t: ^testing.T) {
	world: Collision_World
	tank: Ground_Vehicle
	drive(&tank, TANK, {steer = -1}, world, FLAT, 2)
	testing.expect(t, tank.yaw_radians > 1.5 && tank.yaw_radians < 2.6) // About 1.2 rad/s, minus the steering ramp.
	testing.expect(t, abs(tank.position.x) < 1e-4 && abs(tank.position.z) < 1e-4)
}

@(test)
test_the_hull_rests_on_a_slope_with_the_matching_pitch :: proc(t: ^testing.T) {
	world: Collision_World
	vehicle: Ground_Vehicle
	drive(&vehicle, CAR, {}, world, Ground{height_at = sloped_ground}, 2)
	// sloped_ground rises 0.1 per meter toward +X. Facing +Z the vehicle's right is -X, so it leans left: negative roll.
	expected_roll := -math.atan(f32(0.1))
	testing.expect(t, abs(vehicle.roll_radians - expected_roll) < 0.01)
	testing.expect(t, abs(vehicle.pitch_radians) < 0.01)
	drive(&vehicle, CAR, {}, world, Ground{height_at = sloped_ground}, 0.1)
	testing.expect(t, abs(vehicle.position.y - 0) < 0.01)
}

@(test)
test_a_wall_stops_the_hull_at_any_heading_and_it_never_overlaps :: proc(t: ^testing.T) {
	for yaw in ([3]f32{0, 0.65, -2.2}) {
		world: Collision_World
		defer Collision_World_Destroy(&world)
		// A 20 m wall across the path, 30 m ahead along the heading.
		heading := [3]f32{math.sin(yaw), 0, math.cos(yaw)}
		append(&world.boxes, Solid{center = heading * 30 + {0, 1.5, 0}, half_extents = {10, 1.5, 0.3}, yaw_radians = yaw})
		vehicle := Ground_Vehicle{yaw_radians = yaw}
		drive(&vehicle, CAR, {throttle = 1}, world, FLAT, 12)
		testing.expectf(t, !hull_hits_solid(world, -1, CAR, vehicle.position, vehicle.yaw_radians), "heading %.2f: the hull ended inside the wall", yaw)
		distance := vehicle.position.x * heading.x + vehicle.position.z * heading.z
		testing.expectf(t, distance > 26 && distance < 28, "heading %.2f: stopped at %.2f m (wall face at 29.7, hull reaches 2)", yaw, distance)
	}
}

@(test)
test_low_kerbs_are_driven_over_and_the_vehicles_own_solid_is_ignored :: proc(t: ^testing.T) {
	world: Collision_World
	defer Collision_World_Destroy(&world)
	append(&world.boxes, Box_Solid({-3, 0, 12}, {3, 0.3, 13})) // A kerb under the clearance.
	append(&world.boxes, Box_Solid({-1, 0, -2}, {1, 1.5, 2})) // The vehicle's own solid.
	vehicle := Ground_Vehicle{}
	drive(&vehicle, CAR, {throttle = 1}, world, FLAT, 6, 1)
	testing.expect(t, vehicle.position.z > 20)
}

@(test)
test_temporary_solids_such_as_trees_block_a_vehicle :: proc(t: ^testing.T) {
	world: Collision_World
	defer Collision_World_Destroy(&world)
	append(&world.temporary, Solid{center = {0, 2, 20}, half_extents = {0.3, 2, 0.3}})
	vehicle := Ground_Vehicle{}
	drive(&vehicle, CAR, {throttle = 1}, world, FLAT, 8)
	testing.expect(t, vehicle.position.z < 18.2)
}

// A vehicle that starts overlapping a solid (parked too close) must be able to drive away instead of being stuck.
@(test)
test_a_vehicle_that_starts_inside_a_solid_can_drive_out :: proc(t: ^testing.T) {
	world: Collision_World
	defer Collision_World_Destroy(&world)
	append(&world.boxes, Solid{center = {0.8, 1.5, 0}, half_extents = {0.1, 1.5, 0.1}}) // A post inside the hull's footprint.
	vehicle := Ground_Vehicle{}
	drive(&vehicle, CAR, {throttle = 1}, world, FLAT, 4)
	testing.expect(t, vehicle.position.z > 10)
}
