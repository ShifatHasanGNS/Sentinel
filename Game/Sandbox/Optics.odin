package Sandbox

import "../../Engine/Platform"
import "../../Engine/Render"
import World "../../Engine/World"
import "../Base"
import "../Catalogue"
import "../Gameplay"
import "../Mission"
import "../Weapons"
import "../Vehicles"
import "core:fmt"
import "core:math"
import la "core:math/linalg"

BINOCULAR_ZOOM_START :: 2.5 // Times the normal view: a gentle first look.
BINOCULAR_ZOOM_MIN :: 1.5
BINOCULAR_ZOOM_MAX :: 10.0
BINOCULAR_ZOOM_RATE :: 1.2 // Natural-log units per second while Z or X is held: x3.3 each second.
BINOCULAR_RAISE_PER_SECOND :: 5.0 // The lenses come up in a fifth of a second.
BINOCULAR_RANGE_METERS :: 1500.0
MAP_RADIUS_METERS :: 100.0 // Half the width of the world shown on the map.
MAP_MIN_OBJECT_SIZE_METERS :: 2.0 // Smaller objects (crates, barrels) are left off the map.
MAP_RING_SEGMENTS :: 64
MAP_DOT_METERS :: 2.6

// B raises and lowers the binoculars (smoothly), Z and X zoom in and out while held, M shows the map; the first two only on foot.
// Zoom is multiplicative, so the same hold changes it by the same proportion at any level (an exponential approach feels even).
update_optics_keys :: proc(play: ^Play, input: ^Platform.Input, delta_seconds: f32) {
	binoculars_down := Platform.Input_Key_Down(input, .B)
	if binoculars_down && !play.binoculars_was_down && play.driving == nil do play.binoculars = !play.binoculars
	play.binoculars_was_down = binoculars_down
	map_down := Platform.Input_Key_Down(input, .M)
	if map_down && !play.map_was_down do play.map_open = !play.map_open
	play.map_was_down = map_down
	if play.driving != nil do play.binoculars = false
	if play.binoculars {
		change := f32(int(Platform.Input_Key_Down(input, .Z))) - f32(int(Platform.Input_Key_Down(input, .X)))
		play.binocular_zoom = clamp(play.binocular_zoom * math.exp(change * BINOCULAR_ZOOM_RATE * delta_seconds), BINOCULAR_ZOOM_MIN, BINOCULAR_ZOOM_MAX)
	}
	target: f32 = 1 if play.binoculars else 0
	play.binocular_raise += clamp(target - play.binocular_raise, -BINOCULAR_RAISE_PER_SECOND * delta_seconds, BINOCULAR_RAISE_PER_SECOND * delta_seconds)
}

// Zoom of a weapon when aimed down its sights (hold the right mouse button): the sniper rifle has a 4x scope, the rifle a red-dot at
// 1.5x, pistols barely zoom. Heavy launchers do not zoom.
aim_zoom_for :: proc(kind: Weapons.Weapon_Kind) -> f32 {
	#partial switch kind {
	case .Sniper_Rifle: return 4.0
	case .Rifle: return 1.5
	case .Pistol, .Silenced_Pistol: return 1.25
	}
	return 1.0
}

AIM_RAISE_PER_SECOND :: 7.0

// Called each frame on foot: right mouse aims down the sights (smoothly), the binoculars override it.
update_aim :: proc(play: ^Play, input: ^Platform.Input, delta_seconds: f32) {
	wants := (Platform.Input_Mouse_Down(input, .Right) || play.aim_held) && play.driving == nil && !play.binoculars && !Gameplay.Health_Is_Dead(play.battle.player.health)
	target: f32 = 1 if wants else 0
	play.aim += clamp(target - play.aim, -AIM_RAISE_PER_SECOND * delta_seconds, AIM_RAISE_PER_SECOND * delta_seconds)
}

// A scoped sniper rifle blacks out the screen around a circular view with crosshair lines.
scope_draw_hud :: proc(play: ^Play, width, height, scale: f32) {
	if play.aim < 0.75 || play.battle.player.current != .Sniper_Rifle || play.driving != nil do return
	hud := &play.hud
	radius := min(width, height) * 0.42
	draw_binocular_mask(hud, width, height, radius)
	line := [4]f32{0, 0, 0, 0.9}
	Render.Hud_Rect(hud, width / 2 - 1, height / 2 - radius, 2, 2 * radius, line)
	Render.Hud_Rect(hud, width / 2 - radius, height / 2 - 1, 2 * radius, 2, line)
	Render.Hud_Rect(hud, width / 2 - 3, height / 2 - 3, 6, 6, {1, 0.2, 0.2, 0.9})
}

// How magnified the view is now: 1 normally, the chosen zoom with the binoculars up, blended in log space while they move.
binocular_current_zoom :: proc(play: ^Play) -> f32 {
	aim_zoom := math.pow(aim_zoom_for(play.battle.player.current), play.aim)
	return math.pow(play.binocular_zoom, play.binocular_raise) * aim_zoom
}

// The mouse turns the view more slowly the more it is zoomed, so a binocular view is not twitchy.
binocular_look_scale :: proc(play: ^Play) -> f32 {
	return 1 / binocular_current_zoom(play)
}

// Range readout and mask: the world is darkened outside a circle-ish window, with tick marks and the distance to what is centred.
binoculars_draw_hud :: proc(play: ^Play, width, height, scale: f32) {
	if play.binocular_raise < 0.02 do return
	hud := &play.hud
	player := play.battle.player
	eye := Gameplay.Player_Eye(player)
	direction := Gameplay.Player_Forward(player)
	hit := World.Raycast_World(play.battle.collision, play.battle.ground, eye, direction, BINOCULAR_RANGE_METERS)
	enemy_distance := nearest_enemy_in_line(play, eye, direction)
	distance := hit.distance if hit.hit else math.INF_F32
	if enemy_distance < distance do distance = enemy_distance
	range_text := fmt.tprintf("RANGE %d M   ZOOM %.1fX   Z/X", int(distance), binocular_current_zoom(play)) if distance < BINOCULAR_RANGE_METERS else fmt.tprintf("RANGE ---   ZOOM %.1fX   Z/X", binocular_current_zoom(play))
	radius := min(width, height) * (0.46 + 0.9 * (1 - play.binocular_raise)) // The mask opens out as the binoculars come down.
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
	Render.Hud_Text(hud, center.x - half, center.y + half + 3 * scale, "ARROW YOU   RED SOLDIER   AMBER CAMERA   BLUE VEHICLE   GLOWING YELLOW NEXT GOAL", scale * 0.9, {0.8, 1, 0.8, 0.9})
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

// Where each objective is on the ground: the gate for "get inside", then the thing itself.
mission_objective_position :: proc(play: ^Play, objective: Mission.Objective) -> [3]f32 {
	mission := &play.mission
	switch objective {
	case .Enter_Compound: return {0, mission.extraction.y, Base.PERIMETER_RADIUS_METERS - 4}
	case .Hack_Cameras: return mission.terminal_position
	case .Destroy_Radar: return mission.radar_dish
	case .Rescue_Hostage: return mission.hostage.controller.position
	case .Destroy_Fuel:
		if len(mission.fuel_targets) == 0 do return {}
		return play.battle.targets[mission.fuel_targets[0]].position
	case .Reach_Extraction: return mission.extraction
	}
	return {}
}

@(private = "file")
OBJECTIVE_LABELS := [Mission.Objective]string{
	.Enter_Compound = "1 GATE",
	.Hack_Cameras = "2 COMPUTER",
	.Destroy_Radar = "3 RADAR",
	.Rescue_Hostage = "4 HOSTAGE",
	.Destroy_Fuel = "4 FUEL",
	.Reach_Extraction = "5 EXTRACT",
}

// Soldiers (red), cameras (amber, grey when broken), vehicles, and the five objectives: numbered like the list, the current one
// pulsing with a ring, a line from the player and its distance; finished ones grey with a check; later ones dim.
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
	for vehicle in play.vehicles {
		position, _, _, _ := vehicle_position(vehicle)
		dot(hud, center, factor, position, 1.1, {0.4, 0.6, 1, 1})
	}
	draw_objective_markers(play, center, factor, scale)
	for index in play.mission.fuel_targets {
		target := play.battle.targets[index]
		if !target.destroyed do dot(hud, center, factor, target.position, 1.3, {1, 0.5, 0.1, 1})
	}
}

@(private = "file")
draw_objective_markers :: proc(play: ^Play, center: [2]f32, factor, scale: f32) {
	hud := &play.hud
	mission := &play.mission.state
	current, any := Mission.Mission_Current_Objective(mission^)
	player := play.battle.player.controller.position
	pulse := 0.5 + 0.5 * math.sin(play.clock_seconds * 5)
	for objective in Mission.Objective {
		if objective not_in mission.required do continue
		position := mission_objective_position(play, objective)
		at := center + {position.x, position.z} * factor
		done := mission.done[objective]
		is_current := any && objective == current
		color := [4]f32{0.55, 0.55, 0.55, 0.9} if done else ([4]f32{1, 0.9, 0.2, 1} if is_current else [4]f32{0.9, 0.9, 0.9, 0.55})
		size := MAP_DOT_METERS * factor * (1.7 if is_current else 1.2)
		if is_current {
			draw_map_ring(hud, at, size * (1.2 + pulse), {1, 0.9, 0.2, 0.5 + 0.5 * pulse}, scale)
			player_at := center + {player.x, player.z} * factor
			draw_dashed_line(hud, player_at, at, {1, 0.9, 0.2, 0.7}, scale)
		}
		Render.Hud_Rect(hud, at.x - size / 2, at.y - size / 2, size, size, color)
		label := OBJECTIVE_LABELS[objective]
		if done do label = fmt.tprintf("%s OK", label)
		Render.Hud_Text(hud, at.x + size, at.y - 4 * scale, label, scale, color)
		if is_current {
			meters := int(la.length([2]f32{position.x - player.x, position.z - player.z}))
			Render.Hud_Text(hud, at.x + size, at.y + 5 * scale, fmt.tprintf("%d M", meters), scale, color)
		}
	}
}

// A line of small squares between two screen points, so it reads as a route without needing line primitives.
@(private = "file")
draw_dashed_line :: proc(hud: ^Render.Hud, from, to: [2]f32, color: [4]f32, scale: f32) {
	span := to - from
	length := la.length(span)
	if length < 1 do return
	step := 8 * scale
	for distance := f32(0); distance < length; distance += step {
		at := from + span / length * distance
		Render.Hud_Rect(hud, at.x - scale * 0.5, at.y - scale * 0.5, scale, scale, color)
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

