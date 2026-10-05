package World

import "core:math"

LADDER_CLIMB_SPEED :: f32(1.1) // Meters per second up: about three rungs a second, a brisk but real pace.
LADDER_DESCEND_SPEED :: f32(1.5) // Down is faster (hand over hand, sliding the feet).
LADDER_ACCELERATION :: f32(5.0)
LADDER_RUNG_METERS :: f32(0.3)
LADDER_STANDOFF_METERS :: f32(0.3) // Body center in front of the ladder's face while climbing: the chest is against the rungs.
LADDER_GRAB_REACH_METERS :: f32(0.9) // How far in front of the face a body can start a climb.
LADDER_MOUNT_SECONDS :: f32(0.3)
LADDER_TOP_MOUNT_SECONDS :: f32(0.45)
LADDER_TOP_OUT_SECONDS :: f32(0.6)
LADDER_TOP_ENTRY_METERS :: f32(0.08) // Within this of the top, still pushing up, starts the step over.
LADDER_LANDING_INSET_METERS :: f32(0.6) // How far past the ladder's plane the body lands on the platform.
LADDER_REGRAB_SECONDS :: f32(0.5) // After letting go, no new grab for this long, so a jump off is not instantly undone.
LADDER_JUMP_OFF_SPEED :: f32(2.2)
LADDER_FACING_DOT :: f32(0.35) // How squarely the player must face the ladder for a push forward to grab it.

Ladder_Phase :: enum {
	None,
	Mounting, // Easing from where the body stood onto the ladder.
	Climbing,
	Topping_Out, // Stepping up and over onto the platform.
}

// Everything about a body's hold on a ladder. While `phase` is not None the ladder owns the body's position.
Ladder_Grip :: struct {
	phase:         Ladder_Phase,
	index:         int,
	height:        f32, // Feet above the ladder's bottom, meters.
	speed:         f32, // Signed: positive is up.
	seconds:       f32, // Time spent in a Mounting or Topping_Out transition.
	duration:      f32, // How long that transition lasts.
	from:          [3]f32, // Where the transition began.
	rung:          int, // The rung the feet have reached, for sound and bob.
	cooldown:      f32, // After letting go: seconds until a new grab is allowed.
	mount_height:  f32, // The height a Mounting transition ends at.
}

Ladder_Input :: struct {
	climb:  f32, // -1 down .. 1 up (W and S).
	use:    bool, // The use key went down this frame.
	jump:   bool,
	facing: [2]f32, // Horizontal unit direction the player looks along.
}

Ladder_Prompt :: enum {
	None,
	Climb_Up, // Standing in front of a ladder: push forward or use.
	Climb_Down, // Standing at its top: use.
}

@(private = "file")
Candidate :: struct {
	index:    int,
	from_top: bool,
}

// Geometry of one ladder in its own frame: local +Z is the side the climber stands on, local -Z is the wall, local Y spans its height.
@(private = "file")
bottom_y :: proc(ladder: Solid) -> f32 {
	return ladder.center.y - ladder.half_extents.y
}

@(private = "file")
top_height :: proc(ladder: Solid) -> f32 {
	return 2 * ladder.half_extents.y
}

// Height of the ladder's foot above sea level and its length, for code that draws what the climber holds.
Ladder_Bottom_Meters :: proc(ladder: Solid) -> f32 {
	return bottom_y(ladder)
}

Ladder_Top_Meters :: proc(ladder: Solid) -> f32 {
	return top_height(ladder)
}

// The world point on the climbing plane at a height: centered on the ladder, STANDOFF in front of its face.
@(private = "file")
grip_position :: proc(ladder: Solid, height: f32) -> [3]f32 {
	offset := rotate_about_y({0, 0, ladder.half_extents.z + LADDER_STANDOFF_METERS}, ladder.yaw_radians)
	return {ladder.center.x + offset.x, bottom_y(ladder) + height, ladder.center.z + offset.z}
}

// The unit horizontal direction from the climber into the wall.
@(private = "file")
into_wall :: proc(ladder: Solid) -> [2]f32 {
	direction := rotate_about_y({0, 0, -1}, ladder.yaw_radians)
	return {direction.x, direction.z}
}

@(private = "file")
dot2 :: proc(a, b: [2]f32) -> f32 {
	return a.x * b.x + a.y * b.y
}

// Which ladder (if any) this body could take hold of now, and from which end. `must_want` also requires the player to ask for it
// (push forward squarely, or the use key); false asks only whether it is possible (for the on-screen prompt).
@(private = "file")
find_candidate :: proc(world: Collision_World, controller: Controller, input: Ladder_Input, must_want: bool) -> (candidate: Candidate, found: bool) {
	for ladder, index in world.ladders {
		local := to_local(ladder, controller.position)
		height := controller.position.y - bottom_y(ladder)
		front := local.z - ladder.half_extents.z // Distance in front of the ladder's face (negative: past it).
		sideways := abs(local.x)
		facing := dot2(input.facing, into_wall(ladder))
		if sideways <= ladder.half_extents.x + 0.4 && front >= 0 && front <= LADDER_GRAB_REACH_METERS && height >= -0.15 && height <= top_height(ladder) - 0.9 {
			wants := input.use || (input.climb > 0 && facing > LADDER_FACING_DOT)
			if wants || !must_want do return {index, false}, true
		}
		on_top := controller.on_ground && abs(height - top_height(ladder)) <= 0.5 && front >= -1.1 && front <= LADDER_GRAB_REACH_METERS && sideways <= ladder.half_extents.x + 0.5
		if on_top {
			wants := input.use || (input.climb < 0 && facing < -0.5)
			if wants || !must_want do return {index, true}, true
		}
	}
	return {}, false
}

// What to show the player: the prompt for a ladder they could grab right now. None while already on one.
Ladder_Prompt_For :: proc(world: Collision_World, controller: Controller, facing: [2]f32) -> Ladder_Prompt {
	if controller.grip.phase != .None || controller.grip.cooldown > 0 do return .None
	candidate, found := find_candidate(world, controller, Ladder_Input{facing = facing}, false)
	if !found do return .None
	return .Climb_Down if candidate.from_top else .Climb_Up
}

@(private = "file")
release :: proc(controller: ^Controller, position: [3]f32, velocity: [3]f32, on_ground: bool) {
	controller.position = position
	controller.velocity = velocity
	controller.on_ground = on_ground
	controller.grip.phase = .None
	controller.grip.speed = 0
	controller.grip.cooldown = LADDER_REGRAB_SECONDS
}

// One frame of ladder handling, called before Controller_Step. Returns true while the ladder holds the body: the caller then skips
// ordinary walking (the ladder moves the body itself, so there is no collision test to catch on the platform's edge or the tower).
Controller_Ladder_Step :: proc(controller: ^Controller, world: Collision_World, ground: Ground, input: Ladder_Input, delta_seconds: f32) -> (holding: bool) {
	grip := &controller.grip
	grip.cooldown = max(grip.cooldown - delta_seconds, 0)
	if grip.phase == .None {
		if grip.cooldown > 0 || len(world.ladders) == 0 do return false
		candidate, found := find_candidate(world, controller^, input, true)
		if !found do return false
		begin_mount(controller, world.ladders[candidate.index], candidate)
	}
	ladder := world.ladders[grip.index]
	if input.jump && grip.phase != .Topping_Out {
		jump_off(controller, ladder)
		return false
	}
	switch grip.phase {
	case .Mounting: advance_mount(controller, ladder, delta_seconds)
	case .Climbing: advance_climb(controller, world, ground, ladder, input, delta_seconds)
	case .Topping_Out: advance_top_out(controller, world, ground, ladder, delta_seconds)
	case .None:
	}
	return controller.grip.phase != .None
}

@(private = "file")
begin_mount :: proc(controller: ^Controller, ladder: Solid, candidate: Candidate) {
	grip := &controller.grip
	grip.phase = .Mounting
	grip.index = candidate.index
	grip.seconds = 0
	grip.from = controller.position
	grip.speed = 0
	if candidate.from_top {
		grip.mount_height = top_height(ladder) - 0.25
		grip.duration = LADDER_TOP_MOUNT_SECONDS
	} else {
		grip.mount_height = clamp(controller.position.y - bottom_y(ladder), 0, top_height(ladder) - 0.9)
		grip.duration = LADDER_MOUNT_SECONDS
	}
	grip.height = grip.mount_height
	grip.rung = int(grip.height / LADDER_RUNG_METERS)
	controller.velocity = {}
	controller.on_ground = false
}

@(private = "file")
smooth :: proc(t: f32) -> f32 {
	clamped := clamp(t, 0, 1)
	return clamped * clamped * (3 - 2 * clamped)
}

@(private = "file")
advance_mount :: proc(controller: ^Controller, ladder: Solid, delta_seconds: f32) {
	grip := &controller.grip
	grip.seconds += delta_seconds
	eased := smooth(grip.seconds / grip.duration)
	target := grip_position(ladder, grip.mount_height)
	controller.position = grip.from + (target - grip.from) * eased
	if grip.seconds >= grip.duration do grip.phase = .Climbing
}

@(private = "file")
advance_climb :: proc(controller: ^Controller, world: Collision_World, ground: Ground, ladder: Solid, input: Ladder_Input, delta_seconds: f32) {
	grip := &controller.grip
	target_speed: f32
	if input.climb > 0.1 do target_speed = LADDER_CLIMB_SPEED * min(input.climb, 1)
	else if input.climb < -0.1 do target_speed = -LADDER_DESCEND_SPEED * min(-input.climb, 1)
	grip.speed += clamp(target_speed - grip.speed, -LADDER_ACCELERATION * delta_seconds, LADDER_ACCELERATION * delta_seconds)
	grip.height = clamp(grip.height + grip.speed * delta_seconds, 0, top_height(ladder))
	grip.rung = int(grip.height / LADDER_RUNG_METERS)
	controller.position = grip_position(ladder, grip.height)
	controller.velocity = {}
	if grip.height <= 0 && input.climb < -0.1 {
		step_off_bottom(controller, world, ground, ladder)
		return
	}
	if grip.height >= top_height(ladder) - LADDER_TOP_ENTRY_METERS && input.climb > 0.1 {
		grip.phase = .Topping_Out
		grip.seconds = 0
		grip.duration = LADDER_TOP_OUT_SECONDS
		grip.from = controller.position
	}
}

// Stepping back off the bottom rung onto the ground in front of the ladder.
@(private = "file")
step_off_bottom :: proc(controller: ^Controller, world: Collision_World, ground: Ground, ladder: Solid) {
	outward := -into_wall(ladder)
	spot := controller.position + [3]f32{outward.x, 0, outward.y} * 0.35
	spot.y = support_height(world, ground, spot)
	release(controller, spot, {}, true)
}

// The step up and over: from the top rung to a point on the platform inset past the ladder's plane, rising an extra quarter meter in
// the middle so the feet clear the edge.
@(private = "file")
advance_top_out :: proc(controller: ^Controller, world: Collision_World, ground: Ground, ladder: Solid, delta_seconds: f32) {
	grip := &controller.grip
	grip.seconds += delta_seconds
	progress := smooth(grip.seconds / grip.duration)
	landing := landing_point(world, ground, ladder)
	arc := 0.25 * math.sin(math.PI * progress)
	controller.position = grip.from + (landing - grip.from) * progress + {0, arc, 0}
	if grip.seconds >= grip.duration do release(controller, landing, {}, true)
}

// Where a body ends up after topping out: LANDING_INSET past the climbing plane toward the wall, at whatever it can stand on there.
@(private = "file")
landing_point :: proc(world: Collision_World, ground: Ground, ladder: Solid) -> [3]f32 {
	plane := grip_position(ladder, top_height(ladder))
	inward := into_wall(ladder)
	spot := plane + [3]f32{inward.x, 0, inward.y} * (LADDER_STANDOFF_METERS + ladder.half_extents.z + LADDER_LANDING_INSET_METERS)
	standing := support_height(world, ground, {spot.x, plane.y, spot.z})
	spot.y = max(standing, plane.y - 0.1) if standing > plane.y - 1 else plane.y
	return spot
}

// Pushing off: away from the wall with a small hop, then ordinary falling.
@(private = "file")
jump_off :: proc(controller: ^Controller, ladder: Solid) {
	outward := -into_wall(ladder)
	release(controller, controller.position, {outward.x * LADDER_JUMP_OFF_SPEED, 1.5, outward.y * LADDER_JUMP_OFF_SPEED}, false)
}
