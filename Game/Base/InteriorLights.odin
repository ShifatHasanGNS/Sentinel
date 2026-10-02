package Base

import "../../Engine/Render"
import "../Catalogue"
import World "../../Engine/World"
import "core:math"

INTERIOR_LIGHT_INTENSITY :: 0.9
INTERIOR_LIGHT_RANGE_METERS :: 8.0
INTERIOR_LIGHT_COLOR :: [3]f32{1.0, 0.82, 0.55}

// Ceiling lamps, in the object's frame (y from the ground); they match the glowing panels in Catalogue/Buildings.odin.
@(rodata)
BARRACKS_INTERIOR := [3][3]f32{{-6, 2.8, 0.4}, {0, 2.8, 0.4}, {6, 2.8, 0.4}}
@(rodata)
HEADQUARTERS_INTERIOR := [2][3]f32{{-3.5, 3.0, 0}, {3.5, 3.0, 0}}
@(rodata)
MESS_HALL_INTERIOR := [2][3]f32{{-4, 2.8, 0}, {4, 2.8, 0}}
@(rodata)
SMALL_INTERIOR := [1][3]f32{{0, 2.0, 0}}

interior_lamps_for :: proc(kind: Catalogue.Object_Kind) -> [][3]f32 {
	#partial switch kind {
	case .Barracks: return BARRACKS_INTERIOR[:]
	case .Headquarters: return HEADQUARTERS_INTERIOR[:]
	case .Mess_Hall: return MESS_HALL_INTERIOR[:]
	case .Generator_Shed, .Guard_Post, .Bunker: return SMALL_INTERIOR[:]
	}
	return nil
}

// Warm point lights inside every building with a room, always on.
Layout_Interior_Lights :: proc(layout: Layout, ground_height_meters: f32, allocator := context.temp_allocator) -> (lights: [dynamic]Render.Light) {
	lights = make([dynamic]Render.Light, allocator)
	for placement in layout.placements {
		yaw := math.to_radians(placement.yaw_degrees)
		for lamp in interior_lamps_for(placement.kind) {
			local := World.rotate_about_y(lamp, yaw)
			position := [3]f32{placement.x + local.x, ground_height_meters + local.y - 0.3, placement.z + local.z}
			append(&lights, Render.Light_Point(position, INTERIOR_LIGHT_COLOR, INTERIOR_LIGHT_INTENSITY, INTERIOR_LIGHT_RANGE_METERS))
		}
	}
	return lights
}

// The room inside each building, in the object's frame: {center, half extents} from the floor slab's top to the ceiling.
interior_box_for :: proc(kind: Catalogue.Object_Kind) -> (center, half: [3]f32, found: bool) {
	#partial switch kind {
	case .Barracks: return {0, 1.7, 0}, {8.7, 1.4, 2.7}, true
	case .Headquarters: return {0, 1.8, 0}, {6.7, 1.5, 4.7}, true
	case .Mess_Hall: return {0, 1.65, 0}, {6.7, 1.35, 3.7}, true
	case .Generator_Shed: return {0, 1.1, 0}, {1.58, 1.1, 1.38}, true
	case .Guard_Post: return {0, 1.35, 0}, {1.3, 1.25, 1.3}, true
	case .Bunker: return {0, 1.4, 0}, {2.5, 1.3, 2.5}, true
	}
	return {}, {}, false
}

// Every room in the layout, for the renderer to shut the sky out of.
Layout_Interiors :: proc(layout: Layout, ground_height_meters: f32, allocator := context.temp_allocator) -> (volumes: [dynamic]Render.Interior_Volume) {
	volumes = make([dynamic]Render.Interior_Volume, allocator)
	for placement in layout.placements {
		center, half, found := interior_box_for(placement.kind)
		if !found do continue
		yaw := math.to_radians(placement.yaw_degrees)
		turned := World.rotate_about_y(center, yaw)
		append(&volumes, Render.Interior_Volume{center = {placement.x + turned.x, ground_height_meters + turned.y, placement.z + turned.z}, half_extents = half, yaw_radians = yaw})
	}
	return volumes
}
