package Base

import "../Catalogue"
import World "../../Engine/World"
import "core:testing"

// Seam: Layout_Doors + Doors_Register + Doors_Update against a body walking through the world.

// A world with one placement of `kind` at (x, z) turned `yaw_degrees`.
single_building :: proc(kind: Catalogue.Object_Kind, x, z, yaw_degrees: f32) -> (layout: Layout, world: World.Collision_World, doors: [dynamic]Door) {
	append(&layout.placements, Placement{kind, x, z, yaw_degrees})
	world.boxes = Layout_Solids(layout, 0)
	doors = Layout_Doors(layout, 0)
	Doors_Register(doors[:], &world)
	return
}

destroy_building :: proc(layout: ^Layout, world: ^World.Collision_World, doors: ^[dynamic]Door) {
	delete(doors^)
	World.Collision_World_Destroy(world)
	Layout_Destroy(layout)
}

// Walks a body from 7 m in front of the door's middle toward the door and 3 m beyond it; returns how far along the walking
// direction (positive = inside) it ended relative to the wall plane.
walk_through_door :: proc(door: Door, world: World.Collision_World, sideways_meters: f32) -> f32 {
	middle := door.hinge + World.rotate_about_y({door.spec.side * door.spec.width / 2 + sideways_meters, 0, 0}, door.yaw_radians)
	inward := World.rotate_about_y({0, 0, -1}, door.yaw_radians) // Out of the front (+Z) is outward, so inward is -Z.
	start := middle - inward * 7
	controller := World.Controller_Create({start.x, 0, start.z})
	for _ in 0 ..< 60 * 5 do World.Controller_Step(&controller, world, World.Ground{height_at = flat}, {inward.x, inward.z} * 3, false, 1.0 / 60)
	travelled := [3]f32{controller.position.x - middle.x, 0, controller.position.z - middle.z}
	return travelled.x * inward.x + travelled.z * inward.z
}

open_all :: proc(doors: []Door, world: ^World.Collision_World) {
	for &door in doors do door.opening = true
	for _ in 0 ..< 60 * 2 do Doors_Update(doors, world, 1.0 / 60)
}

BUILDINGS_WITH_DOORS :: [?]Catalogue.Object_Kind{.Barracks, .Headquarters, .Mess_Hall, .Generator_Shed, .Guard_Post, .Bunker}

@(test)
test_a_closed_door_blocks_and_an_open_door_lets_a_body_inside_at_any_heading :: proc(t: ^testing.T) {
	for kind in BUILDINGS_WITH_DOORS {
		for yaw in ([4]f32{0, 90, 37, 200}) {
			layout, world, doors := single_building(kind, 30, -12, yaw)
			testing.expect(t, len(doors) > 0)
			for door in doors {
				closed := walk_through_door(door, world, 0)
				testing.expectf(t, closed < 0.1, "%v yaw %.0f: a closed door let the body to %.2f past the wall", kind, yaw, closed)
			}
			open_all(doors[:], &world)
			for door in doors {
				open := walk_through_door(door, world, 0)
				testing.expectf(t, open > 2.0, "%v yaw %.0f: an open door left the body at %.2f", kind, yaw, open)
			}
			destroy_building(&layout, &world, &doors)
		}
	}
}

// Opening the door must not open the walls: a body walking at the wall beside an open door is still stopped.
@(test)
test_an_open_door_does_not_open_the_wall_beside_it :: proc(t: ^testing.T) {
	layout, world, doors := single_building(.Headquarters, 0, 0, 0)
	defer destroy_building(&layout, &world, &doors)
	open_all(doors[:], &world)
	beside := walk_through_door(doors[0], world, 3.5)
	testing.expectf(t, beside < 0.1, "walked through the wall beside the door to %.2f", beside)
}

@(test)
test_doors_open_over_time_and_the_gate_leaves_move_together :: proc(t: ^testing.T) {
	layout, world, doors := single_building(.Gate, 0, 62, 0)
	defer destroy_building(&layout, &world, &doors)
	testing.expect_value(t, len(doors), 2)
	Doors_Toggle(doors[:], 0)
	Doors_Update(doors[:], &world, DOOR_OPEN_SECONDS / 4)
	testing.expect(t, abs(doors[0].open_amount - 0.25) < 1e-3 && abs(doors[1].open_amount - 0.25) < 1e-3)
	testing.expect(t, !world.boxes[doors[0].solid_index].disabled) // A crack open still blocks.
	Doors_Update(doors[:], &world, DOOR_OPEN_SECONDS / 4)
	testing.expect(t, world.boxes[doors[0].solid_index].disabled) // Half open lets a body through.
	Doors_Update(doors[:], &world, DOOR_OPEN_SECONDS)
	testing.expect_value(t, doors[1].open_amount, 1)
	testing.expect(t, world.boxes[doors[1].solid_index].disabled)
	Doors_Toggle(doors[:], 1)
	Doors_Update(doors[:], &world, 2 * DOOR_OPEN_SECONDS)
	testing.expect_value(t, doors[0].open_amount, 0)
	testing.expect(t, !world.boxes[doors[0].solid_index].disabled)
}

@(test)
test_the_nearest_door_is_found_only_within_reach :: proc(t: ^testing.T) {
	layout, world, doors := single_building(.Headquarters, 0, 0, 0)
	defer destroy_building(&layout, &world, &doors)
	middle := doors[0].hinge + World.rotate_about_y({doors[0].spec.width / 2, 0, 0}, 0)
	_, near := Doors_Nearest(doors[:], world, World.Ground{height_at = flat}, middle + {0, 1.6, 1.5})
	_, far := Doors_Nearest(doors[:], world, World.Ground{height_at = flat}, middle + {0, 1.6, 6})
	testing.expect(t, near && !far)
	// From inside the room the same door is just as usable (it is in the wall's opening, not behind it).
	_, from_inside := Doors_Nearest(doors[:], world, World.Ground{height_at = flat}, middle + {0, 1.6, -1.2})
	testing.expect(t, from_inside)
	// A second building's wall between the eye and the door blocks it: stand behind a barracks placed in the way.
	append(&world.boxes, World.Box_Solid(middle + {-3, 0, 0.8}, middle + {3, 3, 1.2}))
	_, behind_wall := Doors_Nearest(doors[:], world, World.Ground{height_at = flat}, middle + {0, 1.6, 2.0})
	testing.expect(t, !behind_wall)

}
