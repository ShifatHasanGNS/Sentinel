package World

import "core:math"

ROTOR_REVOLUTIONS_PER_SECOND :: 7.0 // At full speed; drawn rotation, not aerodynamics.
AIRCRAFT_GROUND_CONTACT_METERS :: 0.05
AIRCRAFT_GROUND_FRICTION_PER_SECOND :: 4.0
AIRCRAFT_HULL_BOTTOM_MARGIN_METERS :: 0.3 // Solids lower than this above the skids pass underneath.

// A helicopter's arcade flight model. Speeds in m/s, accelerations in m/s^2, rates per second.
Aircraft_Handling :: struct {
	climb_speed_max:       f32,
	descent_speed_max:     f32,
	vertical_acceleration: f32,
	forward_speed_max:     f32,
	strafe_speed_max:      f32,
	horizontal_acceleration: f32,
	yaw_rate_max:          f32, // Radians per second.
	tilt_max:              f32, // Radians of nose-down and bank at full stick.
	tilt_follow_per_second: f32,
	spool_up_seconds:      f32,
	spool_down_seconds:    f32,
	lift_rotor_threshold:  f32, // Rotor speed (0..1) needed to lift off.
	half_width:            f32,
	half_length:           f32,
	hull_center_z:         f32, // The hull rectangle's centre along the heading (the tail boom reaches behind).
	height:                f32,
}

Aircraft :: struct {
	position:     [3]f32, // Skid level, under the middle of the fuselage.
	yaw_radians:  f32, // Front along (sin yaw, 0, cos yaw), as for ground vehicles.
	pitch_radians: f32, // Nose up positive.
	roll_radians:  f32, // Leaning right positive.
	velocity:     [3]f32,
	rotor:        f32, // 0 stopped .. 1 full speed.
	rotor_angle_radians: f32,
	on_ground:    bool,
	impact_speed: f32, // Downward speed of the last touchdown (0 if none this step), for the game to judge.
}

Aircraft_Input :: struct {
	engine:     bool,
	collective: f32, // -1 descend .. 1 climb.
	pitch:      f32, // -1 backward .. 1 forward.
	roll:       f32, // -1 left .. 1 right (sideways).
	yaw:        f32, // -1 left .. 1 right.
}

Aircraft_Step :: proc(aircraft: ^Aircraft, handling: Aircraft_Handling, input: Aircraft_Input, world: Collision_World, ground: Ground, ignore_solid: int, delta_seconds: f32) {
	aircraft.impact_speed = 0
	spin_rotor(aircraft, handling, input.engine, delta_seconds)
	lifted := aircraft.rotor >= handling.lift_rotor_threshold
	terrain := ground.height_at(ground.data, aircraft.position.x, aircraft.position.z)
	airborne := aircraft.position.y - terrain > AIRCRAFT_GROUND_CONTACT_METERS
	steer_yaw(aircraft, handling, input, delta_seconds)
	update_velocity(aircraft, handling, input, lifted, airborne, delta_seconds)
	move(aircraft, handling, world, ground, ignore_solid, delta_seconds)
	tilt(aircraft, handling, input, airborne, delta_seconds)
}

@(private = "file")
spin_rotor :: proc(aircraft: ^Aircraft, handling: Aircraft_Handling, engine: bool, delta_seconds: f32) {
	if engine do aircraft.rotor = min(aircraft.rotor + delta_seconds / handling.spool_up_seconds, 1)
	else do aircraft.rotor = max(aircraft.rotor - delta_seconds / handling.spool_down_seconds, 0)
	aircraft.rotor_angle_radians = math.mod(aircraft.rotor_angle_radians + aircraft.rotor * ROTOR_REVOLUTIONS_PER_SECOND * 2 * math.PI * delta_seconds, 2 * math.PI)
}

// The tail rotor needs the engine turning: half speed is enough to steer.
@(private = "file")
steer_yaw :: proc(aircraft: ^Aircraft, handling: Aircraft_Handling, input: Aircraft_Input, delta_seconds: f32) {
	if aircraft.rotor < 0.5 do return
	aircraft.yaw_radians += -input.yaw * handling.yaw_rate_max * delta_seconds // A positive yaw is a turn to the left.
}

@(private = "file")
update_velocity :: proc(aircraft: ^Aircraft, handling: Aircraft_Handling, input: Aircraft_Input, lifted, airborne: bool, delta_seconds: f32) {
	forward := [2]f32{math.sin(aircraft.yaw_radians), math.cos(aircraft.yaw_radians)}
	right := [2]f32{-forward.y, forward.x}
	wish: [2]f32
	if lifted && airborne do wish = forward * (input.pitch * handling.forward_speed_max) + right * (input.roll * handling.strafe_speed_max)
	step := handling.horizontal_acceleration * delta_seconds
	if !airborne do step = AIRCRAFT_GROUND_FRICTION_PER_SECOND * handling.forward_speed_max * delta_seconds
	aircraft.velocity.x += clamp(wish.x - aircraft.velocity.x, -step, step)
	aircraft.velocity.z += clamp(wish.y - aircraft.velocity.z, -step, step)
	target_climb: f32
	switch {
	case !lifted: target_climb = -handling.descent_speed_max * 1.5 // Without lift it sinks.
	case input.collective > 0: target_climb = input.collective * handling.climb_speed_max
	case input.collective < 0: target_climb = input.collective * handling.descent_speed_max
	}
	vertical_step := handling.vertical_acceleration * delta_seconds
	aircraft.velocity.y += clamp(target_climb - aircraft.velocity.y, -vertical_step, vertical_step)
}

// Horizontal motion stops (does not slide) when the hull would meet a solid; vertical motion ends at the terrain.
@(private = "file")
move :: proc(aircraft: ^Aircraft, handling: Aircraft_Handling, world: Collision_World, ground: Ground, ignore_solid: int, delta_seconds: f32) {
	proposed := aircraft.position + [3]f32{aircraft.velocity.x, 0, aircraft.velocity.z} * delta_seconds
	if !aircraft_hull_hits_solid(world, ignore_solid, handling, {proposed.x, aircraft.position.y, proposed.z}, aircraft.yaw_radians) {
		aircraft.position.x, aircraft.position.z = proposed.x, proposed.z
	} else {
		aircraft.velocity.x, aircraft.velocity.z = 0, 0
	}
	aircraft.position.y += aircraft.velocity.y * delta_seconds
	terrain := ground.height_at(ground.data, aircraft.position.x, aircraft.position.z)
	if aircraft.position.y <= terrain {
		if aircraft.velocity.y < 0 do aircraft.impact_speed = -aircraft.velocity.y
		aircraft.position.y, aircraft.velocity.y = terrain, 0
	}
	aircraft.on_ground = aircraft.position.y - terrain <= AIRCRAFT_GROUND_CONTACT_METERS
}

// The hull as a rectangle on the ground plane (offset along the heading), in a height band from just above the skids to the rotor.
aircraft_hull_hits_solid :: proc(world: Collision_World, ignore_solid: int, handling: Aircraft_Handling, position: [3]f32, yaw: f32) -> bool {
	forward := [2]f32{math.sin(yaw), math.cos(yaw)}
	center := [2]f32{position.x, position.z} + forward * handling.hull_center_z
	test :: proc(solid: Solid, handling: Aircraft_Handling, position: [3]f32, center: [2]f32, yaw: f32) -> bool {
		if solid.disabled do return false
		top, bottom := solid.center.y + solid.half_extents.y, solid.center.y - solid.half_extents.y
		if top <= position.y + AIRCRAFT_HULL_BOTTOM_MARGIN_METERS || bottom >= position.y + handling.height do return false
		return rectangles_overlap(center, {handling.half_width, handling.half_length}, yaw, {solid.center.x, solid.center.z}, {solid.half_extents.x, solid.half_extents.z}, solid.yaw_radians)
	}
	for solid, index in world.boxes do if index != ignore_solid && test(solid, handling, position, center, yaw) do return true
	for solid in world.temporary do if test(solid, handling, position, center, yaw) do return true
	return false
}

// Visual attitude: nose down and bank follow the commanded motion, only while airborne and with the rotor turning.
@(private = "file")
tilt :: proc(aircraft: ^Aircraft, handling: Aircraft_Handling, input: Aircraft_Input, airborne: bool, delta_seconds: f32) {
	target_pitch, target_roll: f32
	if airborne && aircraft.rotor >= 0.5 {
		target_pitch = -input.pitch * handling.tilt_max
		target_roll = input.roll * handling.tilt_max
	}
	blend := min(1, handling.tilt_follow_per_second * delta_seconds)
	aircraft.pitch_radians += (target_pitch - aircraft.pitch_radians) * blend
	aircraft.roll_radians += (target_roll - aircraft.roll_radians) * blend
}
