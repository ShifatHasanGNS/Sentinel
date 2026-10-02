package Sandbox

import "../../Engine/Platform"
import "../../Engine/Render"
import World "../../Engine/World"
import "../Base"
import "../Catalogue"
import "../Gameplay"
import "../Vehicles"
import "core:fmt"
import "core:math"

BINOCULAR_FIELD_OF_VIEW_DEGREES :: 12.0
BINOCULAR_RANGE_METERS :: 1500.0
MAP_RADIUS_METERS :: 100.0 // Half the width of the world shown on the map.
MAP_MIN_OBJECT_SIZE_METERS :: 2.0 // Smaller objects (crates, barrels) are left off the map.
MAP_RING_SEGMENTS :: 64
MAP_DOT_METERS :: 2.6

// B raises and lowers the binoculars, M the map; both only on foot.
update_optics_keys :: proc(play: ^Play, input: ^Platform.Input) {
	binoculars_down := Platform.Input_Key_Down(input, .B)
	if binoculars_down && !play.binoculars_was_down && play.driving == nil do play.binoculars = !play.binoculars
	play.binoculars_was_down = binoculars_down
	map_down := Platform.Input_Key_Down(input, .M)
	if map_down && !play.map_was_down do play.map_open = !play.map_open
	play.map_was_down = map_down
	if play.driving != nil do play.binoculars = false
}

// The mouse turns the view more slowly the more it is zoomed, so a binocular view is not twitchy.
binocular_look_scale :: proc(play: ^Play) -> f32 {
	return BINOCULAR_FIELD_OF_VIEW_DEGREES / PLAY_FIELD_OF_VIEW_DEGREES if play.binoculars else 1
}

// Range readout and mask: the world is darkened outside a circle-ish window, with tick marks and the distance to what is centred.
binoculars_draw_hud :: proc(play: ^Play, width, height, scale: f32) {
	if !play.binoculars do return
	hud := &play.hud
	player := play.battle.player
	eye := Gameplay.Player_Eye(player)
	direction := Gameplay.Player_Forward(player)
	hit := World.Raycast_World(play.battle.collision, play.battle.ground, eye, direction, BINOCULAR_RANGE_METERS)
	enemy_distance := nearest_enemy_in_line(play, eye, direction)
	distance := hit.distance if hit.hit else math.INF_F32
	if enemy_distance < distance do distance = enemy_distance
	range_text := fmt.tprintf("RANGE %d M", int(distance)) if distance < BINOCULAR_RANGE_METERS else "RANGE ---"
	radius := min(width, height) * 0.46
	draw_binocular_mask(hud, width, height, radius)
	Render.Hud_Text(hud, (width - Render.Hud_Text_Width(range_text, scale * 1.4)) / 2, height / 2 + radius + 4 * scale, range_text, scale * 1.4, {0.7, 1, 0.7, 0.95})
	tick := 6 * scale
	Render.Hud_Rect(hud, width / 2 - 1, height / 2 - tick * 3, 2, tick * 2, {0.7, 1, 0.7, 0.9})
	Render.Hud_Rect(hud, width / 2 - 1, height / 2 + tick, 2, tick * 2, {0.7, 1, 0.7, 0.9})
	Render.Hud_Rect(hud, width / 2 - tick * 3, height / 2 - 1, tick * 2, 2, {0.7, 1, 0.7, 0.9})
	Render.Hud_Rect(hud, width / 2 + tick, height / 2 - 1, tick * 2, 2, {0.7, 1, 0.7, 0.9})
}

// Distance to the first living enemy whose body the sight line crosses (so binoculars can range a soldier too).
@(private = "file")
nearest_enemy_in_line :: proc(play: ^Play, origin, direction: [3]f32) -> f32 {
	nearest := math.INF_F32
	for enemy in play.battle.enemies {
		if !Gameplay.Enemy_Is_Alive(enemy) do continue
		if distance, _, hit := Gameplay.Enemy_Raycast(enemy, origin, direction); hit && distance < nearest do nearest = distance
	}
	return nearest
}

// Black everywhere but a disc of `radius` about the centre: a polygon ring of quads from the disc's edge out to beyond the screen.
@(private = "file")
draw_binocular_mask :: proc(hud: ^Render.Hud, width, height, radius: f32) {
	center := [2]f32{width / 2, height / 2}
	outer := max(width, height)
	segments := 48
	for index in 0 ..< segments {
		a0 := f32(index) / f32(segments) * 2 * math.PI
		a1 := f32(index + 1) / f32(segments) * 2 * math.PI
		d0 := [2]f32{math.cos(a0), math.sin(a0)}
		d1 := [2]f32{math.cos(a1), math.sin(a1)}
		Render.Hud_Quad(hud, {center + d0 * radius, center + d1 * radius, center + d1 * outer, center + d0 * outer}, {0, 0, 0, 1})
	}
}

// ---- The map computer ----

map_draw_hud :: proc(sandbox: ^Sandbox, width, height, scale: f32) {
	play := &sandbox.play
	if !play.map_open do return
	hud := &play.hud
	half := min(width, height) * 0.45
	center := [2]f32{width / 2, height / 2}
	meters_to_pixels := half / MAP_RADIUS_METERS
	to_screen :: proc(center: [2]f32, factor: f32, x, z: f32) -> [2]f32 {
		return center + {x, z} * factor
	}
	Render.Hud_Rect(hud, 0, 0, width, height, {0, 0.03, 0.02, 0.82})
	Render.Hud_Rect(hud, center.x - half, center.y - half, 2 * half, 2 * half, {0.08, 0.2, 0.12, 0.9})
	draw_map_ring(hud, center, Base.PERIMETER_RADIUS_METERS * meters_to_pixels, {0.8, 0.8, 0.8, 0.9}, scale)
	for placement in sandbox.base.layout.placements {
		info := Catalogue.Catalogue_Info(placement.kind)
		if max(info.highest.x - info.lowest.x, info.highest.z - info.lowest.z) < MAP_MIN_OBJECT_SIZE_METERS || placement.kind == .Fence_Section do continue
		corners := Base.Footprint_Corners(placement)
		// corners_of orders them by bit pattern (0: -x -z, 1: +x -z, 2: -x +z, 3: +x +z); around the rectangle that is 0, 1, 3, 2.
		order := [4]int{0, 1, 3, 2}
		quad: [4][2]f32
		for index in 0 ..< 4 do quad[index] = to_screen(center, meters_to_pixels, corners[order[index]].x, corners[order[index]].y)
		Render.Hud_Quad(hud, quad, map_color(placement.kind))
	}
	draw_map_markers(play, center, meters_to_pixels, scale)
	player := play.battle.player
	draw_map_arrow(hud, to_screen(center, meters_to_pixels, player.controller.position.x, player.controller.position.z), {-math.sin(player.yaw_radians), -math.cos(player.yaw_radians)}, 4.5 * scale, {1, 1, 0.3, 1})
	Render.Hud_Text(hud, center.x - half, center.y - half - 10 * scale, "TACTICAL MAP    M CLOSE    N IS UP", scale, {0.8, 1, 0.8, 0.95})
}

@(private = "file")
map_color :: proc(kind: Catalogue.Object_Kind) -> [4]f32 {
	#partial switch kind {
	case .Barracks, .Headquarters, .Mess_Hall, .Generator_Shed, .Guard_Post, .Bunker, .Hangar: return {0.55, 0.55, 0.6, 0.95}
	case .Radar_Station: return {0.9, 0.3, 0.25, 0.95}
	case .Jeep, .Cargo_Truck, .Armored_Carrier, .Battle_Tank: return {0.3, 0.5, 0.9, 0.9}
	case .Helicopter, .Helipad: return {0.4, 0.7, 0.95, 0.9}
	}
	return {0.35, 0.4, 0.35, 0.9}
}

@(private = "file")
draw_map_ring :: proc(hud: ^Render.Hud, center: [2]f32, radius: f32, color: [4]f32, scale: f32) {
	thickness := max(scale * 0.5, 1)
	for index in 0 ..< MAP_RING_SEGMENTS {
		a0 := f32(index) / MAP_RING_SEGMENTS * 2 * math.PI
		a1 := f32(index + 1) / MAP_RING_SEGMENTS * 2 * math.PI
		d0 := [2]f32{math.cos(a0), math.sin(a0)}
		d1 := [2]f32{math.cos(a1), math.sin(a1)}
		Render.Hud_Quad(hud, {center + d0 * radius, center + d1 * radius, center + d1 * (radius + thickness), center + d0 * (radius + thickness)}, color)
	}
}

// Soldiers (red), cameras (amber, grey when broken), the objectives, and vehicles.
@(private = "file")
draw_map_markers :: proc(play: ^Play, center: [2]f32, factor, scale: f32) {
	hud := &play.hud
	dot :: proc(hud: ^Render.Hud, center: [2]f32, factor: f32, position: [3]f32, size_scale: f32, color: [4]f32) {
		size := MAP_DOT_METERS * factor * size_scale
		at := center + {position.x, position.z} * factor
		Render.Hud_Rect(hud, at.x - size / 2, at.y - size / 2, size, size, color)
	}
	for enemy in play.battle.enemies {
		if Gameplay.Enemy_Is_Alive(enemy) do dot(hud, center, factor, enemy.controller.position, 1, {1, 0.2, 0.2, 1})
	}
	for instance in play.cameras {
		dot(hud, center, factor, instance.camera.position, 0.9, {0.5, 0.5, 0.5, 0.9} if instance.camera.disabled else {1, 0.75, 0.1, 1})
	}
	mission := &play.mission
	if !mission.state.done[.Hack_Cameras] do dot(hud, center, factor, mission.terminal_position, 1.3, {0.3, 1, 1, 1})
	if !play.battle.targets[mission.radar_target].destroyed do dot(hud, center, factor, mission.radar_dish, 1.6, {1, 0.4, 0.1, 1})
	if !mission.hostage.rescued do dot(hud, center, factor, mission.hostage.controller.position, 1.4, {1, 1, 0.4, 1})
	dot(hud, center, factor, mission.extraction, 2.2, {0.3, 1, 0.4, 1})
	for vehicle in play.vehicles {
		position, _, _, _ := vehicle_position(vehicle)
		dot(hud, center, factor, position, 1.1, {0.4, 0.6, 1, 1})
	}
}

@(private = "file")
vehicle_position :: proc(vehicle: Vehicles.Vehicle) -> (position: [3]f32, yaw, pitch, roll: f32) {
	return Vehicles.Vehicle_Pose(vehicle)
}

@(private = "file")
draw_map_arrow :: proc(hud: ^Render.Hud, at, direction: [2]f32, size: f32, color: [4]f32) {
	side := [2]f32{-direction.y, direction.x}
	tip := at + direction * size * 1.6
	left := at - direction * size + side * size * 0.8
	right := at - direction * size - side * size * 0.8
	Render.Hud_Quad(hud, {tip, right, at - direction * size * 0.4, left}, color)
}

