package Sandbox

import "../../Engine/Render"
import "../Mission"
import "core:fmt"
import "core:math"

COMPASS_HALF_SPAN_DEGREES :: 70.0
COMPASS_TICK_DEGREES :: 10

// The signed angle in degrees from the direction the player faces to a point, positive to the right, in (-180, 180].
// North is -Z (the map's up); the player's yaw turns left when positive, so the heading clockwise from north is -yaw.
bearing_relative_degrees :: proc(player_position: [3]f32, player_yaw: f32, target: [3]f32) -> f32 {
	offset := target - player_position
	bearing := math.atan2(offset.x, -offset.z) // Clockwise from north.
	relative := math.to_degrees(bearing + player_yaw) // bearing - heading, with heading = -yaw
	wrapped := math.mod(relative + 180, 360)
	if wrapped < 0 do wrapped += 360
	return wrapped - 180
}

// Heading in degrees clockwise from north, in [0, 360).
heading_degrees :: proc(player_yaw: f32) -> f32 {
	degrees := math.mod(math.to_degrees(-player_yaw), 360)
	if degrees < 0 do degrees += 360
	return degrees
}

// A strip along the top: tick marks every 10 degrees, N E S W at the cardinal directions, the heading in the middle, and a marker
// for the current objective at its bearing (clamped to the edge when it is off to the side).
compass_draw_hud :: proc(play: ^Play, width, scale: f32) {
	if play.mission.state.status != .Active || play.map_open || play.binoculars || play.paused do return
	hud := &play.hud
	player := play.battle.player
	strip_width := min(width * 0.4, 520 * scale / 2)
	left := (width - strip_width) / 2
	top := 16 + 24 * scale
	pixels_per_degree := strip_width / (2 * COMPASS_HALF_SPAN_DEGREES)
	Render.Hud_Rect(hud, left, top, strip_width, 2 * scale, {1, 1, 1, 0.35})
	heading := heading_degrees(player.yaw_radians)
	first := int(math.floor((heading - COMPASS_HALF_SPAN_DEGREES) / COMPASS_TICK_DEGREES))
	last := int(math.ceil((heading + COMPASS_HALF_SPAN_DEGREES) / COMPASS_TICK_DEGREES))
	for tick in first ..= last {
		degrees := f32(tick * COMPASS_TICK_DEGREES)
		x := left + strip_width / 2 + (degrees - heading) * pixels_per_degree
		if x < left || x > left + strip_width do continue
		normalized := int(math.mod(degrees + 720, 360))
		cardinal := normalized % 90 == 0
		height := (7 if cardinal else 4) * scale
		Render.Hud_Rect(hud, x - scale * 0.5, top - height, scale, height, {1, 1, 1, 0.85 if cardinal else 0.5})
		if cardinal {
			label := "N" if normalized == 0 else ("E" if normalized == 90 else ("S" if normalized == 180 else "W"))
			Render.Hud_Text(hud, x - Render.Hud_Text_Width(label, scale) / 2, top - 20 * scale, label, scale, {1, 0.9, 0.4, 0.95})
		}
	}
	Render.Hud_Quad(hud, {{left + strip_width / 2, top + 4 * scale}, {left + strip_width / 2 - 3 * scale, top + 10 * scale}, {left + strip_width / 2 + 3 * scale, top + 10 * scale}, {left + strip_width / 2, top + 4 * scale}}, {1, 1, 1, 0.9})
	Render.Hud_Text(hud, left + strip_width / 2 - Render.Hud_Text_Width(fmt.tprintf("%d", int(heading)), scale) / 2, top + 12 * scale, fmt.tprintf("%d", int(heading)), scale, {1, 1, 1, 0.8})
	if objective, any := Mission.Mission_Current_Objective(play.mission.state); any {
		target := mission_objective_position(play, objective)
		relative := clamp(bearing_relative_degrees(player.controller.position, player.yaw_radians, target), -COMPASS_HALF_SPAN_DEGREES, COMPASS_HALF_SPAN_DEGREES)
		x := left + strip_width / 2 + relative * pixels_per_degree
		size := 4 * scale
		Render.Hud_Quad(hud, {{x, top - 2 * size}, {x + size, top - size}, {x, top}, {x - size, top - size}}, {1, 0.9, 0.2, 1})
	}
}
