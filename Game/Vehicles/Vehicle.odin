package Vehicles

import "../Catalogue"
import "../Gameplay"
import World "../../Engine/World"
import "core:math"
import la "core:math/linalg"

BOARD_RANGE_METERS :: 3.0 // From the hull's edge.
EXIT_SPEED_MAX :: 3.0 // Faster than this and the door stays shut.
CANNON_COOLDOWN_SECONDS :: 2.5
CANNON_MUZZLE_SPEED :: 70.0
MACHINE_GUN_COOLDOWN_SECONDS :: 0.09
MACHINE_GUN_DAMAGE :: 14.0
MACHINE_GUN_RANGE_METERS :: 160.0
MACHINE_GUN_SPREAD :: 0.012
TURRET_TURN_CANNON :: 0.7 // Radians per second.
TURRET_TURN_GUN :: 2.4
GUN_PITCH_MIN :: -0.15
GUN_PITCH_MAX :: 0.4
SOLID_HEIGHT_FRACTION :: 1.0

// One drivable vehicle in the world: its hull, its turret and gun angles, its slot in the collision world, who is in it.
Vehicle :: struct {
	kind:             Catalogue.Object_Kind,
	spec:             ^Catalogue.Vehicle_Spec,
	body:             World.Ground_Vehicle,
	solid_index:      int,
	occupied:         bool,
	turret_yaw:       f32, // Radians relative to the hull; positive turns left, like hull yaw.
	gun_pitch:        f32,
	cooldown_seconds: f32,
	shots:            u32,
}

// The pilot's wishes for one frame: where to drive and where to aim (world heading in the vehicle convention, and pitch).
Vehicle_Controls :: struct {
	drive:      World.Vehicle_Input,
	aim_yaw:    f32, // World heading the turret should face: (sin yaw, cos yaw) is the direction.
	aim_pitch:  f32,
}

// Creates a vehicle for every ground-vehicle placement and registers each hull in the collision world.
Vehicles_Create :: proc(layout_vehicles: []Placed, ground: World.Ground, collision: ^World.Collision_World) -> (vehicles: [dynamic]Vehicle) {
	for placed in layout_vehicles {
		spec := Catalogue.Catalogue_Vehicle_Spec(placed.kind)
		vehicle := Vehicle{kind = placed.kind, spec = spec}
		vehicle.body.position = {placed.x, ground.height_at(ground.data, placed.x, placed.z), placed.z}
		vehicle.body.yaw_radians = placed.yaw_radians
		vehicle.solid_index = len(collision.boxes)
		append(&collision.boxes, hull_solid(vehicle))
		append(&vehicles, vehicle)
	}
	return vehicles
}

// A vehicle to place: what it is and where it stands (yaw in the placement convention).
Placed :: struct {
	kind:        Catalogue.Object_Kind,
	x, z:        f32,
	yaw_radians: f32,
}

@(private = "file")
hull_solid :: proc(vehicle: Vehicle) -> World.Solid {
	handling := vehicle.spec.handling
	return World.Solid{
		center = vehicle.body.position + {0, handling.height / 2, 0},
		half_extents = {handling.half_width, handling.height / 2, handling.half_length},
		yaw_radians = vehicle.body.yaw_radians,
	}
}

// Moves the vehicle one step; an empty one is held by its handbrake. The collision solid follows the hull.
Vehicle_Update :: proc(vehicle: ^Vehicle, controls: Vehicle_Controls, collision: ^World.Collision_World, ground: World.Ground, delta_seconds: f32) {
	input := controls.drive
	if !vehicle.occupied do input = World.Vehicle_Input{brake = true}
	World.Ground_Vehicle_Step(&vehicle.body, vehicle.spec.handling, input, collision^, ground, vehicle.solid_index, delta_seconds)
	if vehicle.occupied do slew_turret(vehicle, controls, delta_seconds)
	vehicle.cooldown_seconds = max(vehicle.cooldown_seconds - delta_seconds, 0)
	collision.boxes[vehicle.solid_index] = hull_solid(vehicle^)
}

@(private = "file")
slew_turret :: proc(vehicle: ^Vehicle, controls: Vehicle_Controls, delta_seconds: f32) {
	if vehicle.spec.weapon == .None do return
	rate: f32 = TURRET_TURN_CANNON if vehicle.spec.weapon == .Cannon else TURRET_TURN_GUN
	wanted_yaw := wrap_angle(controls.aim_yaw - vehicle.body.yaw_radians)
	vehicle.turret_yaw = wrap_angle(vehicle.turret_yaw + clamp(wrap_angle(wanted_yaw - vehicle.turret_yaw), -rate * delta_seconds, rate * delta_seconds))
	wanted_pitch := clamp(controls.aim_pitch - vehicle.body.pitch_radians, GUN_PITCH_MIN, GUN_PITCH_MAX)
	vehicle.gun_pitch += clamp(wanted_pitch - vehicle.gun_pitch, -rate * delta_seconds, rate * delta_seconds)
}

wrap_angle :: proc(angle: f32) -> f32 {
	wrapped := math.mod(angle + math.PI, 2 * math.PI)
	if wrapped < 0 do wrapped += 2 * math.PI
	return wrapped - math.PI
}

// Hull frame: translate, turn about +Y, then nose up (a rotation about X by -pitch, since +Z is the nose) and lean (about Z).
Vehicle_Hull_Matrix :: proc(vehicle: Vehicle) -> matrix[4, 4]f32 {
	body := vehicle.body
	return la.matrix4_translate_f32(body.position) * la.matrix4_rotate_f32(body.yaw_radians, {0, 1, 0}) * la.matrix4_rotate_f32(-body.pitch_radians, {1, 0, 0}) * la.matrix4_rotate_f32(body.roll_radians, {0, 0, 1})
}

Vehicle_Turret_Matrix :: proc(vehicle: Vehicle) -> matrix[4, 4]f32 {
	return Vehicle_Hull_Matrix(vehicle) * la.matrix4_translate_f32(vehicle.spec.turret_pivot) * la.matrix4_rotate_f32(vehicle.turret_yaw, {0, 1, 0})
}

Vehicle_Gun_Matrix :: proc(vehicle: Vehicle) -> matrix[4, 4]f32 {
	return Vehicle_Turret_Matrix(vehicle) * la.matrix4_translate_f32(vehicle.spec.gun_pivot) * la.matrix4_rotate_f32(-vehicle.gun_pitch, {1, 0, 0})
}

// Where the gun fires from and along.
Vehicle_Muzzle :: proc(vehicle: Vehicle) -> (origin, direction: [3]f32) {
	gun := Vehicle_Gun_Matrix(vehicle)
	tip := gun * [4]f32{vehicle.spec.muzzle.x, vehicle.spec.muzzle.y, vehicle.spec.muzzle.z, 1}
	forward := gun * [4]f32{0, 0, 1, 0}
	return tip.xyz, la.normalize(forward.xyz)
}

// The occupant's eye in the world.
Vehicle_Seat_Position :: proc(vehicle: Vehicle) -> [3]f32 {
	seat := Vehicle_Hull_Matrix(vehicle) * [4]f32{vehicle.spec.seat.x, vehicle.spec.seat.y, vehicle.spec.seat.z, 1}
	return seat.xyz
}

// Within the boarding distance of the hull's edge (the rectangle it stands on), and low enough to climb in.
Vehicle_Can_Board :: proc(vehicle: Vehicle, position: [3]f32) -> bool {
	if vehicle.occupied || abs(vehicle.body.speed) > EXIT_SPEED_MAX do return false
	handling := vehicle.spec.handling
	local := World.rotate_about_y(position - vehicle.body.position, -vehicle.body.yaw_radians)
	if local.y < -1 || local.y > handling.height do return false
	outside_x, outside_z := max(abs(local.x) - handling.half_width, 0), max(abs(local.z) - handling.half_length, 0)
	return math.sqrt(outside_x * outside_x + outside_z * outside_z) <= BOARD_RANGE_METERS
}

// A spot beside the vehicle where a person can stand: its left side first, then right, then behind, then ahead; the first that
// is clear of every solid. Falls back to the left side if everything is blocked.
Vehicle_Exit_Position :: proc(vehicle: Vehicle, collision: World.Collision_World, ground: World.Ground) -> [3]f32 {
	handling := vehicle.spec.handling
	candidates := [4][3]f32{
		{handling.half_width + 1.0, 0, 0}, {-(handling.half_width + 1.0), 0, 0}, {0, 0, -(handling.half_length + 1.0)}, {0, 0, handling.half_length + 1.0},
	}
	fallback: [3]f32
	for candidate, index in candidates {
		offset := World.rotate_about_y(candidate, vehicle.body.yaw_radians)
		spot := vehicle.body.position + offset
		spot.y = ground.height_at(ground.data, spot.x, spot.z)
		if index == 0 do fallback = spot
		if !World.Body_Blocked(collision, spot) do return spot
	}
	return fallback
}

// Fires the vehicle's gun if it has one and has reloaded. The vehicle's own hull is switched off for the shot so the round does
// not strike the vehicle that fired it.
Vehicle_Fire :: proc(vehicle: ^Vehicle, battle: ^Gameplay.Battle) -> bool {
	if vehicle.spec.weapon == .None || vehicle.cooldown_seconds > 0 do return false
	origin, direction := Vehicle_Muzzle(vehicle^)
	vehicle.shots += 1
	battle.collision.boxes[vehicle.solid_index].disabled = true
	defer battle.collision.boxes[vehicle.solid_index].disabled = false
	switch vehicle.spec.weapon {
	case .Cannon:
		Gameplay.Battle_Spawn_Projectile(battle, .Rocket_Launcher, origin + direction * 0.6, direction * CANNON_MUZZLE_SPEED)
		vehicle.cooldown_seconds = CANNON_COOLDOWN_SECONDS
	case .Machine_Gun:
		Gameplay.Battle_Fire_Bullet(battle, origin, spread(direction, vehicle.shots), MACHINE_GUN_DAMAGE, MACHINE_GUN_RANGE_METERS)
		vehicle.cooldown_seconds = MACHINE_GUN_COOLDOWN_SECONDS
	case .None:
	}
	return true
}

@(private = "file")
spread :: proc(direction: [3]f32, counter: u32) -> [3]f32 {
	u1 := f32(counter * 2654435761 % 1000) / 1000
	u2 := f32(counter * 40503 % 1000) / 1000
	return World.Spread_Direction(direction, MACHINE_GUN_SPREAD, u1, u2)
}
