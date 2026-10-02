package Catalogue

import "../../Engine/Procedural"
import World "../../Engine/World"

Wheel_Mount :: struct {
	position: [3]f32, // Vehicle frame; y is the wheel's radius (its axle height).
	steered:  bool,
}

Vehicle_Weapon :: enum {
	None,
	Machine_Gun,
	Cannon,
}

// A drivable vehicle taken apart into the pieces that move: the hull, one wheel (mounted many times), and a turret carrying a gun.
// Everything is in its own frame, built around the origin; the mounts and pivots say where each piece sits.
Vehicle_Spec :: struct {
	body:         Parts,
	wheel:        Parts,
	wheel_mounts: [dynamic]Wheel_Mount,
	wheel_radius: f32,
	turret:       Parts,
	turret_pivot: [3]f32, // In the vehicle frame.
	gun:          Parts,
	gun_pivot:    [3]f32, // In the turret frame.
	muzzle:       [3]f32, // In the gun frame.
	weapon:       Vehicle_Weapon,
	seat:         [3]f32, // The occupant's eye, in the vehicle frame.
	armor:        f32, // Fraction of incoming damage the occupant takes.
	handling:     World.Vehicle_Handling,
	is_aircraft:  bool,
	aircraft:     World.Aircraft_Handling,
	main_rotor:   Parts,
	main_rotor_pivot: [3]f32,
	tail_rotor:   Parts,
	tail_rotor_pivot: [3]f32,
}

Vehicle_Spec_Destroy :: proc(spec: ^Vehicle_Spec) {
	delete(spec.body)
	delete(spec.wheel)
	delete(spec.wheel_mounts)
	delete(spec.turret)
	delete(spec.gun)
	delete(spec.main_rotor)
	delete(spec.tail_rotor)
	spec^ = {}
}

@(private = "file")
spec_cache: [Object_Kind]Maybe(Vehicle_Spec)

// Built on first use and kept for the life of the program. Only the five vehicle kinds have one.
Catalogue_Vehicle_Spec :: proc(kind: Object_Kind) -> ^Vehicle_Spec {
	if spec_cache[kind] == nil {
		spec_cache[kind] = vehicle_spec_for(kind)
	}
	return &spec_cache[kind].?
}

Is_Ground_Vehicle :: proc(kind: Object_Kind) -> bool {
	#partial switch kind {
	case .Jeep, .Cargo_Truck, .Armored_Carrier, .Battle_Tank: return true
	}
	return false
}

// Anything you can get into and move: the ground vehicles and the helicopter.
Is_Drivable :: proc(kind: Object_Kind) -> bool {
	return Is_Ground_Vehicle(kind) || kind == .Helicopter
}

@(private = "file")
vehicle_spec_for :: proc(kind: Object_Kind) -> Vehicle_Spec {
	#partial switch kind {
	case .Jeep: return jeep_spec()
	case .Cargo_Truck: return cargo_truck_spec()
	case .Armored_Carrier: return armored_carrier_spec()
	case .Battle_Tank: return battle_tank_spec()
	case .Helicopter: return helicopter_spec()
	}
	panic("Catalogue_Vehicle_Spec: not a ground vehicle")
}

// The assembled vehicle at rest: hull, wheels on their mounts, turret and gun in place (what the catalogue and showroom show).
@(private = "file")
compose :: proc(spec: Vehicle_Spec) -> (parts: Parts) {
	append_offset(&parts, spec.body, {})
	for mount in spec.wheel_mounts do append_offset(&parts, spec.wheel, mount.position)
	append_offset(&parts, spec.turret, spec.turret_pivot)
	append_offset(&parts, spec.gun, spec.turret_pivot + spec.gun_pivot)
	append_offset(&parts, spec.main_rotor, spec.main_rotor_pivot)
	append_offset(&parts, spec.tail_rotor, spec.tail_rotor_pivot)
	return parts
}

@(private = "file")
append_offset :: proc(destination: ^Parts, source: Parts, offset: [3]f32) {
	for part in source {
		moved := part
		moved.position += offset
		append(destination, moved)
	}
}

// A light utility truck. Front is +Z; four wheels, a boxy cab, hood, spare tyre and headlights.
@(private = "file")
jeep_spec :: proc() -> (spec: Vehicle_Spec) {
	add_wheel(&spec.wheel, 0.45, 0.35, {})
	spec.wheel_radius = 0.45
	for x in ([2]f32{-0.98, 0.98}) {
		for z in ([2]f32{-1.5, 1.5}) do append(&spec.wheel_mounts, Wheel_Mount{{x, 0.45, z}, z > 0})
	}
	parts := &spec.body
	add_box(parts, {2, 0.55, 4.6}, {0, 0.8, 0}, .Olive_Paint)
	add_box(parts, {1.9, 0.35, 1.5}, {0, 1.2, 1.5}, .Olive_Paint)
	add_box(parts, {1.9, 0.7, 2.2}, {0, 1.45, -0.5}, .Olive_Paint)
	add_box(parts, {1.95, 0.1, 2.3}, {0, 1.85, -0.5}, .Olive_Paint)
	add_box(parts, {1.8, 0.55, 0.06}, {0, 1.5, 0.62}, .Glass, false)
	for x in ([2]f32{-0.96, 0.96}) do add_box(parts, {0.05, 0.5, 1.0}, {x, 1.5, -0.5}, .Glass, false)
	add_box(parts, {2.1, 0.2, 0.2}, {0, 0.55, 2.4}, .Rusted_Metal)
	add_box(parts, {2.1, 0.2, 0.2}, {0, 0.55, -2.4}, .Rusted_Metal, false)
	for x in ([2]f32{-0.7, 0.7}) {
		add_part(parts, Procedural.Part{primitive = Procedural.Sphere(0.12, 10, 5), position = {x, 0.95, 2.32}, stretch = {1, 1, 0.6}, material = layer(.Glass), emission = {1, 0.95, 0.8}})
	}
	add_cylinder_z(parts, 0.4, 0.25, {0, 0.9, -2.52}, .Rubber, false, 18)
	spec.seat = {0.4, 1.7, -0.3}
	spec.armor = 1
	spec.handling = World.Vehicle_Handling{
		speed_forward_max = 24, speed_reverse_max = 7, acceleration = 7, brake = 14, drag = 3, wheel_base = 3, steer_angle_max = 0.55,
		half_width = 1.05, half_length = 2.45, height = 2.0,
	}
	return spec
}

@(private = "file")
cargo_truck_spec :: proc() -> (spec: Vehicle_Spec) {
	add_wheel(&spec.wheel, 0.55, 0.3, {})
	spec.wheel_radius = 0.55
	for z in ([3]f32{3, -0.9, -2.5}) {
		for x in ([2]f32{-1.1, 1.1}) do append(&spec.wheel_mounts, Wheel_Mount{{x, 0.55, z}, z > 2})
	}
	parts := &spec.body
	add_box(parts, {2.2, 0.45, 7}, {0, 0.95, 0}, .Olive_Paint)
	add_box(parts, {2.3, 1.6, 1.9}, {0, 1.95, 2.7}, .Olive_Paint)
	add_box(parts, {2.35, 0.1, 1.95}, {0, 2.8, 2.7}, .Olive_Paint, false)
	add_box(parts, {2.1, 0.7, 0.06}, {0, 2.2, 3.66}, .Glass, false)
	add_box(parts, {2.1, 0.9, 1.3}, {0, 1.4, 4}, .Olive_Paint)
	add_box(parts, {2.3, 0.25, 0.2}, {0, 0.75, 4.7}, .Rusted_Metal, false)
	add_box(parts, {2.3, 0.2, 4.7}, {0, 1.3, -1.4}, .Wood)
	for x in ([2]f32{-1.15, 1.15}) do add_box(parts, {0.1, 0.6, 4.7}, {x, 1.7, -1.4}, .Olive_Paint, false)
	add_part(parts, Procedural.Part{primitive = Procedural.Box({2.2, 1.3, 4.6}, {4, 4, 4}), position = {0, 2.25, -1.4}, deformers = {0 = Procedural.Bulge{0.08}}, material = layer(.Canvas), solid = true})
	add_box(parts, {2.3, 0.2, 0.2}, {0, 0.75, -3.8}, .Rusted_Metal, false)
	for x in ([2]f32{-0.8, 0.8}) {
		add_part(parts, Procedural.Part{primitive = Procedural.Sphere(0.13, 10, 5), position = {x, 1.45, 4.66}, stretch = {1, 1, 0.6}, material = layer(.Glass), emission = {1, 0.95, 0.8}})
	}
	spec.seat = {0.5, 2.5, 2.8}
	spec.armor = 0.9
	spec.handling = World.Vehicle_Handling{
		speed_forward_max = 18, speed_reverse_max = 5, acceleration = 4, brake = 10, drag = 2.5, wheel_base = 5.5, steer_angle_max = 0.5,
		half_width = 1.2, half_length = 4.2, height = 3.2,
	}
	return spec
}

// Eight-wheeled troop carrier: sloped nose, boxy hull, small remote turret with a machine gun.
@(private = "file")
armored_carrier_spec :: proc() -> (spec: Vehicle_Spec) {
	add_wheel(&spec.wheel, 0.5, 0.35, {})
	spec.wheel_radius = 0.5
	for x in ([2]f32{-1.25, 1.25}) {
		for z in ([4]f32{-2.4, -0.8, 0.8, 2.4}) do append(&spec.wheel_mounts, Wheel_Mount{{x, 0.5, z}, z > 0})
	}
	parts := &spec.body
	add_box(parts, {2.7, 1.2, 6.2}, {0, 1.2, 0}, .Olive_Paint)
	add_part(parts, Procedural.Part{primitive = Procedural.Wedge({2.7, 1.2, 1.8}), position = {0, 1.2, 4}, material = layer(.Olive_Paint), solid = true})
	add_box(parts, {2.5, 0.7, 3.5}, {0, 2.15, -0.8}, .Olive_Paint)
	add_box(parts, {0.5, 0.15, 0.1}, {-0.7, 2.55, 1.0}, .Glass, false)
	for x in ([2]f32{-0.8, 0.8}) {
		add_part(parts, Procedural.Part{primitive = Procedural.Sphere(0.1, 8, 4), position = {x, 0.95, 4.2}, material = layer(.Glass), emission = {1, 0.95, 0.8}})
	}
	add_cylinder(&spec.turret, 0.65, 0.55, {}, .Olive_Paint, true, 18)
	add_cylinder_z(&spec.gun, 0.05, 1.8, {0, 0, 0.9}, .Rusted_Metal, false, 10)
	spec.turret_pivot = {0.5, 2.75, -0.5}
	spec.gun_pivot = {0, 0.05, 0.3}
	spec.muzzle = {0, 0, 1.85}
	spec.weapon = .Machine_Gun
	spec.seat = {-0.6, 2.35, 0.2}
	spec.armor = 0.25
	spec.handling = World.Vehicle_Handling{
		speed_forward_max = 16, speed_reverse_max = 5, acceleration = 3.5, brake = 9, drag = 2.5, wheel_base = 4, steer_angle_max = 0.45,
		half_width = 1.4, half_length = 3.6, height = 2.9,
	}
	return spec
}

// Main battle tank: low hull with a sloped glacis, track units with road wheels, a rounded turret and a long gun.
@(private = "file")
battle_tank_spec :: proc() -> (spec: Vehicle_Spec) {
	add_cylinder_x(&spec.wheel, 0.32, 0.72, {}, .Olive_Paint, false, 14)
	spec.wheel_radius = 0.32
	for x in ([2]f32{-1.5, 1.5}) {
		for index in 0 ..< 7 do append(&spec.wheel_mounts, Wheel_Mount{{x, 0.4, -2.7 + f32(index) * 0.9}, false})
	}
	parts := &spec.body
	add_box(parts, {3, 0.9, 6.2}, {0, 1.15, 0}, .Olive_Paint)
	add_part(parts, Procedural.Part{primitive = Procedural.Wedge({3, 0.7, 1.5}), position = {0, 1.25, 3.85}, material = layer(.Olive_Paint), solid = true})
	for x in ([2]f32{-1.5, 1.5}) do add_box(parts, {0.65, 0.9, 6.9}, {x, 0.45, 0}, .Rubber)
	add_part(&spec.turret, Procedural.Part{primitive = Procedural.Sphere(1, 20, 10), stretch = {1.6, 0.5, 1.9}, material = layer(.Olive_Paint), solid = true})
	add_cylinder(&spec.turret, 0.3, 0.25, {0.7, 0.6, -0.3}, .Olive_Paint, false, 12)
	add_box(&spec.turret, {0.5, 0.08, 0.2}, {-0.9, 0.45, 0.9}, .Glass, false)
	add_cylinder_z(&spec.gun, 0.12, 3.4, {0, 0, 1.7}, .Olive_Paint, true, 14)
	add_cylinder_z(&spec.gun, 0.17, 0.4, {0, 0, 3.55}, .Rusted_Metal, false, 14)
	spec.turret_pivot = {0, 2, -0.3}
	spec.gun_pivot = {0, 0.1, 1.5}
	spec.muzzle = {0, 0, 3.8}
	spec.weapon = .Cannon
	spec.seat = {0, 2.7, -0.6}
	spec.armor = 0.1
	spec.handling = World.Vehicle_Handling{
		speed_forward_max = 11, speed_reverse_max = 5, acceleration = 3.5, brake = 9, drag = 4, turn_rate_max = 0.9, tracked = true,
		half_width = 1.6, half_length = 3.2, height = 2.7,
	}
	return spec
}

@(private = "package")
jeep :: proc() -> Parts {
	return compose(Catalogue_Vehicle_Spec(.Jeep)^)
}

@(private = "package")
cargo_truck :: proc() -> Parts {
	return compose(Catalogue_Vehicle_Spec(.Cargo_Truck)^)
}

@(private = "package")
armored_carrier :: proc() -> Parts {
	return compose(Catalogue_Vehicle_Spec(.Armored_Carrier)^)
}

@(private = "package")
battle_tank :: proc() -> Parts {
	return compose(Catalogue_Vehicle_Spec(.Battle_Tank)^)
}

// A light utility helicopter: egg fuselage with a glass nose, tapering tail boom, a two-blade main rotor and a tail rotor, skids.
@(private = "file")
helicopter_spec :: proc() -> (spec: Vehicle_Spec) {
	parts := &spec.body
	add_part(parts, Procedural.Part{primitive = Procedural.Sphere(1.2, 20, 10), position = {0, 1.9, 0.2}, stretch = {0.9, 1, 2.1}, material = layer(.Olive_Paint), solid = true})
	add_part(parts, Procedural.Part{primitive = Procedural.Sphere(0.8, 16, 8), position = {0, 2.0, 1.9}, stretch = {0.9, 0.75, 1}, material = layer(.Glass), solid = true})
	add_part(parts, Procedural.Part{primitive = Procedural.Cylinder(0.35, 4.8, 12, 4), position = {0, 2.2, -4.7}, rotation_degrees = {90, 0, 0}, deformers = {0 = Procedural.Taper{0.35, 1}}, material = layer(.Olive_Paint), solid = true})
	add_box(parts, {0.08, 1.2, 0.9}, {0, 2.7, -6.9}, .Olive_Paint, false)
	add_cylinder(parts, 0.1, 0.7, {0, 3.3, 0.2}, .Rusted_Metal, false, 8)
	for x in ([2]f32{-1.1, 1.1}) {
		add_cylinder_z(parts, 0.05, 3.4, {x, 0.15, 0.3}, .Rusted_Metal, true, 8)
		add_cylinder(parts, 0.04, 1.4, {x, 0.85, 1.2}, .Rusted_Metal, false, 6)
		add_cylinder(parts, 0.04, 1.4, {x, 0.85, -0.6}, .Rusted_Metal, false, 6)
	}
	add_cylinder(&spec.main_rotor, 0.25, 0.15, {}, .Rusted_Metal, false, 10)
	add_box(&spec.main_rotor, {13, 0.05, 0.4}, {}, .Rusted_Metal)
	add_part(&spec.main_rotor, Procedural.Part{primitive = Procedural.Box({13, 0.05, 0.4}), rotation_degrees = {0, 90, 0}, material = layer(.Rusted_Metal), solid = true})
	add_box(&spec.tail_rotor, {0.03, 1.4, 0.12}, {}, .Rusted_Metal, false)
	add_box(&spec.tail_rotor, {0.03, 0.12, 1.4}, {}, .Rusted_Metal, false)
	spec.main_rotor_pivot = {0, 3.7, 0.2}
	spec.tail_rotor_pivot = {0.2, 2.7, -7.0}
	spec.seat = {-0.45, 2.15, 1.3}
	spec.armor = 0.5
	spec.is_aircraft = true
	spec.aircraft = World.Aircraft_Handling{
		climb_speed_max = 7, descent_speed_max = 5, vertical_acceleration = 4,
		forward_speed_max = 36, strafe_speed_max = 14, horizontal_acceleration = 9,
		yaw_rate_max = 1.5, tilt_max = 0.32, tilt_follow_per_second = 4,
		spool_up_seconds = 4, spool_down_seconds = 8, lift_rotor_threshold = 0.92,
		half_width = 1.3, half_length = 5.2, hull_center_z = -2.2, height = 3.7,
	}
	return spec
}

@(private = "package")
helicopter :: proc() -> Parts {
	return compose(Catalogue_Vehicle_Spec(.Helicopter)^)
}
