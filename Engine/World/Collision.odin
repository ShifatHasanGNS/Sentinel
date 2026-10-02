package World

import "../Procedural"
import "core:math"

GRAVITY_METERS_PER_SECOND_SQUARED :: 9.81
JUMP_SPEED_METERS_PER_SECOND :: 4.6
CONTROLLER_RADIUS_METERS :: 0.35
CONTROLLER_HEIGHT_METERS :: 1.8
STEP_HEIGHT_METERS :: 0.35 // Ledges up to this tall are stepped onto; taller ones are walls.
GROUND_SNAP_METERS :: 0.35 // On the ground, drops up to this far are walked down; larger ones are falls.
SUBSTEP_SECONDS_MAX :: 1.0 / 60 // Longer steps are split, so fast motion cannot skip over a thin wall.

// The terrain as a height function of (x, z); data is passed through for whatever the function needs.
Ground :: struct {
	height_at: proc(data: rawptr, x, z: f32) -> f32,
	data:      rawptr,
}

// Static solid boxes (buildings, fences, vehicles) in world axes.
Collision_World :: struct {
	boxes: [dynamic]Procedural.Collision_Box,
}

Collision_World_Destroy :: proc(world: ^Collision_World) {
	delete(world.boxes)
}

// A character body: a vertical cylinder whose bottom (position) is at the feet.
Controller :: struct {
	position:  [3]f32,
	velocity:  [3]f32,
	on_ground: bool,
}

Controller_Create :: proc(position: [3]f32) -> Controller {
	return Controller{position = position}
}

// Moves the body by wish (horizontal metres per second) over delta_seconds. Each horizontal axis is tried separately, so a wall
// removes only the part of the motion that pushes into it (sliding). Vertical motion is gravity, jumps and landing.
Controller_Step :: proc(controller: ^Controller, world: Collision_World, ground: Ground, wish: [2]f32, jump: bool, delta_seconds: f32) {
	substeps := max(1, int(math.ceil(delta_seconds / SUBSTEP_SECONDS_MAX)))
	step := delta_seconds / f32(substeps)
	for _ in 0 ..< substeps {
		move_horizontally(controller, world, wish * step)
		resolve_vertically(controller, world, ground, jump, step)
	}
}

@(private = "file")
move_horizontally :: proc(controller: ^Controller, world: Collision_World, displacement: [2]f32) {
	move_along_axis(controller, world, {1, 0, 0}, displacement.x)
	move_along_axis(controller, world, {0, 0, 1}, displacement.y)
}

// Moves as far along one axis as is free: the whole way if it is, otherwise up to the point of contact, found by bisection,
// so the body ends against the wall instead of up to one step short of it.
@(private = "file")
move_along_axis :: proc(controller: ^Controller, world: Collision_World, axis: [3]f32, distance: f32) {
	if distance == 0 do return
	full := controller.position + axis * distance
	if !is_blocked(world, full) {
		controller.position = full
		return
	}
	free, blocked: f32 = 0, 1
	for _ in 0 ..< 6 {
		middle := (free + blocked) / 2
		if is_blocked(world, controller.position + axis * (distance * middle)) do blocked = middle
		else do free = middle
	}
	controller.position += axis * (distance * free)
}

// A box blocks when it is tall enough to be a wall (its top above step height), reaches into the body's height band,
// and the body's circle overlaps it on the ground plane.
@(private = "file")
is_blocked :: proc(world: Collision_World, position: [3]f32) -> bool {
	for box in world.boxes {
		if box.highest.y <= position.y + STEP_HEIGHT_METERS || box.lowest.y >= position.y + CONTROLLER_HEIGHT_METERS do continue
		if circle_overlaps_box(position, box) do return true
	}
	return false
}

@(private = "file")
circle_overlaps_box :: proc(position: [3]f32, box: Procedural.Collision_Box) -> bool {
	nearest_x := max(box.lowest.x - position.x, 0, position.x - box.highest.x)
	nearest_z := max(box.lowest.z - position.z, 0, position.z - box.highest.z)
	return nearest_x * nearest_x + nearest_z * nearest_z < CONTROLLER_RADIUS_METERS * CONTROLLER_RADIUS_METERS
}

// The highest thing the feet can stand on here: the terrain, or the top of a box low enough to step onto.
@(private = "file")
support_height :: proc(world: Collision_World, ground: Ground, position: [3]f32) -> f32 {
	height := ground.height_at(ground.data, position.x, position.z)
	for box in world.boxes {
		if box.highest.y > position.y + STEP_HEIGHT_METERS + 1e-4 || box.highest.y <= height do continue
		if circle_overlaps_box(position, box) do height = box.highest.y
	}
	return height
}

@(private = "file")
resolve_vertically :: proc(controller: ^Controller, world: Collision_World, ground: Ground, jump: bool, step: f32) {
	support := support_height(world, ground, controller.position)
	if controller.on_ground {
		if jump {
			controller.velocity.y = JUMP_SPEED_METERS_PER_SECOND
			controller.on_ground = false
		} else if controller.position.y - support <= GROUND_SNAP_METERS {
			controller.position.y, controller.velocity.y = support, 0
			return
		} else {
			controller.on_ground = false
		}
	}
	controller.velocity.y -= GRAVITY_METERS_PER_SECOND_SQUARED * step
	controller.position.y += controller.velocity.y * step
	if controller.position.y <= support && controller.velocity.y <= 0 {
		controller.position.y, controller.velocity.y = support, 0
		controller.on_ground = true
	}
}
