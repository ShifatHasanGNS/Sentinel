package Base

import "../Catalogue"
import "../../Engine/Procedural"
import World "../../Engine/World"
import "core:math"

// An object placed on the plateau. Positions are on the ground plane (x east, z south); yaw turns the object about +Y, so at
// yaw 90 its front (+Z) faces +X.
Placement :: struct {
	kind:        Catalogue.Object_Kind,
	x:           f32,
	z:           f32,
	yaw_degrees: f32,
}

// A placement's rectangle on the ground: where its bounds stand, rotated by its yaw.
Footprint :: struct {
	center:       [2]f32,
	half_extents: [2]f32,
	yaw_radians:  f32,
}

placement_footprint :: proc(placement: Placement) -> Footprint {
	info := Catalogue.Catalogue_Info(placement.kind)
	yaw := math.to_radians(placement.yaw_degrees)
	local_center := [2]f32{(info.lowest.x + info.highest.x) / 2, (info.lowest.z + info.highest.z) / 2}
	return Footprint{
		center = [2]f32{placement.x, placement.z} + rotate_ground(local_center, yaw),
		half_extents = {(info.highest.x - info.lowest.x) / 2, (info.highest.z - info.lowest.z) / 2},
		yaw_radians = yaw,
	}
}

// The yaw rotation seen from above: x' = x cos + z sin, z' = -x sin + z cos.
rotate_ground :: proc(point: [2]f32, yaw_radians: f32) -> [2]f32 {
	return {point.x * math.cos(yaw_radians) + point.y * math.sin(yaw_radians), -point.x * math.sin(yaw_radians) + point.y * math.cos(yaw_radians)}
}

Footprint_Corners :: proc(placement: Placement) -> [4][2]f32 {
	return corners_of(placement_footprint(placement), 0)
}

// Half the footprint's length along the object's own X axis (the way a fence section runs).
Footprint_Half_Length :: proc(placement: Placement) -> f32 {
	return placement_footprint(placement).half_extents.x
}

// Two oriented rectangles overlap unless some edge direction separates their projections (separating axis theorem for boxes:
// only the four edge normals need testing). `shrink` pulls each rectangle in so that neighbours which merely touch do not count.
Footprints_Overlap :: proc(a, b: Placement, shrink: f32) -> bool {
	corners_a, corners_b := corners_of(placement_footprint(a), shrink), corners_of(placement_footprint(b), shrink)
	for footprint in ([2]Footprint{placement_footprint(a), placement_footprint(b)}) {
		for axis_yaw in ([2]f32{0, math.PI / 2}) {
			axis := rotate_ground({1, 0}, footprint.yaw_radians + axis_yaw)
			a_low, a_high := project(corners_a, axis)
			b_low, b_high := project(corners_b, axis)
			if a_high < b_low || b_high < a_low do return false
		}
	}
	return true
}

// A camouflage net spreads over what is under it; a helicopter stands on its pad.
Placements_May_Overlap :: proc(a, b: Catalogue.Object_Kind) -> bool {
	covers :: proc(cover, covered: Catalogue.Object_Kind) -> bool {
		#partial switch cover {
		case .Camo_Net:
			#partial switch covered {
			case .Jeep, .Cargo_Truck, .Armored_Carrier, .Battle_Tank, .Tent, .Crate, .Pallet, .Barrel, .Ammo_Box: return true
			}
		case .Helipad: return covered == .Helicopter
		}
		return false
	}
	return covers(a, b) || covers(b, a)
}

// A placement's collision as solids turned with the object. Boxes are in the object's own frame (y = 0 is its ground point),
// so `ground_height_meters` lifts them onto the terrain.
Placement_Solids :: proc(placement: Placement, ground_height_meters: f32 = 0) -> (solids: [dynamic]World.Solid) {
	yaw := math.to_radians(placement.yaw_degrees)
	for box in Catalogue.Catalogue_Info(placement.kind).collision_boxes {
		append(&solids, World.Solid_From_Object_Box(box, {placement.x, ground_height_meters, placement.z}, yaw))
	}
	return solids
}

@(private = "file")
corners_of :: proc(footprint: Footprint, shrink: f32) -> (corners: [4][2]f32) {
	half := [2]f32{max(footprint.half_extents.x - shrink, 0), max(footprint.half_extents.y - shrink, 0)}
	for index in 0 ..< 4 {
		local := [2]f32{-half.x if index & 1 == 0 else half.x, -half.y if index & 2 == 0 else half.y}
		corners[index] = footprint.center + rotate_ground(local, footprint.yaw_radians)
	}
	return
}

@(private = "file")
project :: proc(corners: [4][2]f32, axis: [2]f32) -> (low, high: f32) {
	low, high = max(f32), min(f32)
	for corner in corners {
		distance := corner.x * axis.x + corner.y * axis.y
		low, high = min(low, distance), max(high, distance)
	}
	return
}

// Every placement's solids on the plateau.
Layout_Solids :: proc(layout: Layout, ground_height_meters: f32) -> (solids: [dynamic]World.Solid) {
	for placement in layout.placements {
		own := Placement_Solids(placement, ground_height_meters)
		defer delete(own)
		for solid in own do append(&solids, solid)
	}
	return solids
}
