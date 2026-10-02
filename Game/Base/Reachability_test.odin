package Base

import "../Catalogue"
import World "../../Engine/World"
import "core:math"
import "core:testing"

// Seam: Layout_Solids + Layout_Doors + World.Body_Blocked. A person starting outside the gate, with every door opened, can walk to
// everything the mission asks for: the HQ computer, the hostage in the middle barracks, and the extraction point. Breadth-first
// search over a 0.5 m grid, one body-sized cell at a time.

GRID_STEP_METERS :: 0.5
GRID_HALF_SPAN_METERS :: 90.0

flat_ground :: proc(data: rawptr, x, z: f32) -> f32 {
	return 0
}

cell_of :: proc(point: [2]f32) -> [2]int {
	return {int(math.round((point.x + GRID_HALF_SPAN_METERS) / GRID_STEP_METERS)), int(math.round((point.y + GRID_HALF_SPAN_METERS) / GRID_STEP_METERS))}
}

point_of :: proc(cell: [2]int) -> [2]f32 {
	return {f32(cell.x) * GRID_STEP_METERS - GRID_HALF_SPAN_METERS, f32(cell.y) * GRID_STEP_METERS - GRID_HALF_SPAN_METERS}
}

// All cells reachable from `start`, as a flat boolean grid.
reachable_cells :: proc(world: World.Collision_World, start: [2]f32) -> (grid: []bool, size: int) {
	size = int(2 * GRID_HALF_SPAN_METERS / GRID_STEP_METERS) + 1
	grid = make([]bool, size * size)
	queue := make([dynamic][2]int)
	defer delete(queue)
	first := cell_of(start)
	grid[first.y * size + first.x] = true
	append(&queue, first)
	for head := 0; head < len(queue); head += 1 {
		cell := queue[head]
		for step in ([4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
			next := cell + step
			if next.x < 0 || next.y < 0 || next.x >= size || next.y >= size || grid[next.y * size + next.x] do continue
			position := point_of(next)
			if World.Body_Blocked(world, {position.x, 0, position.y}) do continue
			grid[next.y * size + next.x] = true
			append(&queue, next)
		}
	}
	return
}

@(test)
test_every_mission_goal_can_be_walked_to_from_outside_the_gate :: proc(t: ^testing.T) {
	layout := Layout_Create(5, 90)
	defer Layout_Destroy(&layout)
	world := World.Collision_World{boxes = Layout_Solids(layout, 0)}
	defer World.Collision_World_Destroy(&world)
	doors := Layout_Doors(layout, 0)
	defer delete(doors)
	Doors_Register(doors[:], &world)
	for &door in doors do door.opening = true
	for _ in 0 ..< 120 do Doors_Update(doors[:], &world, 1.0 / 60)

	grid, size := reachable_cells(world, {0, 80}) // South of the gate, where the player spawns.
	defer delete(grid)

	goals := make([dynamic][2]f32, context.temp_allocator)
	names := make([dynamic]string, context.temp_allocator)
	for placement in layout.placements {
		yaw := math.to_radians(placement.yaw_degrees)
		at := [3]f32{placement.x, 0, placement.z}
		#partial switch placement.kind {
		case .Headquarters:
			spot := at + World.rotate_about_y({Catalogue.HEADQUARTERS_TERMINAL.x, 0, Catalogue.HEADQUARTERS_TERMINAL.z + 1.0}, yaw)
			append(&goals, [2]f32{spot.x, spot.z})
			append(&names, "the HQ computer")
		case .Barracks:
			spot := at + World.rotate_about_y({0, 0, 1.2}, yaw)
			append(&goals, [2]f32{spot.x, spot.z})
			append(&names, "a barracks interior")
		case .Radar_Station:
			spot := at + World.rotate_about_y({0, 0, 3.2}, yaw)
			append(&goals, [2]f32{spot.x, spot.z})
			append(&names, "the radar station")
		}
	}
	append(&goals, [2]f32{-72, -52})
	append(&names, "the extraction point")
	testing.expect(t, len(goals) >= 6)
	for goal, index in goals {
		cell := cell_of(goal)
		testing.expectf(t, grid[cell.y * size + cell.x], "%s at (%.1f, %.1f) cannot be reached from the gate", names[index], goal.x, goal.y)
	}
}

// With the doors shut, the HQ interior cannot be reached: the doors are what gate the rooms (the test above would pass for a world
// with no walls at all, so this one confirms the search can fail).
@(test)
test_closed_doors_keep_the_rooms_unreachable :: proc(t: ^testing.T) {
	layout := Layout_Create(5, 90)
	defer Layout_Destroy(&layout)
	world := World.Collision_World{boxes = Layout_Solids(layout, 0)}
	defer World.Collision_World_Destroy(&world)
	doors := Layout_Doors(layout, 0)
	defer delete(doors)
	Doors_Register(doors[:], &world)
	grid, size := reachable_cells(world, {0, 80})
	defer delete(grid)
	for placement in layout.placements {
		if placement.kind != .Headquarters do continue
		inside := cell_of({placement.x, placement.z})
		testing.expect(t, !grid[inside.y * size + inside.x])
	}
	gate_inside := cell_of({0, 40})
	testing.expect(t, !grid[gate_inside.y * size + gate_inside.x]) // The shut gate seals the compound.
}

