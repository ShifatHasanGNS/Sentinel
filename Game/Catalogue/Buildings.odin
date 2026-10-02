package Catalogue

import "../../Engine/Procedural"
import "../Materials"
import "core:math"

// Four walls around a room, standing on y = base_y. The +Z wall is cut at each door: wall segments between the openings and a
// lintel above each. The back and side walls are solid boxes, so the inside is open floor a body can walk across.
@(private = "package")
add_walled_room :: proc(parts: ^Parts, size: [3]f32, base_y, thickness: f32, material: Materials.Surface_Material, doors: []Door_Spec) {
	width, height, depth := size.x, size.y, size.z
	middle_y := base_y + height / 2
	add_box(parts, {width, height, thickness}, {0, middle_y, -depth / 2 + thickness / 2}, material)
	for x in ([2]f32{-1, 1}) do add_box(parts, {thickness, height, depth - 2 * thickness}, {x * (width / 2 - thickness / 2), middle_y, 0}, material)
	front_z := depth / 2 - thickness / 2
	cursor := -width / 2
	for door in doors_by_position(doors, context.temp_allocator) {
		opening_start, opening_end := Door_Center_X(door) - door.width / 2, Door_Center_X(door) + door.width / 2
		add_wall_segment(parts, cursor, opening_start, base_y, height, front_z, thickness, material)
		lintel_height := base_y + height - (door.hinge.y + door.height)
		if lintel_height > 0.01 do add_box(parts, {door.width, lintel_height, thickness}, {Door_Center_X(door), door.hinge.y + door.height + lintel_height / 2, front_z}, material)
		cursor = opening_end
	}
	add_wall_segment(parts, cursor, width / 2, base_y, height, front_z, thickness, material)
}

@(private = "file")
add_wall_segment :: proc(parts: ^Parts, from_x, to_x, base_y, height, z, thickness: f32, material: Materials.Surface_Material) {
	if to_x - from_x < 0.01 do return
	add_box(parts, {to_x - from_x, height, thickness}, {(from_x + to_x) / 2, base_y + height / 2, z}, material)
}

@(private = "file")
doors_by_position :: proc(doors: []Door_Spec, allocator := context.allocator) -> []Door_Spec {
	sorted := make([]Door_Spec, len(doors), allocator)
	copy(sorted, doors)
	for i in 1 ..< len(sorted) {
		for j := i; j > 0 && Door_Center_X(sorted[j]) < Door_Center_X(sorted[j - 1]); j -= 1 do sorted[j], sorted[j - 1] = sorted[j - 1], sorted[j]
	}
	return sorted
}

// A ceiling light: a small glowing panel (the point light that goes with it is in Game/Base/InteriorLights.odin).
@(private = "package")
add_lamp_panel :: proc(parts: ^Parts, position: [3]f32) {
	add_box(parts, {0.55, 0.06, 0.28}, position, .Glass, false, {}, {2.2, 1.9, 1.4})
}

// A two-tier bunk bed standing on the floor at `position` (its centre footprint), long along Z.
@(private = "file")
add_bunk :: proc(parts: ^Parts, position: [3]f32) {
	for tier in ([2]f32{0.5, 1.3}) do add_box(parts, {0.9, 0.14, 2}, {position.x, position.y + tier, position.z}, .Fabric_Dark)
	for corner in ([4][2]f32{{-0.42, -0.95}, {0.42, -0.95}, {-0.42, 0.95}, {0.42, 0.95}}) {
		add_cylinder(parts, 0.025, 1.9, {position.x + corner.x, position.y + 0.95, position.z + corner.y}, .Rusted_Metal, false, 6)
	}
}

// A long wooden table with a bench along each side, long along X.
@(private = "file")
add_table_with_benches :: proc(parts: ^Parts, position: [3]f32, length: f32) {
	add_box(parts, {length, 0.06, 0.9}, {position.x, position.y + 0.78, position.z}, .Wood)
	for z in ([2]f32{-0.8, 0.8}) {
		add_box(parts, {length, 0.05, 0.3}, {position.x, position.y + 0.45, position.z + z}, .Wood)
		for x in ([2]f32{-1, 1}) do add_box(parts, {0.05, 0.45, 0.25}, {position.x + x * (length / 2 - 0.2), position.y + 0.22, position.z + z}, .Wood, false)
	}
	for x in ([2]f32{-1, 1}) do add_box(parts, {0.06, 0.78, 0.7}, {position.x + x * (length / 2 - 0.2), position.y + 0.39, position.z}, .Wood, false)
}

// A desk with a computer on it, its screen facing +Z.
@(private = "file")
add_desk_with_computer :: proc(parts: ^Parts, position: [3]f32, width: f32) {
	add_box(parts, {width, 0.05, 0.8}, {position.x, position.y + 0.75, position.z}, .Wood)
	for x in ([2]f32{-1, 1}) do add_box(parts, {0.05, 0.75, 0.7}, {position.x + x * (width / 2 - 0.08), position.y + 0.375, position.z}, .Painted_Metal, false)
	add_box(parts, {0.55, 0.4, 0.04}, {position.x, position.y + 1.2, position.z - 0.1}, .Glass, false, {}, {0.1, 1.4, 0.35})
	add_box(parts, {0.4, 0.02, 0.15}, {position.x, position.y + 0.79, position.z + 0.15}, .Painted_Metal, false)
}

BARRACKS_SIZE :: [3]f32{18, 2.8, 6}

// A long hut: plinth, walls with two doors, a row of bunks along the back wall, windows on the front, a gable roof.
@(private = "package")
barracks :: proc() -> (parts: Parts) {
	add_box(&parts, {18.4, 0.3, 6.9}, {0, 0.15, 0}, .Concrete)
	add_walled_room(&parts, BARRACKS_SIZE, 0.3, 0.3, .Concrete, BARRACKS_DOORS[:])
	add_gable_roof(&parts, 18.6, 7, 1.4, 3.1, 0, .Painted_Metal)
	for index in 0 ..< 7 do add_bunk(&parts, {-7.5 + f32(index) * 2.5, 0.3, -1.7})
	for x in ([3]f32{-6, 0, 6}) do add_lamp_panel(&parts, {x, 2.95, 0.4})
	for x in ([2]f32{-7, 7}) do add_box(&parts, {1.6, 0.3, 0.8}, {x, 0.15, 3.4}, .Concrete, false)
	add_front_windows(&parts, 5, 2, 2, 3.05, {1.1, 1})
	return parts
}

// Where the computer stands in the headquarters, in its own frame: the target of the hacking objective.
HEADQUARTERS_TERMINAL :: [3]f32{-3.5, 1.5, -4.1}

@(private = "package")
headquarters :: proc() -> (parts: Parts) {
	add_box(&parts, {14.4, 0.3, 10.4}, {0, 0.15, 0}, .Concrete)
	add_walled_room(&parts, {14, 3, 10}, 0.3, 0.3, .Concrete, HEADQUARTERS_DOORS[:])
	add_box(&parts, {14.6, 0.3, 10.6}, {0, 3.45, 0}, .Concrete)
	add_box(&parts, {5, 1.6, 4}, {-2, 4.4, -1}, .Concrete)
	add_cylinder(&parts, 0.08, 3, {5, 5.1, -3}, .Rusted_Metal, false, 8)
	for x in ([6]f32{-5.4, -3.6, -1.8, 1.8, 3.6, 5.4}) do add_window(&parts, {1.2, 1.1}, x, 2.1, 5.05)
	for x in ([2]f32{-0.9, 0.9}) do add_box(&parts, {0.12, 2.5, 0.16}, {x * 1.35, 1.55, 5.08}, .Concrete, false)
	add_box(&parts, {3.1, 0.14, 0.4}, {0, 2.85, 5.2}, .Concrete, false)
	add_box(&parts, {3, 0.3, 1.2}, {0, 0.15, 5.6}, .Concrete, false)
	add_desk_with_computer(&parts, {-3.5, 0.3, -4}, 2.2)
	add_desk_with_computer(&parts, {3.5, 0.3, -4}, 2.2)
	add_table_with_benches(&parts, {0, 0.3, -0.5}, 4)
	add_box(&parts, {3.5, 1.6, 0.05}, {0, 1.9, -4.72}, .Sand, false)
	for x in ([2]f32{-3.5, 3.5}) do add_lamp_panel(&parts, {x, 3.1, 0})
	return parts
}

// A half-pipe roof of nine slabs; each slab is tangent to a circle of radius 8 about the floor line.
@(private = "package")
hangar :: proc() -> (parts: Parts) {
	radius: f32 = 8
	segments := 9
	step := f32(180) / f32(segments)
	chord := 2 * radius * math.sin(math.to_radians(step) / 2)
	for index in 0 ..< segments {
		middle := (f32(index) + 0.5) * step
		inset := radius * math.cos(math.to_radians(step) / 2)
		add_part(&parts, Procedural.Part{
			primitive = Procedural.Box({chord + 0.1, 0.25, 24}),
			position = {inset * math.cos(math.to_radians(middle)), inset * math.sin(math.to_radians(middle)), 0},
			rotation_degrees = {0, 0, middle + 90},
			material = layer(.Painted_Metal),
		})
	}
	add_box(&parts, {16.4, 0.2, 24.4}, {0, 0.1, 0}, .Concrete, false)
	add_box(&parts, {15.6, 7.6, 0.3}, {0, 3.8, -12}, .Painted_Metal)
	for x in ([2]f32{-7.85, 7.85}) do add_box(&parts, {0.3, 4, 24}, {x, 2, 0}, .Painted_Metal)
	return parts
}

@(private = "package")
mess_hall :: proc() -> (parts: Parts) {
	add_box(&parts, {14.4, 0.3, 8.4}, {0, 0.15, 0}, .Concrete)
	add_walled_room(&parts, {14, 2.7, 8}, 0.3, 0.3, .Wood, MESS_HALL_DOORS[:])
	add_gable_roof(&parts, 14.8, 9, 1.6, 3, 0, .Painted_Metal)
	add_cylinder(&parts, 0.35, 2.4, {5, 4.4, -2.5}, .Concrete, false, 10)
	add_front_windows(&parts, 4, 2.6, 1.9, 4.05, {1.3, 1.1})
	for x in ([2]f32{-3.5, 3}) do add_table_with_benches(&parts, {x, 0.3, -1}, 5)
	for x in ([2]f32{-4, 4}) do add_lamp_panel(&parts, {x, 2.9, 0})
	return parts
}

@(private = "package")
generator_shed :: proc() -> (parts: Parts) {
	add_box(&parts, {3.4, 0.1, 3}, {0, 0.05, 0}, .Concrete)
	add_walled_room(&parts, {3.4, 2.2, 3}, 0, 0.12, .Painted_Metal, GENERATOR_SHED_DOORS[:])
	add_box(&parts, {3.7, 0.15, 3.3}, {0, 2.3, 0}, .Painted_Metal)
	add_cylinder(&parts, 0.12, 0.9, {1.1, 2.7, -0.8}, .Rusted_Metal, false, 8)
	for index in 0 ..< 4 do add_box(&parts, {0.04, 0.9, 1.4}, {1.72, 1.2, -0.9 + f32(index) * 0.55}, .Rusted_Metal, false)
	add_box(&parts, {1.5, 1.1, 0.9}, {0.6, 0.65, -0.7}, .Olive_Paint)
	add_lamp_panel(&parts, {0, 2.1, 0})
	return parts
}

// One horizontal tank on two concrete cradles, with a manway hatch and a filler pipe.
@(private = "package")
fuel_tank :: proc() -> (parts: Parts) {
	add_part(&parts, Procedural.Part{primitive = Procedural.Cylinder(1.4, 7, 24, 2), position = {0, 1.9, 0}, rotation_degrees = {0, 0, 90}, deformers = {0 = Procedural.Bulge{0.04}}, material = layer(.Painted_Metal), solid = true})
	for x in ([2]f32{-2.4, 2.4}) do add_box(&parts, {0.6, 0.5, 2.4}, {x, 0.25, 0}, .Concrete)
	add_cylinder(&parts, 0.35, 0.25, {0, 3.4, 0}, .Rusted_Metal, false, 12)
	add_cylinder(&parts, 0.08, 0.8, {-3, 2.6, 0.9}, .Rusted_Metal, false, 8)
	return parts
}

@(private = "package")
water_tower :: proc() -> (parts: Parts) {
	for x in ([2]f32{-2, 2}) {
		for z in ([2]f32{-2, 2}) do add_cylinder(&parts, 0.18, 8, {x, 4, z}, .Rusted_Metal, true, 10)
	}
	for height in ([2]f32{2.5, 5.5}) {
		add_box(&parts, {4.2, 0.1, 0.1}, {0, height, 2}, .Rusted_Metal, false)
		add_box(&parts, {4.2, 0.1, 0.1}, {0, height, -2}, .Rusted_Metal, false)
		add_box(&parts, {0.1, 0.1, 4.2}, {2, height, 0}, .Rusted_Metal, false)
		add_box(&parts, {0.1, 0.1, 4.2}, {-2, height, 0}, .Rusted_Metal, false)
	}
	add_part(&parts, Procedural.Part{primitive = Procedural.Cylinder(2.4, 4, 24, 3), position = {0, 10, 0}, deformers = {0 = Procedural.Bulge{0.05}}, material = layer(.Painted_Metal), solid = true})
	add_part(&parts, Procedural.Part{primitive = Procedural.Cone(2.6, 1.2, 24), position = {0, 12.6, 0}, material = layer(.Painted_Metal)})
	add_box(&parts, {0.1, 3.5, 0.1}, {2.6, 8.2, 0}, .Rusted_Metal, false)
	return parts
}

@(private = "package")
watchtower :: proc() -> (parts: Parts) {
	for x in ([2]f32{-1.1, 1.1}) {
		for z in ([2]f32{-1.1, 1.1}) {
			add_part(&parts, Procedural.Part{primitive = Procedural.Cylinder(0.13, 6, 10, 2), position = {x, 3, z}, deformers = {0 = Procedural.Taper{1.3, 1}}, material = layer(.Wood), solid = true})
		}
	}
	add_collision_box(&parts, {2.5, 3.2, 2.5}, {0, 1.6, 0}) // The legs stand 2.2 m apart: a body fits between them, and a tower is a link in the perimeter, so its base is closed.
	for height in ([2]f32{1.8, 3.8}) {
		add_box(&parts, {2.3, 0.08, 0.08}, {0, height, 1.1}, .Wood, false)
		add_box(&parts, {2.3, 0.08, 0.08}, {0, height, -1.1}, .Wood, false)
		add_box(&parts, {0.08, 0.08, 2.3}, {1.1, height, 0}, .Wood, false)
		add_box(&parts, {0.08, 0.08, 2.3}, {-1.1, height, 0}, .Wood, false)
	}
	add_box(&parts, {3, 0.2, 3}, {0, 6.1, 0}, .Wood)
	add_box(&parts, {2.6, 1.6, 2.6}, {0, 7, 0}, .Wood)
	add_box(&parts, {2.7, 0.7, 0.1}, {0, 7.2, 1.35}, .Glass, false, {}, {0.9, 0.65, 0.3})
	add_part(&parts, Procedural.Part{primitive = Procedural.Cone(2.2, 0.9, 4), position = {0, 8.25, 0}, rotation_degrees = {0, 45, 0}, material = layer(.Painted_Metal), solid = true})
	add_cylinder_z(&parts, 0.18, 0.5, {1.1, 7.6, 1.5}, .Painted_Metal, false, 12)
	add_box(&parts, {0.08, 6.2, 0.4}, {-0.4, 3.1, 1.45}, .Wood, false)
	return parts
}

@(private = "package")
guard_post :: proc() -> (parts: Parts) {
	add_box(&parts, {3, 0.1, 3}, {0, 0.05, 0}, .Concrete)
	add_walled_room(&parts, {3, 2.5, 3}, 0, 0.2, .Concrete, GUARD_POST_DOORS[:])
	add_box(&parts, {3.6, 0.2, 3.6}, {0, 2.6, 0}, .Painted_Metal)
	add_box(&parts, {1.4, 0.8, 0.1}, {0.5, 1.7, 1.55}, .Glass, false, {}, {0.9, 0.65, 0.3})
	add_box(&parts, {1.2, 0.05, 0.5}, {0.2, 0.85, -1.0}, .Wood)
	add_lamp_panel(&parts, {0, 2.45, 0})
	return parts
}

@(private = "package")
bunker :: proc() -> (parts: Parts) {
	add_box(&parts, {6, 0.1, 6}, {0, 0.05, 0}, .Concrete)
	add_walled_room(&parts, {6, 2.6, 6}, 0, 0.5, .Concrete, BUNKER_DOORS[:])
	add_box(&parts, {6.6, 0.5, 6.6}, {0, 2.85, 0}, .Concrete)
	add_box(&parts, {2, 0.4, 0.3}, {-0.8, 1.6, 3.05}, .Rubber, false)
	for index in 0 ..< 10 {
		x := (f32(index) - 4.5) * 0.55
		add_part(&parts, Procedural.Part{primitive = Procedural.Box({0.5, 0.2, 0.32}), position = {x, 3.2, 3.1}, deformers = {0 = Procedural.Bulge{0.15}}, material = layer(.Canvas)})
	}
	for index in 0 ..< 3 do add_box(&parts, {0.9, 0.7, 0.9}, {-1.6 + f32(index) * 1.1, 0.45, -1.9}, .Wood)
	add_lamp_panel(&parts, {0, 2.5, 0})
	return parts
}

@(private = "package")
helipad :: proc() -> (parts: Parts) {
	add_part(&parts, Procedural.Part{primitive = Procedural.Cylinder(9, 0.2, 48), position = {0, 0.1, 0}, material = layer(.Concrete), solid = true})
	add_box(&parts, {0.6, 0.03, 5}, {-1.4, 0.215, 0}, .Sand, false)
	add_box(&parts, {0.6, 0.03, 5}, {1.4, 0.215, 0}, .Sand, false)
	add_box(&parts, {2.2, 0.03, 0.6}, {0, 0.215, 0}, .Sand, false)
	for index in 0 ..< 16 {
		angle := f32(index) / 16 * 2 * math.PI
		add_part(&parts, Procedural.Part{primitive = Procedural.Sphere(0.14, 8, 4), position = {8.6 * math.cos(angle), 0.3, 8.6 * math.sin(angle)}, material = layer(.Glass), emission = {1, 0.85, 0.4}})
	}
	return parts
}

GUY_ANCHOR_RADIUS_METERS :: 3.5

@(private = "package")
radio_mast :: proc() -> (parts: Parts) {
	add_part(&parts, Procedural.Part{primitive = Procedural.Cylinder(0.25, 24, 12, 8), position = {0, 12, 0}, deformers = {0 = Procedural.Taper{1, 0.5}}, material = layer(.Rusted_Metal), solid = true})
	add_cylinder(&parts, 0.04, 3, {0, 25.5, 0}, .Rusted_Metal, false, 6)
	for height in ([3]f32{14, 18, 22}) do add_box(&parts, {2.4 - (height - 14) * 0.1, 0.06, 0.06}, {0, height, 0}, .Rusted_Metal, false)
	for index in 0 ..< 3 {
		azimuth := f32(index) * 120 + 20
		anchor := [2]f32{math.sin(math.to_radians(azimuth)), math.cos(math.to_radians(azimuth))} * GUY_ANCHOR_RADIUS_METERS
		attach_height: f32 = 16
		length := math.sqrt(GUY_ANCHOR_RADIUS_METERS * GUY_ANCHOR_RADIUS_METERS + attach_height * attach_height)
		add_part(&parts, Procedural.Part{
			primitive = Procedural.Cylinder(0.015, length, 6),
			position = {anchor.x / 2, attach_height / 2, anchor.y / 2},
			rotation_degrees = {math.to_degrees(math.atan(f32(GUY_ANCHOR_RADIUS_METERS) / attach_height)), azimuth, 0},
			material = layer(.Rusted_Metal),
		})
	}
	add_box(&parts, {0.8, 0.5, 0.8}, {0, 0.25, 0}, .Concrete, false)
	return parts
}

@(private = "package")
radar_station :: proc() -> (parts: Parts) {
	add_box(&parts, {2.4, 2.4, 3}, {0, 1.2, 0.2}, .Concrete)
	add_cylinder(&parts, 0.3, 0.9, {0, 2.85, 0}, .Painted_Metal, true, 12)
	add_part(&parts, Procedural.Part{primitive = Procedural.Sphere(2.4, 28, 14), position = {0, 4.1, 0.3}, rotation_degrees = {-55, 0, 0}, stretch = {1, 0.14, 1}, material = layer(.Painted_Metal), solid = true})
	add_part(&parts, Procedural.Part{primitive = Procedural.Cylinder(0.05, 1.6, 8), position = {0, 4.9, 1.0}, rotation_degrees = {-55, 0, 0}, material = layer(.Rusted_Metal)})
	add_box(&parts, {1.4, 1.2, 0.08}, {0, 1.0, 1.24}, .Rusted_Metal, false)
	return parts
}
