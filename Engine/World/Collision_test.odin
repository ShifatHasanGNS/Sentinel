package World

import "core:math"
import "core:testing"

flat_ground :: proc(data: rawptr, x, z: f32) -> f32 {
	return 0
}

sloped_ground :: proc(data: rawptr, x, z: f32) -> f32 {
	return 0.1 * x // A gentle 5.7 degree rise toward +X.
}

FLAT :: Ground{height_at = flat_ground}

walk :: proc(controller: ^Controller, world: ^Collision_World, ground: Ground, wish: [2]f32, seconds: f32) {
	steps := int(seconds * 60)
	for _ in 0 ..< steps do Controller_Step(controller, world^, ground, wish, false, 1.0 / 60)
}

@(test)
test_a_wall_stops_the_controller :: proc(t: ^testing.T) {
	world: Collision_World
	defer Collision_World_Destroy(&world)
	append(&world.boxes, Box_Solid({5, 0, -10}, {6, 3, 10}))
	controller := Controller_Create({0, 0, 0})
	walk(&controller, &world, FLAT, {5, 0}, 3)
	testing.expect(t, controller.position.x + CONTROLLER_RADIUS_METERS <= 5.001)
	testing.expect(t, controller.position.x > 5 - CONTROLLER_RADIUS_METERS - 0.05) // It did reach the wall.
}

@(test)
test_the_controller_slides_along_a_wall :: proc(t: ^testing.T) {
	world: Collision_World
	defer Collision_World_Destroy(&world)
	append(&world.boxes, Box_Solid({5, 0, -10}, {6, 3, 30}))
	controller := Controller_Create({4, 0, 0})
	walk(&controller, &world, FLAT, {5, 5}, 2) // Diagonally into the wall.
	testing.expect(t, controller.position.x + CONTROLLER_RADIUS_METERS <= 5.001)
	testing.expect(t, controller.position.z > 8) // The along-wall half of the motion survived.
}

@(test)
test_small_ledges_are_stepped_onto_and_tall_ones_block :: proc(t: ^testing.T) {
	world: Collision_World
	defer Collision_World_Destroy(&world)
	append(&world.boxes, Box_Solid({3, 0, -5}, {6, 0.3, 5})) // A kerb.
	append(&world.boxes, Box_Solid({-6, 0, -5}, {-3, 1.0, 5})) // A wall-high block.
	over_kerb := Controller_Create({0, 0, 0})
	walk(&over_kerb, &world, FLAT, {3, 0}, 1.5)
	testing.expect(t, over_kerb.position.x > 3.5 && abs(over_kerb.position.y - 0.3) < 1e-3 && over_kerb.on_ground)
	into_block := Controller_Create({0, 0, 0})
	walk(&into_block, &world, FLAT, {-3, 0}, 3)
	testing.expect(t, into_block.position.x - CONTROLLER_RADIUS_METERS >= -3.001 && into_block.position.y == 0)
}

@(test)
test_the_controller_follows_the_terrain_up_and_down :: proc(t: ^testing.T) {
	world: Collision_World
	defer Collision_World_Destroy(&world)
	ground := Ground{height_at = sloped_ground}
	controller := Controller_Create({0, 0, 0})
	walk(&controller, &world, ground, {3, 0}, 2)
	testing.expect(t, abs(controller.position.y - 0.1 * controller.position.x) < 1e-3 && controller.on_ground)
	walk(&controller, &world, ground, {-3, 0}, 2)
	testing.expect(t, abs(controller.position.y - 0.1 * controller.position.x) < 1e-3 && controller.on_ground)
}

// With gravity g and take-off speed v, a jump peaks at v^2 / 2g after v / g seconds and lands after 2v / g.
@(test)
test_a_jump_follows_the_analytic_parabola :: proc(t: ^testing.T) {
	world: Collision_World
	defer Collision_World_Destroy(&world)
	controller := Controller_Create({0, 0, 0})
	Controller_Step(&controller, world, FLAT, {}, false, 1.0 / 120)
	peak, air_time: f32
	jumped := false
	for step in 0 ..< 400 {
		Controller_Step(&controller, world, FLAT, {}, !jumped, 1.0 / 120)
		jumped = true
		peak = max(peak, controller.position.y)
		if !controller.on_ground do air_time += 1.0 / 120
		if step > 5 && controller.on_ground do break
	}
	testing.expect(t, abs(peak - JUMP_SPEED_METERS_PER_SECOND * JUMP_SPEED_METERS_PER_SECOND / (2 * GRAVITY_METERS_PER_SECOND_SQUARED)) < 0.04)
	testing.expect(t, abs(air_time - 2 * JUMP_SPEED_METERS_PER_SECOND / GRAVITY_METERS_PER_SECOND_SQUARED) < 0.04)
}

@(test)
test_a_huge_step_does_not_tunnel_through_a_thin_wall :: proc(t: ^testing.T) {
	world: Collision_World
	defer Collision_World_Destroy(&world)
	append(&world.boxes, Box_Solid({5, 0, -10}, {5.1, 3, 10}))
	controller := Controller_Create({0, 0, 0})
	for _ in 0 ..< 10 do Controller_Step(&controller, world, FLAT, {30, 0}, false, 0.2) // 6 m per step, far more than the wall is thick.
	testing.expect(t, controller.position.x + CONTROLLER_RADIUS_METERS <= 5.001)
}

@(test)
test_the_controller_cannot_walk_into_a_building :: proc(t: ^testing.T) {
	world: Collision_World
	defer Collision_World_Destroy(&world)
	append(&world.boxes, Box_Solid({-9, 0, -3}, {9, 3, 3}))
	for heading in 0 ..< 24 {
		angle := f32(heading) * math.PI / 12
		controller := Controller_Create({math.cos(angle) * 20, 0, math.sin(angle) * 20})
		walk(&controller, &world, FLAT, {-math.cos(angle) * 4, -math.sin(angle) * 4}, 8)
		inside := controller.position.x > -9 + 0.01 && controller.position.x < 9 - 0.01 && abs(controller.position.z) < 3 - 0.01
		testing.expectf(t, !inside, "walked into the building from heading %d at (%.2f, %.2f)", heading, controller.position.x, controller.position.z)
	}
}

@(test)
test_controller_is_deterministic :: proc(t: ^testing.T) {
	world: Collision_World
	defer Collision_World_Destroy(&world)
	append(&world.boxes, Box_Solid({5, 0, -10}, {6, 3, 10}))
	first, second := Controller_Create({0, 0, 1}), Controller_Create({0, 0, 1})
	walk(&first, &world, FLAT, {4, 2}, 2)
	walk(&second, &world, FLAT, {4, 2}, 2)
	testing.expect_value(t, first, second)
}

// A crouching body fits under a 1.4 m beam, cannot stand up beneath it, and stands again once clear.
@(test)
test_a_crouching_controller_fits_under_a_low_beam_and_cannot_stand_there :: proc(t: ^testing.T) {
	world: Collision_World
	defer Collision_World_Destroy(&world)
	append(&world.boxes, Box_Solid({5, 1.4, -10}, {9, 1.6, 10})) // A beam 1.4 m above the ground.
	standing := Controller_Create({0, 0, 0})
	walk(&standing, &world, FLAT, {4, 0}, 3)
	testing.expect(t, standing.position.x < 5) // Blocked.
	crouching := Controller_Create({0, 0, 0})
	Controller_Set_Crouch(&crouching, world, true)
	walk(&crouching, &world, FLAT, {4, 0}, 1.75)
	testing.expect(t, crouching.position.x > 6 && crouching.position.x < 8.5) // Underneath.
	Controller_Set_Crouch(&crouching, world, false)
	testing.expect(t, crouching.crouching) // Cannot stand under the beam.
	walk(&crouching, &world, FLAT, {4, 0}, 3)
	Controller_Set_Crouch(&crouching, world, false)
	testing.expect(t, !crouching.crouching) // Clear of it: stands up.
	testing.expect_value(t, Controller_Height(crouching), CONTROLLER_HEIGHT_METERS)
}
