package World

import "core:math"
import "core:testing"

// Seams: Controller_Step and Raycast_World against yaw-turned solids.

// A 10 m x 0.4 m x 3 m wall along X, turned 45 degrees about +Y, centred on the origin.
diagonal_wall :: proc() -> Solid {
	return Solid{center = {0, 1.5, 0}, half_extents = {5, 1.5, 0.2}, yaw_radians = math.PI / 4}
}

// The wall's axis-aligned bounds span about +-3.6 on both axes, so a body at (3, 3) is inside that square yet well clear of the
// wall itself: an axis-aligned stand-in would block it, an exact turned box does not.
// Yaw +45 degrees turns the wall's local +X to world (cos, -sin) = (0.707, -0.707), so it runs from (-3.5, 3.5) to (3.5, -3.5).
// Its axis-aligned bounds are about +-3.6 on both axes, so a body at (-3, -3) lies inside that square yet 4.2 m from the wall
// itself: an axis-aligned stand-in would block it, an exact turned box does not.
@(test)
test_a_turned_wall_does_not_block_the_empty_corners_of_its_bounds :: proc(t: ^testing.T) {
	world: Collision_World
	defer Collision_World_Destroy(&world)
	append(&world.boxes, diagonal_wall())
	controller := Controller_Create({-3, 0, -3})
	walk(&controller, &world, FLAT, {0.5, 0.5}, 1)
	testing.expect(t, controller.position.x > -2.6 && controller.position.z > -2.6)
}

@(test)
test_a_turned_wall_blocks_a_body_walking_into_its_face :: proc(t: ^testing.T) {
	world: Collision_World
	defer Collision_World_Destroy(&world)
	append(&world.boxes, diagonal_wall())
	controller := Controller_Create({4, 0, 4})
	walk(&controller, &world, FLAT, {-3, -3}, 4)
	// The wall face passes through the origin; the body must stop at distance radius + half thickness from that line.
	distance_to_line := (controller.position.x + controller.position.z) / math.sqrt(f32(2))
	testing.expect(t, distance_to_line >= 0.2 + CONTROLLER_RADIUS_METERS - 0.05)
	testing.expect(t, distance_to_line < 0.2 + CONTROLLER_RADIUS_METERS + 0.2)
}

@(test)
test_rays_hit_a_turned_solid_at_the_right_distance_with_a_turned_normal :: proc(t: ^testing.T) {
	world: Collision_World
	defer Collision_World_Destroy(&world)
	append(&world.boxes, diagonal_wall())
	// From (6, 1, 6) straight toward the origin: the face is 0.2 m before the line x + z = 0, so the distance is
	// (|6| * sqrt(2) - 0.2) = 8.285.
	direction := [3]f32{-1, 0, -1} / math.sqrt(f32(2))
	hit := Raycast_World(world, FLAT, {6, 1, 6}, direction, 50)
	testing.expect(t, hit.hit && hit.kind == .Box)
	testing.expect(t, abs(hit.distance - (6 * math.sqrt(f32(2)) - 0.2)) < 1e-3)
	testing.expect(t, abs(hit.normal.x - 1 / math.sqrt(f32(2))) < 1e-4 && abs(hit.normal.z - 1 / math.sqrt(f32(2))) < 1e-4)
}

@(test)
test_temporary_solids_block_and_disabled_ones_do_not :: proc(t: ^testing.T) {
	world: Collision_World
	defer Collision_World_Destroy(&world)
	append(&world.temporary, Box_Solid({5, 0, -10}, {6, 3, 10}))
	blocked := Controller_Create({0, 0, 0})
	walk(&blocked, &world, FLAT, {5, 0}, 3)
	testing.expect(t, blocked.position.x < 5)
	world.temporary[0].disabled = true
	through := Controller_Create({0, 0, 0})
	walk(&through, &world, FLAT, {5, 0}, 3)
	testing.expect(t, through.position.x > 6)
	testing.expect(t, !Raycast_World(world, FLAT, {0, 1, 0}, {1, 0, 0}, 50).hit || Raycast_World(world, FLAT, {0, 1, 0}, {1, 0, 0}, 50).kind == .Terrain)
}

@(test)
test_the_controller_reports_its_horizontal_velocity :: proc(t: ^testing.T) {
	world: Collision_World
	defer Collision_World_Destroy(&world)
	controller := Controller_Create({0, 0, 0})
	Controller_Step(&controller, world, FLAT, {2, -1}, false, 1.0 / 60)
	testing.expect_value(t, controller.velocity.x, 2)
	testing.expect_value(t, controller.velocity.z, -1)
}
