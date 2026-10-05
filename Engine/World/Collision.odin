package World

import "../Procedural"
import "core:math"

GRAVITY_METERS_PER_SECOND_SQUARED :: 9.81
JUMP_SPEED_METERS_PER_SECOND :: 4.6
CONTROLLER_RADIUS_METERS :: 0.35
CONTROLLER_HEIGHT_METERS :: 1.8
CONTROLLER_CROUCH_HEIGHT_METERS :: 1.1
STEP_HEIGHT_METERS :: 0.35 // Ledges up to this tall are stepped onto; taller ones are walls.
GROUND_SNAP_METERS :: 0.35 // On the ground, drops up to this far are walked down; larger ones are falls.
SUBSTEP_SECONDS_MAX :: 1.0 / 60 // Longer steps are split, so fast motion cannot skip over a thin wall.

// The terrain as a height function of (x, z); data is passed through for whatever the function needs.
Ground :: struct {
	height_at: proc(data: rawptr, x, z: f32) -> f32,
	data:      rawptr,
}

// Everything solid: `boxes` is the long-lived set (buildings, fences, doors, vehicles) and `temporary` is rebuilt by the game
// every frame from whatever is near the player (trees, rocks).
Collision_World :: struct {
	boxes:     [dynamic]Solid,
	temporary: [dynamic]Solid,
	ladders:   [dynamic]Solid, // Climbable volumes; the solid's local +Z is the side a climber stands on.
}

Collision_World_Destroy :: proc(world: ^Collision_World) {
	delete(world.boxes)
	delete(world.temporary)
	delete(world.ladders)
}

// A character body: a vertical cylinder whose bottom (position) is at the feet.
Controller :: struct {
	position:  [3]f32,
	velocity:  [3]f32,
	on_ground: bool,
	crouching: bool, // A crouching body is shorter, so it fits under low beams and ceilings.
	grip:      Ladder_Grip, // Non-idle while the body is on a ladder (see Ladder.odin); then position is driven by the ladder.
}

Controller_Create :: proc(position: [3]f32) -> Controller {
	return Controller{position = position}
}

// Moves the body by wish (horizontal metres per second) over delta_seconds. Each horizontal axis is tried separately, so a wall
// removes only the part of the motion that pushes into it (sliding). Vertical motion is gravity, jumps and landing.
Controller_Step :: proc(controller: ^Controller, world: Collision_World, ground: Ground, wish: [2]f32, jump: bool, delta_seconds: f32) {
	controller.velocity.x, controller.velocity.z = wish.x, wish.y
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
	height := Controller_Height(controller^)
	if distance == 0 do return
	full := controller.position + axis * distance
	if !is_blocked(world, full, height) {
		controller.position = full
		return
	}
	free, blocked: f32 = 0, 1
	for _ in 0 ..< 6 {
		middle := (free + blocked) / 2
		if is_blocked(world, controller.position + axis * (distance * middle), height) do blocked = middle
		else do free = middle
	}
	controller.position += axis * (distance * free)
}

// A solid blocks when it is tall enough to be a wall (its top above step height), reaches into the body's height band,
// and the body's circle overlaps it on the ground plane.
@(private = "file")
is_blocked :: proc(world: Collision_World, position: [3]f32, height: f32) -> bool {
	for solid in world.boxes do if blocks(solid, position, height) do return true
	for solid in world.temporary do if blocks(solid, position, height) do return true
	return false
}

// Broad phase with no trigonometry: the solid fits inside a circle of radius hypot(half_x, half_z) about its centre, so a body farther
// than that plus its own radius cannot touch it, whatever the solid's heading.
@(private = "file")
within_reach :: proc(solid: Solid, position: [3]f32) -> bool {
	dx, dz := position.x - solid.center.x, position.z - solid.center.z
	reach := math.sqrt(solid.half_extents.x * solid.half_extents.x + solid.half_extents.z * solid.half_extents.z) + CONTROLLER_RADIUS_METERS
	return dx * dx + dz * dz <= reach * reach
}

@(private = "file")
blocks :: proc(solid: Solid, position: [3]f32, height: f32) -> bool {
	if solid.disabled || !within_reach(solid, position) do return false
	top, bottom := solid.center.y + solid.half_extents.y, solid.center.y - solid.half_extents.y
	if top <= position.y + STEP_HEIGHT_METERS || bottom >= position.y + height do return false
	return circle_overlaps_solid(position, solid)
}

// The circle is tested in the solid's own axes, where the solid is axis-aligned: distance from the circle's center to the
// nearest point of the rectangle must be under the radius.
@(private = "file")
circle_overlaps_solid :: proc(position: [3]f32, solid: Solid) -> bool {
	local := to_local(solid, position)
	nearest_x := max(abs(local.x) - solid.half_extents.x, 0)
	nearest_z := max(abs(local.z) - solid.half_extents.z, 0)
	return nearest_x * nearest_x + nearest_z * nearest_z < CONTROLLER_RADIUS_METERS * CONTROLLER_RADIUS_METERS
}

// The highest thing the feet can stand on here: the terrain, or the top of a solid low enough to step onto.
@(private = "package")
support_height :: proc(world: Collision_World, ground: Ground, position: [3]f32) -> f32 {
	height := ground.height_at(ground.data, position.x, position.z)
	for solid in world.boxes do height = raised_by(solid, position, height)
	for solid in world.temporary do height = raised_by(solid, position, height)
	return height
}

@(private = "file")
raised_by :: proc(solid: Solid, position: [3]f32, height: f32) -> f32 {
	top := solid.center.y + solid.half_extents.y
	if solid.disabled || !within_reach(solid, position) || top > position.y + STEP_HEIGHT_METERS + 1e-4 || top <= height do return height
	return top if circle_overlaps_solid(position, solid) else height
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

// Whether a standing body at this position would overlap any solid (the same test the controller uses when it walks).
Body_Blocked :: proc(world: Collision_World, position: [3]f32) -> bool {
	return is_blocked(world, position, CONTROLLER_HEIGHT_METERS)
}

Controller_Height :: proc(controller: Controller) -> f32 {
	return CONTROLLER_CROUCH_HEIGHT_METERS if controller.crouching else CONTROLLER_HEIGHT_METERS
}

// Crouching is always allowed; standing up only where the full height is clear, so a body under a low beam stays crouched.
Controller_Set_Crouch :: proc(controller: ^Controller, world: Collision_World, crouch: bool) {
	if crouch {
		controller.crouching = true
		return
	}
	if controller.crouching && !is_blocked(world, controller.position, CONTROLLER_HEIGHT_METERS) do controller.crouching = false
}
