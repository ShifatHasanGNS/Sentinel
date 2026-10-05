package Base

import "../../Engine/Render"
import "../Catalogue"
import "core:math"

FLOODLIGHT_INTENSITY :: 520.0
FLOODLIGHT_RANGE_METERS :: 26.0
LAMP_INTENSITY :: 90.0
LAMP_RANGE_METERS :: 14.0
DOORLIGHT_INTENSITY :: 45.0
DOORLIGHT_RANGE_METERS :: 12.0
FLOODLIGHT_COLOR :: [3]f32{1.0, 0.92, 0.75}
WARM_COLOR :: [3]f32{1.0, 0.72, 0.4}

// Where a placement's electric lights sit, in the object's local frame (+Z is the front).
Lamp :: struct {
	local_position: [3]f32,
	axis:           [3]f32, // Zero for an omnidirectional lamp.
}

@(rodata)
FLOODLIGHT_LAMPS := [1]Lamp{{{0.6, 4.4, 0}, {0.2, -1, 0.5}}}
@(rodata)
WATCHTOWER_LAMPS := [1]Lamp{{{0, 5.7, 1.3}, {}}}
@(rodata)
GUARD_POST_LAMPS := [1]Lamp{{{0, 2.7, 2.2}, {}}}
@(rodata)
DOOR_LAMPS := [1]Lamp{{{0, 2.7, 6}, {}}}

lamps_for :: proc(kind: Catalogue.Object_Kind) -> []Lamp {
	#partial switch kind {
	case .Floodlight: return FLOODLIGHT_LAMPS[:]
	case .Watchtower: return WATCHTOWER_LAMPS[:]
	case .Guard_Post: return GUARD_POST_LAMPS[:]
	case .Headquarters, .Barracks, .Mess_Hall: return DOOR_LAMPS[:]
	}
	return nil
}

// The base's lights for the current darkness (0 = day, 1 = night). Rotating a local point by the placement's yaw about +Y
// gives world x = x + lx*cos + lz*sin, z = z - lx*sin + lz*cos.
Layout_Night_Lights :: proc(layout: Layout, ground_height_meters, darkness: f32, allocator := context.temp_allocator) -> (lights: [dynamic]Render.Light) {
	lights = make([dynamic]Render.Light, allocator)
	if darkness <= 0 do return
	for placement in layout.placements {
		yaw := math.to_radians(placement.yaw_degrees)
		sine, cosine := math.sin(yaw), math.cos(yaw)
		for lamp in lamps_for(placement.kind) {
			position := [3]f32{
				placement.x + lamp.local_position.x * cosine + lamp.local_position.z * sine,
				ground_height_meters + lamp.local_position.y,
				placement.z - lamp.local_position.x * sine + lamp.local_position.z * cosine,
			}
			append(&lights, build_light(placement.kind, lamp, position, sine, cosine, darkness))
		}
	}
	return
}

@(private = "file")
build_light :: proc(kind: Catalogue.Object_Kind, lamp: Lamp, position: [3]f32, sine, cosine, darkness: f32) -> Render.Light {
	if lamp.axis == {} {
		intensity, range := f32(DOORLIGHT_INTENSITY), f32(DOORLIGHT_RANGE_METERS)
		if kind == .Watchtower || kind == .Guard_Post do intensity, range = LAMP_INTENSITY, LAMP_RANGE_METERS
		return Render.Light_Point(position, WARM_COLOR, intensity * darkness, range)
	}
	axis := [3]f32{lamp.axis.x * cosine + lamp.axis.z * sine, lamp.axis.y, -lamp.axis.x * sine + lamp.axis.z * cosine}
	light := Render.Light_Spot(position, axis, FLOODLIGHT_COLOR, FLOODLIGHT_INTENSITY * darkness, FLOODLIGHT_RANGE_METERS, 22, 42)
	light.casts_shadow = true
	return light
}
