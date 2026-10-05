package World

import "core:math"
import "core:testing"

// Seam: Controller_Ladder_Step (with Controller_Step for falling) and Ladder_Prompt_For, on a synthetic wall-and-ladder.

// A 3 m block whose +Z face is at z = 0, with a 3.2 m ladder on that face (its front face at z = 0.25). The roof is at y = 3.
ladder_world :: proc() -> Collision_World {
	world: Collision_World
	append(&world.boxes, Box_Solid({-2, 0, -4}, {2, 3, 0}))
	append(&world.ladders, Solid{center = {0, 1.6, 0.15}, half_extents = {0.3, 1.6, 0.1}})
	return world
}

TOWARD_WALL :: [2]f32{0, -1}
AWAY_FROM_WALL :: [2]f32{0, 1}
DT :: f32(1.0 / 60)

// Steps for up to `seconds` with a fixed input; returns the seconds used and stops early when `until` says so.
run_ladder :: proc(controller: ^Controller, world: Collision_World, input: Ladder_Input, seconds: f32, until: proc(c: Controller) -> bool = nil) -> f32 {
	elapsed: f32
	for elapsed < seconds {
		holding := Controller_Ladder_Step(controller, world, FLAT, input, DT)
		if !holding do Controller_Step(controller, world, FLAT, {}, false, DT)
		elapsed += DT
		if until != nil && until(controller^) do break
	}
	return elapsed
}

@(test)
test_a_ladder_is_climbed_to_the_roof_in_a_realistic_time_and_the_climber_ends_standing :: proc(t: ^testing.T) {
	world := ladder_world()
	defer Collision_World_Destroy(&world)
	controller := Controller_Create({0, 0, 0.9})
	seconds := run_ladder(&controller, world, {climb = 1, facing = TOWARD_WALL}, 12, proc(c: Controller) -> bool { return c.grip.phase == .None && c.position.y > 2.5 })
	testing.expect_value(t, controller.grip.phase, Ladder_Phase.None)
	testing.expect(t, controller.on_ground)
	testing.expect(t, abs(controller.position.y - 3) < 0.06 && controller.position.z < 0 && controller.position.z > -1.2)
	testing.expectf(t, seconds > 3.2 && seconds < 5.6, "the climb took %.2f s", seconds) // 3.2 m at about 1.1 m/s, plus mounting and the step over.
}

@(test)
test_the_climb_eases_in_and_settles_at_the_climbing_speed :: proc(t: ^testing.T) {
	world := ladder_world()
	defer Collision_World_Destroy(&world)
	controller := Controller_Create({0, 0, 0.9})
	run_ladder(&controller, world, {climb = 1, facing = TOWARD_WALL}, LADDER_MOUNT_SECONDS + 0.05)
	testing.expect_value(t, controller.grip.phase, Ladder_Phase.Climbing)
	testing.expect(t, controller.grip.speed > 0 && controller.grip.speed < 0.5) // Not an instant jump to full speed.
	run_ladder(&controller, world, {climb = 1, facing = TOWARD_WALL}, 0.8)
	testing.expect(t, abs(controller.grip.speed - LADDER_CLIMB_SPEED) < 0.01)
	run_ladder(&controller, world, {climb = 0, facing = TOWARD_WALL}, 0.6)
	testing.expect(t, abs(controller.grip.speed) < 0.01) // Letting go of the key stops the climber on the rung.
	testing.expect_value(t, controller.grip.phase, Ladder_Phase.Climbing)
}

@(test)
test_a_ladder_is_not_grabbed_by_accident :: proc(t: ^testing.T) {
	world := ladder_world()
	defer Collision_World_Destroy(&world)
	cases := []struct{ position: [3]f32, input: Ladder_Input, label: string }{
		{{0, 0, 0.9}, {climb = 1, facing = AWAY_FROM_WALL}, "facing away"},
		{{0, 0, 0.9}, {climb = 1, facing = {1, 0}}, "facing sideways"},
		{{0, 0, 0.9}, {climb = 0, facing = TOWARD_WALL}, "not pushing forward"},
		{{2.0, 0, 1.0}, {climb = 1, facing = TOWARD_WALL}, "walking past two meters to the side"},
		{{0, 0, 2.6}, {climb = 1, facing = TOWARD_WALL}, "too far out"},
		{{0, 0, 1.4}, {climb = 1, facing = TOWARD_WALL}, "a meter and a half short of the ladder"},
	}
	for entry in cases {
		controller := Controller_Create(entry.position)
		testing.expectf(t, !Controller_Ladder_Step(&controller, world, FLAT, entry.input, DT), "grabbed while %s", entry.label)
	}
	pressing_use := Controller_Create({0, 0, 0.9})
	testing.expect(t, Controller_Ladder_Step(&pressing_use, world, FLAT, {use = true, facing = AWAY_FROM_WALL}, DT)) // The use key grabs from any facing.
}

@(test)
test_stepping_back_off_the_bottom_rung_lets_go_onto_the_ground :: proc(t: ^testing.T) {
	world := ladder_world()
	defer Collision_World_Destroy(&world)
	controller := Controller_Create({0, 0, 0.9})
	run_ladder(&controller, world, {climb = 1, facing = TOWARD_WALL}, 1.2) // Up a little.
	testing.expect(t, controller.grip.height > 0.4)
	run_ladder(&controller, world, {climb = -1, facing = TOWARD_WALL}, 6, proc(c: Controller) -> bool { return c.grip.phase == .None })
	testing.expect_value(t, controller.grip.phase, Ladder_Phase.None)
	testing.expect(t, controller.on_ground && abs(controller.position.y) < 0.01)
	testing.expect(t, controller.position.z > 0.25 + 0.2) // In front of the ladder, not inside it.
	testing.expect(t, !Body_Blocked(world, controller.position))
}

@(test)
test_the_top_can_be_taken_hold_of_with_use_and_climbed_down :: proc(t: ^testing.T) {
	world := ladder_world()
	defer Collision_World_Destroy(&world)
	controller := Controller_Create({0, 3, -0.2}) // On the roof, a little behind the ladder's top, facing out over the edge.
	controller.on_ground = true
	facing_out := AWAY_FROM_WALL
	testing.expect_value(t, Ladder_Prompt_For(world, controller, facing_out), Ladder_Prompt.Climb_Down)
	testing.expect(t, Controller_Ladder_Step(&controller, world, FLAT, {use = true, facing = facing_out}, DT))
	run_ladder(&controller, world, {climb = -1, facing = facing_out}, 10, proc(c: Controller) -> bool { return c.grip.phase == .None && c.position.y < 0.5 })
	testing.expect_value(t, controller.grip.phase, Ladder_Phase.None)
	testing.expect(t, controller.on_ground && abs(controller.position.y) < 0.01 && controller.position.z > 0.45)
}

// Space pushes off backward with a hop; the body then falls like any other, and cannot re-grab until the hold-off has passed.
@(test)
test_jumping_off_pushes_away_and_cannot_be_undone_at_once :: proc(t: ^testing.T) {
	world := ladder_world()
	defer Collision_World_Destroy(&world)
	controller := Controller_Create({0, 0, 0.9})
	run_ladder(&controller, world, {climb = 1, facing = TOWARD_WALL}, 2.0) // About 1 m up.
	testing.expect(t, controller.grip.phase == .Climbing && controller.grip.height > 0.9)
	holding := Controller_Ladder_Step(&controller, world, FLAT, {jump = true, climb = 1, facing = TOWARD_WALL}, DT)
	testing.expect(t, !holding)
	testing.expect(t, controller.velocity.z > 1.5 && controller.velocity.y > 1) // Outward (+Z) and up.
	for _ in 0 ..< 6 { // Still pushing at the wall right after: no re-grab inside the hold-off.
		testing.expect(t, !Controller_Ladder_Step(&controller, world, FLAT, {climb = 1, facing = TOWARD_WALL}, DT))
		Controller_Step(&controller, world, FLAT, {controller.velocity.x, controller.velocity.z}, false, DT)
	}
	run_ladder(&controller, world, {facing = AWAY_FROM_WALL}, 3) // Fall and land.
	testing.expect(t, controller.on_ground && controller.position.y < 0.01)
}

@(test)
test_the_prompt_shows_in_front_of_the_ladder_and_not_elsewhere_or_while_climbing :: proc(t: ^testing.T) {
	world := ladder_world()
	defer Collision_World_Destroy(&world)
	front := Controller_Create({0, 0, 0.9})
	testing.expect_value(t, Ladder_Prompt_For(world, front, TOWARD_WALL), Ladder_Prompt.Climb_Up)
	far := Controller_Create({0, 0, 6})
	testing.expect_value(t, Ladder_Prompt_For(world, far, TOWARD_WALL), Ladder_Prompt.None)
	beside := Controller_Create({3.0, 0, 0.9})
	testing.expect_value(t, Ladder_Prompt_For(world, beside, TOWARD_WALL), Ladder_Prompt.None)
	Controller_Ladder_Step(&front, world, FLAT, {climb = 1, facing = TOWARD_WALL}, DT)
	testing.expect_value(t, Ladder_Prompt_For(world, front, TOWARD_WALL), Ladder_Prompt.None) // Already on it.
}

// Fuzz: sixty seconds of random keys from several starting spots. The climber never gets a bad number, never ends inside a solid,
// never leaves the ladder's height range, and while holding the ladder is exactly on its climbing plane.
@(test)
test_random_input_never_leaves_the_climber_inside_a_wall_or_off_the_ladder :: proc(t: ^testing.T) {
	world := ladder_world()
	defer Collision_World_Destroy(&world)
	starts := [?][3]f32{{0, 0, 1.2}, {0.4, 0, 0.8}, {0, 3, -0.2}, {-0.6, 0, 1.5}, {0, 3, -1.5}}
	state: u32 = 12345
	next := proc(state: ^u32) -> u32 {
		state^ = state^ * 1664525 + 1013904223
		return state^ >> 16
	}
	for start in starts {
		controller := Controller_Create(start)
		controller.on_ground = start.y > 0
		input: Ladder_Input
		for frame in 0 ..< 60 * 60 {
			if frame % 20 == 0 { // New random keys every third of a second.
				choice := next(&state) % 7
				input = Ladder_Input{climb = f32(int(choice % 3)) - 1, use = choice == 3, jump = choice == 4, facing = TOWARD_WALL if next(&state) % 2 == 0 else AWAY_FROM_WALL}
			} else do input.use, input.jump = false, false
			holding := Controller_Ladder_Step(&controller, world, FLAT, input, DT)
			if !holding do Controller_Step(&controller, world, FLAT, {f32(int(next(&state) % 3)) - 1, f32(int(next(&state) % 3)) - 1} * 2, false, DT)
			testing.expect(t, !math.is_nan(controller.position.x) && !math.is_nan(controller.position.y) && !math.is_nan(controller.position.z))
			testing.expect(t, controller.position.y > -0.01 && controller.position.y < 3.8)
			if !holding && controller.on_ground do testing.expect(t, !Body_Blocked(world, controller.position))
			if controller.grip.phase == .Climbing do testing.expect(t, abs(controller.position.z - (0.15 + 0.1 + LADDER_STANDOFF_METERS)) < 1e-3)
		}
	}
}
