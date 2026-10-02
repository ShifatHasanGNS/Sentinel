package World

import "core:math"
import "core:testing"

// Seam: Aircraft_Step(aircraft, handling, input, world, ground, ignore_solid, dt).

HELI :: Aircraft_Handling{
	climb_speed_max = 6, descent_speed_max = 5, vertical_acceleration = 4,
	forward_speed_max = 30, strafe_speed_max = 12, horizontal_acceleration = 8,
	yaw_rate_max = 1.4, tilt_max = 0.3, tilt_follow_per_second = 4,
	spool_up_seconds = 4, spool_down_seconds = 6, lift_rotor_threshold = 0.9,
	half_width = 1.3, half_length = 3.0, hull_center_z = -2.0, height = 3.7,
}

fly :: proc(aircraft: ^Aircraft, input: Aircraft_Input, world: Collision_World, ground: Ground, seconds: f32) {
	for _ in 0 ..< int(seconds * 60) do Aircraft_Step(aircraft, HELI, input, world, ground, -1, 1.0 / 60)
}

@(test)
test_the_rotor_spools_up_and_the_helicopter_cannot_lift_before_it_is_ready :: proc(t: ^testing.T) {
	world: Collision_World
	aircraft: Aircraft
	fly(&aircraft, {engine = true, collective = 1}, world, FLAT, 2)
	testing.expect(t, abs(aircraft.rotor - 0.5) < 0.02)
	testing.expect_value(t, aircraft.position.y, 0) // Half spooled: still on the pad.
	testing.expect(t, aircraft.on_ground)
	fly(&aircraft, {engine = true, collective = 1}, world, FLAT, 4)
	testing.expect_value(t, aircraft.rotor, 1)
	testing.expect(t, aircraft.position.y > 5 && !aircraft.on_ground)
}

@(test)
test_collective_climbs_releasing_it_hovers_and_down_lands_gently :: proc(t: ^testing.T) {
	world: Collision_World
	aircraft := Aircraft{rotor = 1}
	fly(&aircraft, {engine = true, collective = 1}, world, FLAT, 3)
	testing.expect(t, abs(aircraft.velocity.y - 6) < 0.1)
	height := aircraft.position.y
	fly(&aircraft, {engine = true}, world, FLAT, 2)
	testing.expect(t, abs(aircraft.velocity.y) < 0.01) // Hover holds altitude.
	testing.expect(t, aircraft.position.y - height < 6) // Only the braking drift.
	fly(&aircraft, {engine = true, collective = -1}, world, FLAT, 12)
	testing.expect_value(t, aircraft.position.y, 0)
	testing.expect(t, aircraft.on_ground)
}

@(test)
test_forward_and_sideways_follow_the_heading_and_the_ground_holds_it_still :: proc(t: ^testing.T) {
	world: Collision_World
	grounded := Aircraft{rotor = 1}
	fly(&grounded, {engine = true, pitch = 1}, world, FLAT, 2)
	testing.expect_value(t, grounded.position.z, 0) // On the ground, no sliding about.
	aircraft := Aircraft{rotor = 1, position = {0, 20, 0}}
	fly(&aircraft, {engine = true, pitch = 1}, world, FLAT, 5)
	testing.expect(t, aircraft.position.z > 60 && abs(aircraft.position.x) < 0.01) // Heading +Z.
	testing.expect(t, aircraft.pitch_radians < -0.2) // Nose down.
	sideways := Aircraft{rotor = 1, position = {0, 20, 0}}
	fly(&sideways, {engine = true, roll = 1}, world, FLAT, 4)
	testing.expect(t, sideways.position.x < -20 && abs(sideways.position.z) < 0.01) // The right of +Z is -X.
	testing.expect(t, sideways.roll_radians > 0.2)
}

@(test)
test_yaw_turns_the_nose_only_with_the_rotor_turning :: proc(t: ^testing.T) {
	world: Collision_World
	stopped := Aircraft{}
	fly(&stopped, {yaw = 1}, world, FLAT, 1)
	testing.expect_value(t, stopped.yaw_radians, 0)
	running := Aircraft{rotor = 1}
	fly(&running, {engine = true, yaw = 1}, world, FLAT, 1)
	testing.expect(t, abs(running.yaw_radians + 1.4) < 0.02) // Right is a negative yaw.
}

@(test)
test_a_tall_wall_stops_the_hull_but_a_low_one_is_flown_over :: proc(t: ^testing.T) {
	world: Collision_World
	defer Collision_World_Destroy(&world)
	append(&world.boxes, Box_Solid({-20, 0, 40}, {20, 10, 41})) // 10 m tall wall.
	high := Aircraft{rotor = 1, position = {0, 15, 0}}
	low := Aircraft{rotor = 1, position = {0, 5, 0}}
	fly(&high, {engine = true, pitch = 1}, world, FLAT, 6)
	fly(&low, {engine = true, pitch = 1}, world, FLAT, 6)
	testing.expect(t, high.position.z > 80) // Passed over.
	testing.expect(t, low.position.z < 40) // Stopped at the wall.
	testing.expect(t, !aircraft_hull_hits_solid(world, -1, HELI, low.position, low.yaw_radians))
}

@(test)
test_the_ground_stops_a_fall_and_a_hard_landing_reports_its_speed :: proc(t: ^testing.T) {
	world: Collision_World
	falling := Aircraft{position = {0, 40, 0}} // No rotor: it drops.
	crashed := false
	for _ in 0 ..< 60 * 10 {
		Aircraft_Step(&falling, HELI, {}, world, FLAT, -1, 1.0 / 60)
		if falling.impact_speed > 0 do crashed = true
	}
	testing.expect(t, crashed)
	testing.expect_value(t, falling.position.y, 0)
	slope := Ground{height_at = sloped_ground}
	landing := Aircraft{rotor = 1, position = {20, 6, 0}}
	fly(&landing, {engine = true, collective = -1}, world, slope, 8)
	testing.expect(t, abs(landing.position.y - 2.0) < 0.05) // 0.1 * 20 m of rise at x = 20.
	_ = math.PI
}
