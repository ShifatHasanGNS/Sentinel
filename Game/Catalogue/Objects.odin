package Catalogue

import "../../Engine/Procedural"
import "../Materials"
import "core:fmt"
import "core:math"
import "core:strings"
import "core:sync"

// Every object the base is built from. Objects stand on y = 0, face +Z; buildings are long along X, vehicles along Z.
Object_Kind :: enum {
	// Buildings.
	Barracks,
	Headquarters,
	Hangar,
	Mess_Hall,
	Generator_Shed,
	Fuel_Tank,
	Water_Tower,
	Watchtower,
	Guard_Post,
	Bunker,
	Helipad,
	Radio_Mast,
	Radar_Station,
	// Fortifications.
	Fence_Section,
	Gate,
	Barrier_Arm,
	T_Wall,
	Hesco_Barrier,
	Sandbag_Wall,
	// Vehicles.
	Jeep,
	Cargo_Truck,
	Armored_Carrier,
	Battle_Tank,
	Helicopter,
	// Props.
	Crate,
	Barrel,
	Pallet,
	Tent,
	Camo_Net,
	Floodlight,
	Sign,
	Flag,
	Ammo_Box,
}

Catalogue_Build :: proc(kind: Object_Kind) -> Procedural.Assembly {
	parts := object_parts(kind)
	defer delete(parts)
	return Procedural.Assembly_Build(parts[:])
}

// Whether `name` is this object's name, ignoring case (for command-line selection).
Object_Name_Matches :: proc(kind: Object_Kind, name: string) -> bool {
	return strings.equal_fold(object_name(kind), name)
}

// The solid parts alone: what must cast a shadow. Cheaper than the full object because thin wires, bars and panes are left out.
Catalogue_Build_Shadow :: proc(kind: Object_Kind) -> Procedural.Assembly {
	parts := object_parts(kind)
	defer delete(parts)
	solid := make(Parts)
	defer delete(solid)
	for part in parts do if part.solid do append(&solid, part)
	return Procedural.Assembly_Build(solid[:])
}

@(private = "package")
Parts :: [dynamic]Procedural.Part

@(private = "package")
object_name :: proc(kind: Object_Kind) -> string {
	return fmt.tprintf("%v", kind)
}

@(private = "file")
object_parts :: proc(kind: Object_Kind) -> Parts {
	switch kind {
	case .Barracks: return barracks()
	case .Headquarters: return headquarters()
	case .Hangar: return hangar()
	case .Mess_Hall: return mess_hall()
	case .Generator_Shed: return generator_shed()
	case .Fuel_Tank: return fuel_tank()
	case .Water_Tower: return water_tower()
	case .Watchtower: return watchtower()
	case .Guard_Post: return guard_post()
	case .Bunker: return bunker()
	case .Helipad: return helipad()
	case .Radio_Mast: return radio_mast()
	case .Radar_Station: return radar_station()
	case .Fence_Section: return fence_section()
	case .Gate: return gate()
	case .Barrier_Arm: return barrier_arm()
	case .T_Wall: return t_wall()
	case .Hesco_Barrier: return hesco_barrier()
	case .Sandbag_Wall: return sandbag_wall()
	case .Jeep: return jeep()
	case .Cargo_Truck: return cargo_truck()
	case .Armored_Carrier: return armored_carrier()
	case .Battle_Tank: return battle_tank()
	case .Helicopter: return helicopter()
	case .Crate: return crate()
	case .Barrel: return barrel()
	case .Pallet: return pallet()
	case .Tent: return tent()
	case .Camo_Net: return camo_net()
	case .Floodlight: return floodlight()
	case .Sign: return sign()
	case .Flag: return flag()
	case .Ammo_Box: return ammo_box()
	}
	unreachable()
}

// --- Helpers shared by the object tables ---

@(private = "package")
layer :: proc(material: Materials.Surface_Material) -> i32 {
	return i32(material)
}

// A solid-by-default box part; most of an object is boxes.
@(private = "package")
add_box :: proc(parts: ^Parts, size, position: [3]f32, material: Materials.Surface_Material, solid := true, rotation := [3]f32{}, emission := [3]f32{}) {
	append(parts, Procedural.Part{primitive = Procedural.Box(size), position = position, rotation_degrees = rotation, material = layer(material), emission = emission, solid = solid})
}

// An invisible collision box: the volume a body cannot enter (a chain-link panel is mostly air, but you cannot walk through it).
@(private = "package")
add_collision_box :: proc(parts: ^Parts, size, position: [3]f32) {
	append(parts, Procedural.Part{primitive = Procedural.Box(size), position = position, collision_only = true})
}

// A box with a subdivided surface and a gentle bulge: pressed-sheet body panels are slightly domed, not razor-flat.
@(private = "package")
add_rounded_box :: proc(parts: ^Parts, size, position: [3]f32, material: Materials.Surface_Material, bulge := f32(0.05)) {
	append(parts, Procedural.Part{primitive = Procedural.Box(size, {6, 6, 6}), position = position, deformers = {0 = Procedural.Bulge{bulge}}, material = layer(material), solid = true})
}

@(private = "package")
add_part :: proc(parts: ^Parts, part: Procedural.Part) {
	append(parts, part)
}

// A cylinder lying along the X axis (axes of Procedural.Cylinder are Y).
@(private = "package")
add_cylinder_x :: proc(parts: ^Parts, radius, length: f32, position: [3]f32, material: Materials.Surface_Material, solid := true, segments := 16) {
	append(parts, Procedural.Part{primitive = Procedural.Cylinder(radius, length, segments), position = position, rotation_degrees = {0, 0, 90}, material = layer(material), solid = solid})
}

// A cylinder lying along the Z axis.
@(private = "package")
add_cylinder_z :: proc(parts: ^Parts, radius, length: f32, position: [3]f32, material: Materials.Surface_Material, solid := true, segments := 16) {
	append(parts, Procedural.Part{primitive = Procedural.Cylinder(radius, length, segments), position = position, rotation_degrees = {90, 0, 0}, material = layer(material), solid = solid})
}

@(private = "package")
add_cylinder :: proc(parts: ^Parts, radius, height: f32, position: [3]f32, material: Materials.Surface_Material, solid := true, segments := 16) {
	append(parts, Procedural.Part{primitive = Procedural.Cylinder(radius, height, segments), position = position, material = layer(material), solid = solid})
}

// A wheel with its axle along X: rubber tyre plus a metal hub.
@(private = "package")
add_wheel :: proc(parts: ^Parts, radius, width: f32, position: [3]f32) {
	add_cylinder_x(parts, radius, width, position, .Rubber, true, 20)
	add_cylinder_x(parts, radius * 0.5, width * 1.04, position, .Painted_Metal, false, 12)
	for lug in 0 ..< 18 { // Tread blocks around the tyre, each a small box standing proud of the surface.
		angle := f32(lug) / 18 * 2 * math.PI
		offset := [3]f32{0, math.cos(angle), math.sin(angle)} * (radius + 0.012)
		append(parts, Procedural.Part{primitive = Procedural.Box({width * 0.96, 0.03, radius * 0.28}), position = position + offset, rotation_degrees = {math.to_degrees(-angle) + 90, 0, 0}, material = layer(.Rubber)})
	}
	for nut in 0 ..< 6 { // Wheel nuts on the hub face.
		angle := f32(nut) / 6 * 2 * math.PI
		for side in ([2]f32{-1, 1}) {
			offset := [3]f32{side * width * 0.53, math.cos(angle) * radius * 0.28, math.sin(angle) * radius * 0.28}
			add_cylinder_x(parts, radius * 0.04, 0.025, position + offset, .Gunmetal, false, 6)
		}
	}
}

// A gable roof: two wedges meeting at a ridge along X, covering `length` x `depth` and `rise` tall, its base at base_y.
@(private = "package")
add_gable_roof :: proc(parts: ^Parts, length, depth, rise, base_y: f32, position_z: f32, material: Materials.Surface_Material) {
	half := depth / 2
	add_part(parts, Procedural.Part{primitive = Procedural.Wedge({length, rise, half}), position = {0, base_y + rise / 2, position_z + half / 2}, material = layer(material), solid = true})
	add_part(parts, Procedural.Part{primitive = Procedural.Wedge({length, rise, half}), position = {0, base_y + rise / 2, position_z - half / 2}, rotation_degrees = {0, 180, 0}, material = layer(material), solid = true})

	// Trim that makes it read as a roof rather than two slabs: a ridge cap along the top, a fascia board and a half-round gutter along
	// each eave.
	add_box(parts, {length + 0.1, 0.07, 0.3}, {0, base_y + rise + 0.02, position_z}, material, false)
	for side in ([2]f32{-1, 1}) {
		eave_z := position_z + side * half
		add_box(parts, {length + 0.1, 0.16, 0.05}, {0, base_y - 0.04, eave_z}, .Wood, false)
		add_cylinder_x(parts, 0.06, length + 0.1, {0, base_y - 0.13, eave_z + side * 0.07}, .Painted_Metal, false, 8)
	}
}

// A window on a wall facing +Z: the glowing pane, a frame of four bars standing proud of the wall, a mullion across the middle,
// and a sill underneath that sheds water past the wall face.
@(private = "package")
add_window :: proc(parts: ^Parts, size: [2]f32, x, y, z: f32) {
	add_box(parts, {size.x, size.y, 0.1}, {x, y, z}, .Glass, false, {}, {0.9, 0.65, 0.3})
	bar := f32(0.07)
	add_box(parts, {size.x + 2 * bar, bar, 0.16}, {x, y + size.y / 2 + bar / 2, z + 0.03}, .Gunmetal, false)
	add_box(parts, {size.x + 2 * bar, bar, 0.16}, {x, y - size.y / 2 - bar / 2, z + 0.03}, .Gunmetal, false)
	for side in ([2]f32{-1, 1}) do add_box(parts, {bar, size.y, 0.16}, {x + side * (size.x / 2 + bar / 2), y, z + 0.03}, .Gunmetal, false)
	add_box(parts, {size.x, 0.04, 0.14}, {x, y, z + 0.04}, .Gunmetal, false)
	add_box(parts, {size.x + 0.3, 0.07, 0.3}, {x, y - size.y / 2 - bar - 0.035, z + 0.1}, .Concrete, false)
}

// A row of windows on a wall facing +Z: `count` windows centred about x = 0, spaced `spacing` apart.
@(private = "package")
add_front_windows :: proc(parts: ^Parts, count: int, spacing: f32, y, z: f32, size: [2]f32) {
	for index in 0 ..< count do add_window(parts, size, (f32(index) - f32(count - 1) / 2) * spacing, y, z)
}

@(private = "package")
degrees :: proc(radians: f32) -> f32 {
	return math.to_degrees(radians)
}

// What the rest of the game needs to know about an object without its meshes: its extent and its collision boxes.
Object_Info :: struct {
	lowest:          [3]f32,
	highest:         [3]f32,
	collision_boxes: []Procedural.Collision_Box,
}

@(private = "file")
info_cache: [Object_Kind]Maybe(Object_Info)

@(private = "package")
cache_lock: sync.Recursive_Mutex // Test packages run in parallel threads; the caches are filled under this lock.

// Computed on first use and kept for the life of the program.
Catalogue_Info :: proc(kind: Object_Kind) -> Object_Info {
	sync.recursive_mutex_lock(&cache_lock)
	defer sync.recursive_mutex_unlock(&cache_lock)
	if info, cached := info_cache[kind].?; cached do return info
	assembly := Catalogue_Build(kind)
	defer Procedural.Assembly_Destroy(&assembly)
	info: Object_Info
	info.lowest, info.highest = Procedural.Assembly_Bounds(assembly)
	info.collision_boxes = make([]Procedural.Collision_Box, len(assembly.collision_boxes))
	copy(info.collision_boxes, assembly.collision_boxes[:])
	info_cache[kind] = info
	return info
}
