package Base

import "../Catalogue"
import World "../../Engine/World"
import "core:math"
import la "core:math/linalg"

DOOR_OPEN_SECONDS :: 0.6
DOOR_OPEN_ANGLE_RADIANS :: 1.75 // About 100 degrees, outward.
DOOR_SOLID_OPEN_THRESHOLD :: 0.3 // Past this much opening the leaf no longer blocks.
DOOR_INTERACT_RANGE_METERS :: 2.8

// One door of one placement, in the world.
Door :: struct {
	spec:            Catalogue.Door_Spec,
	placement_index: int,
	hinge:           [3]f32, // World position of the hinge, at the foot of the leaf.
	yaw_radians:     f32,
	open_amount:     f32, // 0 closed, 1 fully open.
	opening:         bool, // The direction it is heading.
	solid_index:     int, // Its leaf's slot in the collision world.
}

Layout_Doors :: proc(layout: Layout, ground_height_meters: f32) -> (doors: [dynamic]Door) {
	for placement, index in layout.placements {
		yaw := math.to_radians(placement.yaw_degrees)
		for spec in Catalogue.Catalogue_Doors(placement.kind) {
			local := World.rotate_about_y(spec.hinge, yaw)
			append(&doors, Door{spec = spec, placement_index = index, hinge = {placement.x + local.x, ground_height_meters + local.y, placement.z + local.z}, yaw_radians = yaw})
		}
	}
	return doors
}

// Adds each door's closed leaf to the collision world and remembers where.
Doors_Register :: proc(doors: []Door, collision: ^World.Collision_World) {
	for &door in doors {
		door.solid_index = len(collision.boxes)
		origin := door.hinge - World.rotate_about_y(door.spec.hinge, door.yaw_radians)
		origin.y = door.hinge.y - door.spec.hinge.y
		append(&collision.boxes, World.Solid_From_Object_Box(Catalogue.Door_Closed_Box(door.spec), origin, door.yaw_radians))
	}
}

// Opens or closes the doors toward their target and lets the collision world follow the leaf.
Doors_Update :: proc(doors: []Door, collision: ^World.Collision_World, delta_seconds: f32) {
	for &door in doors {
		target: f32 = 1 if door.opening else 0
		step := delta_seconds / DOOR_OPEN_SECONDS
		door.open_amount = clamp(door.open_amount + clamp(target - door.open_amount, -step, step), 0, 1)
		collision.boxes[door.solid_index].disabled = door.open_amount > DOOR_SOLID_OPEN_THRESHOLD
	}
}

// Flips every door that belongs with this one (a gate's two leaves move together): all open if this one is shut, else all shut.
Doors_Toggle :: proc(doors: []Door, index: int) {
	target := !doors[index].opening
	for &door in doors {
		if door.placement_index == doors[index].placement_index && door.spec.group == doors[index].spec.group do door.opening = target
	}
}

// The door whose leaf is nearest to `position` and within reach, if any.
Doors_Nearest :: proc(doors: []Door, position: [3]f32) -> (index: int, found: bool) {
	best := f32(DOOR_INTERACT_RANGE_METERS)
	for door, candidate in doors {
		middle := door.hinge + World.rotate_about_y({door.spec.side * door.spec.width / 2, 0, 0}, door.yaw_radians)
		offset := position - middle
		if abs(offset.y) > 2.5 do continue
		if distance := la.length([2]f32{offset.x, offset.z}); distance < best do best, index, found = distance, candidate, true
	}
	return
}

// The leaf's model matrix: the hinge frame, turned about +Y by the opening angle (outward is toward +Z in the object frame).
Door_Model :: proc(door: Door) -> matrix[4, 4]f32 {
	opening_angle := -door.spec.side * door.open_amount * DOOR_OPEN_ANGLE_RADIANS
	return la.matrix4_translate_f32(door.hinge) * la.matrix4_rotate_f32(door.yaw_radians, {0, 1, 0}) * la.matrix4_rotate_f32(opening_angle, {0, 1, 0})
}
