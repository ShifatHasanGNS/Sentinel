package World

import "core:math"

VEHICLE_CLEARANCE_METERS :: 0.45 // Solids lower than this above the ground (kerbs, sandbags' base) pass under the hull or are driven over.
VEHICLE_BOUNCE_FRACTION :: 0.25 // Speed kept (reversed) after hitting something.
VEHICLE_SLOPE_FOLLOW_PER_SECOND :: 8.0
VEHICLE_STILL_SPEED_METERS_PER_SECOND :: 0.05

// How a ground vehicle moves and how big it is. Lengths in meters, rates per second.
Vehicle_Handling :: struct {
	speed_forward_max:  f32,
	speed_reverse_max:  f32,
	acceleration:       f32,
	brake:              f32, // Deceleration while the throttle opposes the motion.
	drag:               f32, // Deceleration with no throttle.
	wheel_base:         f32, // Front to rear axle; sets how sharply it turns at speed.
	steer_angle_max:    f32, // Radians at the front wheels (wheeled) ...
	turn_rate_max:      f32, // ... or radians per second of yaw (tracked, which turns on the spot).
	tracked:            bool,
	half_width:         f32,
	half_length:        f32,
	height:             f32,
}

// A vehicle's body: where it is and how it is turned. The ground point is the center under the hull.
Ground_Vehicle :: struct {
	position:    [3]f32,
	yaw_radians: f32, // Front along (sin yaw, 0, cos yaw): the same turn as a placed object.
	speed:       f32, // Along the front; negative is reverse.
	steer:       f32, // Smoothed steering in [-1, 1]; +1 is full right.
	pitch_radians: f32, // Nose up is positive.
	roll_radians:  f32, // Leaning right is positive.
	wheel_spin_radians: f32, // Accumulated rolling, for the wheel animation.
}

Vehicle_Input :: struct {
	throttle: f32, // -1 reverse .. 1 forward.
	steer:    f32, // -1 left .. 1 right.
	brake:    bool,
}

STEER_RESPONSE_PER_SECOND :: 6.0

// One step: speed from throttle, brake and drag; heading from the steering model; the move is refused where the hull would hit a
// solid; the body then rests on the terrain (height from the four corners, pitch and roll from their differences).
// ignore_solid is the vehicle's own solid in the collision world (or -1).
Ground_Vehicle_Step :: proc(vehicle: ^Ground_Vehicle, handling: Vehicle_Handling, input: Vehicle_Input, world: Collision_World, ground: Ground, ignore_solid: int, delta_seconds: f32) {
	vehicle.steer += clamp(input.steer - vehicle.steer, -STEER_RESPONSE_PER_SECOND * delta_seconds, STEER_RESPONSE_PER_SECOND * delta_seconds)
	vehicle.speed = next_speed(vehicle.speed, handling, input, delta_seconds)
	yaw_rate := yaw_rate_for(vehicle^, handling)
	new_yaw := vehicle.yaw_radians + yaw_rate * delta_seconds
	forward := [3]f32{math.sin(new_yaw), 0, math.cos(new_yaw)}
	new_position := vehicle.position + forward * (vehicle.speed * delta_seconds)
	if hull_hits_solid(world, ignore_solid, handling, {vehicle.position.x, ground.height_at(ground.data, vehicle.position.x, vehicle.position.z), vehicle.position.z}, vehicle.yaw_radians) {
		// Already overlapping something (placed too close, or a door swung into it): drive free rather than be stuck for good.
		vehicle.position.x, vehicle.position.z, vehicle.yaw_radians = new_position.x, new_position.z, new_yaw
		vehicle.wheel_spin_radians += vehicle.speed * delta_seconds
		settle_on_ground(vehicle, handling, ground, delta_seconds)
		return
	}
	moved := try_pose(vehicle, handling, world, ground, ignore_solid, new_position, new_yaw) ||
		try_pose(vehicle, handling, world, ground, ignore_solid, new_position, vehicle.yaw_radians) ||
		try_pose(vehicle, handling, world, ground, ignore_solid, vehicle.position, new_yaw)
	if !moved do vehicle.speed *= -VEHICLE_BOUNCE_FRACTION
	vehicle.wheel_spin_radians += vehicle.speed * delta_seconds
	settle_on_ground(vehicle, handling, ground, delta_seconds)
}

@(private = "file")
next_speed :: proc(speed: f32, handling: Vehicle_Handling, input: Vehicle_Input, delta_seconds: f32) -> f32 {
	result := speed
	opposing := (input.throttle > 0 && speed < 0) || (input.throttle < 0 && speed > 0)
	switch {
	case input.brake:
		result = approach(speed, 0, handling.brake * 1.5 * delta_seconds)
	case opposing:
		result = approach(speed, 0, handling.brake * delta_seconds)
	case input.throttle != 0:
		limit := handling.speed_forward_max if input.throttle > 0 else -handling.speed_reverse_max
		result = approach(speed, limit * abs(input.throttle), handling.acceleration * delta_seconds)
	case:
		result = approach(speed, 0, handling.drag * delta_seconds)
	}
	return result
}

@(private = "file")
approach :: proc(value, target, step: f32) -> f32 {
	return value + clamp(target - value, -step, step)
}

// Wheeled: the bicycle model, yaw rate = speed * tan(steer angle) / wheel base (reversing flips the turn, as in a real car).
// Tracked: yaw rate follows the steering alone, so the vehicle can pivot where it stands. Positive yaw is a turn to the left.
@(private = "file")
yaw_rate_for :: proc(vehicle: Ground_Vehicle, handling: Vehicle_Handling) -> f32 {
	if handling.tracked do return -vehicle.steer * handling.turn_rate_max
	return -vehicle.speed * math.tan(vehicle.steer * handling.steer_angle_max) / handling.wheel_base
}

@(private = "file")
try_pose :: proc(vehicle: ^Ground_Vehicle, handling: Vehicle_Handling, world: Collision_World, ground: Ground, ignore_solid: int, position: [3]f32, yaw: f32) -> bool {
	base := ground.height_at(ground.data, position.x, position.z)
	if hull_hits_solid(world, ignore_solid, handling, {position.x, base, position.z}, yaw) do return false
	vehicle.position.x, vehicle.position.z, vehicle.yaw_radians = position.x, position.z, yaw
	return true
}

// Whether the hull (a rectangle on the ground plane turned by yaw) overlaps any solid that is tall enough to be in its way.
hull_hits_solid :: proc(world: Collision_World, ignore_solid: int, handling: Vehicle_Handling, position: [3]f32, yaw: f32) -> bool {
	for solid, index in world.boxes do if index != ignore_solid && solid_in_the_way(solid, handling, position, yaw) do return true
	for solid in world.temporary do if solid_in_the_way(solid, handling, position, yaw) do return true
	return false
}

@(private = "file")
solid_in_the_way :: proc(solid: Solid, handling: Vehicle_Handling, position: [3]f32, yaw: f32) -> bool {
	if solid.disabled do return false
	top, bottom := solid.center.y + solid.half_extents.y, solid.center.y - solid.half_extents.y
	if top <= position.y + VEHICLE_CLEARANCE_METERS || bottom >= position.y + handling.height do return false
	return rectangles_overlap(
		{position.x, position.z}, {handling.half_width, handling.half_length}, yaw,
		{solid.center.x, solid.center.z}, {solid.half_extents.x, solid.half_extents.z}, solid.yaw_radians,
	)
}

// Separating-axis test for two rectangles on the ground plane: they are apart exactly when their projections onto one of the
// four edge directions do not overlap. Each rectangle's local X axis is (cos yaw, -sin yaw), its local Z axis (sin yaw, cos yaw).
rectangles_overlap :: proc(center_a, half_a: [2]f32, yaw_a: f32, center_b, half_b: [2]f32, yaw_b: f32) -> bool {
	axes := [4][2]f32{
		{math.cos(yaw_a), -math.sin(yaw_a)}, {math.sin(yaw_a), math.cos(yaw_a)},
		{math.cos(yaw_b), -math.sin(yaw_b)}, {math.sin(yaw_b), math.cos(yaw_b)},
	}
	offset := center_b - center_a
	for axis in axes {
		radius_a := projected_radius(half_a, yaw_a, axis)
		radius_b := projected_radius(half_b, yaw_b, axis)
		if abs(offset.x * axis.x + offset.y * axis.y) > radius_a + radius_b do return false
	}
	return true
}

// Half the width of a rectangle's shadow on `axis`: |half_x * (x_axis . axis)| + |half_z * (z_axis . axis)|.
@(private = "file")
projected_radius :: proc(half: [2]f32, yaw: f32, axis: [2]f32) -> f32 {
	x_axis := [2]f32{math.cos(yaw), -math.sin(yaw)}
	z_axis := [2]f32{math.sin(yaw), math.cos(yaw)}
	return abs(half.x * (x_axis.x * axis.x + x_axis.y * axis.y)) + abs(half.y * (z_axis.x * axis.x + z_axis.y * axis.y))
}

// Rests on the terrain: height is the mean of the four hull corners, pitch from front minus rear, roll from right minus left.
@(private = "file")
settle_on_ground :: proc(vehicle: ^Ground_Vehicle, handling: Vehicle_Handling, ground: Ground, delta_seconds: f32) {
	forward := [2]f32{math.sin(vehicle.yaw_radians), math.cos(vehicle.yaw_radians)}
	right := [2]f32{-forward.y, forward.x} // The vehicle's right when facing along `forward`.
	at :: proc(ground: Ground, vehicle: Ground_Vehicle, forward, right: [2]f32, along, across: f32) -> f32 {
		return ground.height_at(ground.data, vehicle.position.x + forward.x * along + right.x * across, vehicle.position.z + forward.y * along + right.y * across)
	}
	front_left := at(ground, vehicle^, forward, right, handling.half_length, -handling.half_width)
	front_right := at(ground, vehicle^, forward, right, handling.half_length, handling.half_width)
	rear_left := at(ground, vehicle^, forward, right, -handling.half_length, -handling.half_width)
	rear_right := at(ground, vehicle^, forward, right, -handling.half_length, handling.half_width)
	vehicle.position.y = (front_left + front_right + rear_left + rear_right) / 4
	target_pitch := math.atan2((front_left + front_right - rear_left - rear_right) / 2, 2 * handling.half_length)
	target_roll := math.atan2((front_right + rear_right - front_left - rear_left) / 2, 2 * handling.half_width)
	blend := min(1, VEHICLE_SLOPE_FOLLOW_PER_SECOND * delta_seconds)
	vehicle.pitch_radians += (target_pitch - vehicle.pitch_radians) * blend
	vehicle.roll_radians += (target_roll - vehicle.roll_radians) * blend
}
