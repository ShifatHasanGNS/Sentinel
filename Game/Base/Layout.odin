package Base

import "../Catalogue"
import "../../Engine/Procedural"
import "core:math"

PERIMETER_RADIUS_METERS :: 62.0
PERIMETER_SLOTS :: 128 // Divisible by 8, so towers sit on whole slots at the diagonals.
GATE_SLOT_COUNT :: 3
POSITION_JITTER_METERS :: 0.12
YAW_JITTER_DEGREES :: 8.0

// The base: a fenced compound on the plateau with its gate on the south side (+Z), laid out deterministically from a seed.
Layout :: struct {
	placements: [dynamic]Placement,
	seed:       u32,
	jitter_index: u32,
}

Layout_Create :: proc(seed: u32, plateau_radius_meters: f32) -> (layout: Layout) {
	assert(plateau_radius_meters > PERIMETER_RADIUS_METERS + 20, "Layout_Create: plateau too small for the compound")
	layout.seed = seed
	add_perimeter(&layout)
	add_command_area(&layout)
	add_airfield(&layout)
	add_motor_pool(&layout)
	add_supply_yard(&layout)
	add_camp(&layout)
	add_gate_approach(&layout)
	add_paving(&layout)
	return layout
}

Layout_Destroy :: proc(layout: ^Layout) {
	delete(layout.placements)
	layout^ = {}
}

// The perimeter is a ring of equal slots. A watchtower fills one slot, the gate three, a fence section each of the rest, so
// the ring is closed by construction. Slot 0 is at due south; slots count counter-clockwise seen from above.
@(private = "file")
add_perimeter :: proc(layout: ^Layout) {
	tower_slots := [4]int{-48, -16, 16, 48}
	for slot in 0 ..< PERIMETER_SLOTS {
		signed_slot := slot if slot <= PERIMETER_SLOTS / 2 else slot - PERIMETER_SLOTS
		angle := math.PI / 2 + f32(signed_slot) * 2 * math.PI / PERIMETER_SLOTS
		position := [2]f32{math.cos(angle), math.sin(angle)} * PERIMETER_RADIUS_METERS
		yaw := math.to_degrees(math.atan2(math.cos(angle), math.sin(angle))) // Front (+Z) points outward.
		kind := Catalogue.Object_Kind.Fence_Section
		if abs(signed_slot) < GATE_SLOT_COUNT / 2 + 1 && abs(signed_slot) > 0 do continue // The two slots beside the gate's centre belong to it.
		if signed_slot == 0 do kind = .Gate
		for tower_slot in tower_slots do if signed_slot == tower_slot do kind = .Watchtower
		place(layout, kind, position.x, position.y, yaw)
	}
}

@(private = "file")
add_command_area :: proc(layout: ^Layout) {
	place(layout, .Headquarters, 0, -6, 0)
	for z in ([3]f32{-24, -2, 20}) do place(layout, .Barracks, -44, z, 90)
	place(layout, .Mess_Hall, -22, 36, 0)
	place(layout, .Generator_Shed, -14, -30, 0)
	place(layout, .Fuel_Tank, 10, -40, 0)
	place(layout, .Fuel_Tank, 10, -46, 0)
	place(layout, .Water_Tower, -8, -42, 0)
	place(layout, .Radar_Station, 0, -52, 0)
	place(layout, .Radio_Mast, 50, 0, 0)
	place(layout, .Bunker, -22, -48, 0)
	place(layout, .Bunker, 24, -48, 0)
	for x_index in 0 ..< 6 do place(layout, .T_Wall, -7.5 + f32(x_index) * 3, -14, 0)
	place(layout, .Flag, 11, -4, 0)
}

@(private = "file")
add_airfield :: proc(layout: ^Layout) {
	place(layout, .Hangar, 36, -26, 0)
	place(layout, .Helipad, 30, 16, 0)
	place(layout, .Helicopter, 30, 16, 0)
}

// Vehicles parked in a row facing north, jittered a few degrees as if parked by hand; a net covers the tanks.
@(private = "file")
add_motor_pool :: proc(layout: ^Layout) {
	row := [?]struct {
		kind: Catalogue.Object_Kind,
		x:    f32,
	}{{.Jeep, -10}, {.Jeep, -5}, {.Cargo_Truck, 2}, {.Cargo_Truck, 7}, {.Armored_Carrier, 13}, {.Armored_Carrier, 18}, {.Battle_Tank, 24}, {.Battle_Tank, 30}}
	for vehicle in row do place(layout, vehicle.kind, vehicle.x, 46, 180 + jitter(layout) * YAW_JITTER_DEGREES)
	place(layout, .Camo_Net, 27, 46, 0)
}

@(private = "file")
add_supply_yard :: proc(layout: ^Layout) {
	for index in 0 ..< 3 do place_loose(layout, .Pallet, 16 + f32(index) * 2.5, -4)
	for index in 0 ..< 6 do place_loose(layout, .Crate, 16 + f32(index % 3) * 1.4, 1 + f32(index / 3) * 1.4)
	for index in 0 ..< 6 do place_loose(layout, .Barrel, 21 + f32(index % 3) * 0.9, 1 + f32(index / 3) * 0.9)
	for index in 0 ..< 6 do place_loose(layout, .Ammo_Box, 16 + f32(index) * 0.8, 5)
}

@(private = "file")
add_camp :: proc(layout: ^Layout) {
	for z in ([3]f32{-18, -8, 2}) do place(layout, .Tent, -14, z, 0)
	place(layout, .Camo_Net, -15.5, -8, 0)
	flood_angles := [6]f32{20, 70, 160, 200, 250, 340}
	for angle_degrees in flood_angles {
		angle := math.to_radians(angle_degrees)
		place(layout, .Floodlight, 56 * math.cos(angle), 56 * math.sin(angle), 90 - angle_degrees)
	}
}

// Everything at and beyond the gate: guard posts, sandbag positions, signs, a boom barrier and a chicane of Hesco barriers.
@(private = "file")
add_gate_approach :: proc(layout: ^Layout) {
	for x in ([2]f32{-8, 8}) {
		place(layout, .Guard_Post, x, 56, 0)
		place(layout, .Sandbag_Wall, x, 60, 0)
		place(layout, .Sign, x * 1.5, 66, 0)
	}
	place(layout, .Barrier_Arm, 3, 70, 0)
	for x in ([4]f32{-14, -8, 8, 14}) do place(layout, .Hesco_Barrier, x, 68 + abs(x) * 0.3, 0)
}

// The compound's surfacing: a main road from the gate to the headquarters forecourt, a cross road, a parade ground in front of the
// headquarters, a footpath beside the barracks, the motor pool's apron and two lawns. All flat and non-solid.
@(private = "file")
add_paving :: proc(layout: ^Layout) {
	for z in ([4]f32{70, 54, 38, 22}) do place(layout, .Road, 0, z, 0)
	for x in ([4]f32{-24, -8, 8, 24}) do place(layout, .Road, x, 28, 90)
	place(layout, .Parade_Ground, 0, 7, 0)
	for z in ([4]f32{-24, -8, 8, 24}) do place(layout, .Walkway, -37, z, 0)
	place(layout, .Apron, 10, 46, 0)
	place(layout, .Lawn, -14, 14, 0)
	place(layout, .Lawn, 14, 14, 0)
}

@(private = "file")
place :: proc(layout: ^Layout, kind: Catalogue.Object_Kind, x, z, yaw_degrees: f32) {
	append(&layout.placements, Placement{kind, x, z, yaw_degrees})
}

// Small things lie where they were dropped: nudged and turned at random, but the same every run for a seed.
@(private = "file")
place_loose :: proc(layout: ^Layout, kind: Catalogue.Object_Kind, x, z: f32) {
	place(layout, kind, x + jitter(layout) * POSITION_JITTER_METERS, z + jitter(layout) * POSITION_JITTER_METERS, jitter(layout) * 180)
}

// A deterministic value in [-1, 1) that changes with every call and with the seed.
@(private = "file")
jitter :: proc(layout: ^Layout) -> f32 {
	layout.jitter_index += 1
	return Procedural.Hash_To_Unit_Float(Procedural.Hash_Lattice_3(i32(layout.jitter_index), 17, 3, layout.seed)) * 2 - 1
}
