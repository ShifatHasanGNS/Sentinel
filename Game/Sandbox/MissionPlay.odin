package Sandbox

import "../../Engine/Platform"
import "../../Engine/Procedural"
import "../../Engine/Render"
import World "../../Engine/World"
import "../Base"
import "../Catalogue"
import "../Characters"
import "../Gameplay"
import "../Materials"
import "../Mission"
import "core:fmt"
import "core:math"
import la "core:math/linalg"

COMPOUND_RADIUS_METERS :: 58.0 // Inside the fence ring (62 m).
TERMINAL_REACH_METERS :: 2.4
HOSTAGE_REACH_METERS :: 2.6
RADAR_DISH_LOCAL :: [3]f32{0, 4.1, 0.3}
RADAR_DISH_RADIUS_METERS :: 2.6
RADAR_HEALTH :: 260.0
HOSTAGE_LOCAL :: [3]f32{0, 0.3, 1.2} // Inside the middle barracks, in the corridor between the bunks and the door wall.
EXTRACTION_POSITION_XZ :: [2]f32{-72, -52}
EXTRACTION_RADIUS_METERS :: 9.0
BEACON_HEIGHT_METERS :: 60.0
HOSTAGE_WALK_SPEED :: 3.4
HOSTAGE_FOLLOW_DISTANCE_METERS :: 3.2
HOSTAGE_WARP_DISTANCE_METERS :: 16.0
TOAST_SECONDS :: 3.5

Hostage :: struct {
	character:  Characters.Character,
	controller: World.Controller,
	rescued:    bool,
	hidden:     bool, // Riding along inside the player's vehicle.
}

// Where the mission's things are, and how the mission is going.
Mission_Play :: struct {
	state:             Mission.Mission,
	hostage:           Hostage,
	radar_target:      int,
	terminal_position: [3]f32,
	extraction:        [3]f32,
	radar_dish:        [3]f32,
	toast_text:        string,
	toast_buffer:      [128]u8, // toast_text points into this.
	toast_seconds:     f32,
	hostage_in_reach:  bool,
	terminal_in_reach: bool,
	beacon:            Render.Mesh,
}

mission_create :: proc(play: ^Play, sandbox: ^Sandbox, interactive: bool) {
	mission := &play.mission
	mission.state = Mission.Mission_Create()
	ground := sandbox.terrain.base_height_meters
	for placement in sandbox.base.layout.placements {
		yaw := math.to_radians(placement.yaw_degrees)
		origin := [3]f32{placement.x, ground, placement.z}
		#partial switch placement.kind {
		case .Radar_Station: mission.radar_dish = origin + World.rotate_about_y(RADAR_DISH_LOCAL, yaw)
		case .Headquarters: mission.terminal_position = origin + World.rotate_about_y(Catalogue.HEADQUARTERS_TERMINAL, yaw)
		}
	}
	barracks_origin, barracks_yaw := middle_barracks(sandbox)
	hostage_position := barracks_origin + World.rotate_about_y(HOSTAGE_LOCAL, barracks_yaw)
	mission.hostage.controller = World.Controller_Create(hostage_position)
	mission.hostage.character = Characters.Character{variant = .Officer, position = hostage_position, heading_radians = barracks_yaw + math.PI / 2, hide_weapon = true}
	mission.radar_target = Gameplay.Battle_Add_Target(&play.battle, mission.radar_dish, RADAR_DISH_RADIUS_METERS, RADAR_HEALTH)
	ground_height := terrain_height(sandbox.terrain, EXTRACTION_POSITION_XZ.x, EXTRACTION_POSITION_XZ.y)
	mission.extraction = {EXTRACTION_POSITION_XZ.x, ground_height, EXTRACTION_POSITION_XZ.y}
	column := Procedural.Box_Create({0.5, BEACON_HEIGHT_METERS, 0.5})
	defer Procedural.Mesh_Destroy(&column)
	mission.beacon = Render.Mesh_Upload(column)
	if !interactive do Mission.Mission_Start(&mission.state)
}

mission_destroy :: proc(mission: ^Mission_Play) {
	Render.Mesh_Destroy(&mission.beacon)
}

// The barracks in the middle of the row of three (by z): the hostage is held there.
@(private = "file")
middle_barracks :: proc(sandbox: ^Sandbox) -> (origin: [3]f32, yaw: f32) {
	zs := make([dynamic]f32, context.temp_allocator)
	for placement in sandbox.base.layout.placements do if placement.kind == .Barracks do append(&zs, placement.z)
	assert(len(zs) > 0, "mission_create: the layout has no barracks")
	for i in 1 ..< len(zs) {
		for j := i; j > 0 && zs[j] < zs[j - 1]; j -= 1 do zs[j], zs[j - 1] = zs[j - 1], zs[j]
	}
	median := zs[len(zs) / 2]
	for placement in sandbox.base.layout.placements {
		if placement.kind == .Barracks && placement.z == median {
			return {placement.x, sandbox.terrain.base_height_meters, placement.z}, math.to_radians(placement.yaw_degrees)
		}
	}
	return {}, 0
}

// One frame of the mission: what the player is near, the mission state machine, the hostage following, and the messages.
mission_update :: proc(sandbox: ^Sandbox, interact_down, interact_pressed: bool, delta_seconds: f32) {
	play := &sandbox.play
	mission := &play.mission
	player_position := play.battle.player.controller.position
	flat_distance :: proc(a, b: [3]f32) -> f32 {
		return la.length([2]f32{a.x - b.x, a.z - b.z})
	}
	base_center := [2]f32{0, 0}
	inside := la.length([2]f32{player_position.x, player_position.z} - base_center) < COMPOUND_RADIUS_METERS
	eye := Gameplay.Player_Eye(play.battle.player)
	seen :: proc(play: ^Play, eye, target: [3]f32) -> bool {
		return World.Line_Of_Sight_Clear(play.battle.collision, play.battle.ground, eye, target, 0.5)
	}
	terminal_point := mission.terminal_position + {0, 0.9, 0.6}
	hostage_point := mission.hostage.controller.position + {0, 1.1, 0}
	mission.terminal_in_reach = play.driving == nil && flat_distance(player_position, mission.terminal_position) < TERMINAL_REACH_METERS && abs(player_position.y - mission.terminal_position.y) < 2.5 && seen(play, eye, terminal_point)
	mission.hostage_in_reach = !mission.hostage.rescued && play.driving == nil && flat_distance(player_position, mission.hostage.controller.position) < HOSTAGE_REACH_METERS && seen(play, eye, hostage_point)
	observation := Mission.Observation{
		inside_compound = inside,
		terminal_in_reach = mission.terminal_in_reach && !mission.state.done[.Hack_Cameras],
		interact_held = interact_down,
		hostage_in_reach = mission.hostage_in_reach,
		interact_pressed = interact_pressed,
		radar_destroyed = play.battle.targets[mission.radar_target].destroyed,
		at_extraction = flat_distance(player_position, mission.extraction) < EXTRACTION_RADIUS_METERS && player_position.y - mission.extraction.y < 25,
	}
	Mission.Mission_Update(&mission.state, observation, delta_seconds)
	if .Rescue_Hostage in mission.state.just_completed do mission.hostage.rescued = true
	for objective in Mission.Objective {
		if objective in mission.state.just_completed {
			mission.toast_text = fmt.bprintf(mission.toast_buffer[:], "OBJECTIVE COMPLETE: %s", Mission.Objective_Text(objective))
			mission.toast_seconds = TOAST_SECONDS
		}
	}
	mission.toast_seconds = max(mission.toast_seconds - delta_seconds, 0)
	update_hostage(play, delta_seconds)
}

// A rescued hostage walks behind the player, keeps up by warping if left far behind, and rides hidden inside vehicles.
@(private = "file")
update_hostage :: proc(play: ^Play, delta_seconds: f32) {
	hostage := &play.mission.hostage
	player := play.battle.player
	hostage.hidden = hostage.rescued && play.driving != nil
	wish: [2]f32
	if hostage.rescued {
		offset := player.controller.position - hostage.controller.position
		distance := la.length([2]f32{offset.x, offset.z})
		if hostage.hidden || distance > HOSTAGE_WARP_DISTANCE_METERS {
			behind := -Gameplay.Player_Forward(player)
			hostage.controller.position = player.controller.position + {behind.x, 0, behind.z} * 1.8
		} else if distance > HOSTAGE_FOLLOW_DISTANCE_METERS {
			wish = [2]f32{offset.x, offset.z} / distance * HOSTAGE_WALK_SPEED
		}
	}
	World.Controller_Step(&hostage.controller, play.battle.collision, play.battle.ground, wish, false, delta_seconds)
	character := &hostage.character
	character.position = hostage.controller.position
	character.speed = la.length(wish)
	if la.length(wish) > 0.01 do character.heading_radians = math.atan2(wish.x, wish.y)
	Characters.Character_Step(character, delta_seconds)
}

mission_hostage_character :: proc(play: ^Play) -> Maybe(Characters.Character) {
	if play.mission.hostage.hidden do return nil
	return play.mission.hostage.character
}

// ---- HUD ----

mission_draw_hud :: proc(play: ^Play, width, height, scale: f32) {
	hud := &play.hud
	mission := &play.mission
	switch mission.state.status {
	case .Briefing: draw_briefing(hud, width, height, scale)
	case .Complete: draw_mission_complete(hud, mission, width, height, scale)
	case .Active: if !play.map_open do draw_objectives(play, width, height, scale)
	}
}

@(private = "file")
draw_objectives :: proc(play: ^Play, width, height, scale: f32) {
	hud := &play.hud
	mission := &play.mission
	y := 16 + 12 * scale
	Render.Hud_Text(hud, 16, y, "OBJECTIVES", scale, {1, 0.9, 0.4, 0.95})
	current, any := Mission.Mission_Current_Objective(mission.state)
	for objective in Mission.Objective {
		y += 10 * scale
		done := mission.state.done[objective]
		mark := "[X] " if done else "[ ] "
		color := [4]f32{0.6, 1, 0.6, 0.85} if done else {1, 1, 1, 0.9 if any && objective == current else 0.55}
		distance_text := ""
		if !done {
			target := mission_objective_position(play, objective)
			player := play.battle.player.controller.position
			distance_text = fmt.tprintf("  (%d M)", int(la.length([2]f32{target.x - player.x, target.z - player.z})))
		}
		Render.Hud_Text(hud, 16, y, fmt.tprintf("%s%s%s", mark, Mission.Objective_Text(objective), distance_text), scale, color)
	}
	if mission.terminal_in_reach && !mission.state.done[.Hack_Cameras] {
		Render.Hud_Text(hud, (width - Render.Hud_Text_Width("HOLD E  HACK COMPUTER", scale)) / 2, height * 0.66, "HOLD E  HACK COMPUTER", scale, {0.5, 1, 0.7, 0.95})
		bar_width := 40 * scale
		fraction := mission.state.hack_seconds / Mission.HACK_SECONDS
		Render.Hud_Rect(hud, (width - bar_width) / 2, height * 0.66 + 10 * scale, bar_width, 3 * scale, {0, 0, 0, 0.6})
		Render.Hud_Rect(hud, (width - bar_width) / 2, height * 0.66 + 10 * scale, bar_width * fraction, 3 * scale, {0.4, 1, 0.6, 0.95})
	}
	if mission.hostage_in_reach do Render.Hud_Text(hud, (width - Render.Hud_Text_Width("E  RESCUE HOSTAGE", scale)) / 2, height * 0.66, "E  RESCUE HOSTAGE", scale, {1, 0.9, 0.4, 0.95})
	if mission.toast_seconds > 0 do Render.Hud_Text(hud, (width - Render.Hud_Text_Width(mission.toast_text, scale)) / 2, height * 0.2, mission.toast_text, scale, {0.6, 1, 0.6, min(mission.toast_seconds, 1)})
}

@(private = "file")
draw_briefing :: proc(hud: ^Render.Hud, width, height, scale: f32) {
	Render.Hud_Rect(hud, 0, 0, width, height, {0, 0, 0, 0.78})
	lines := [?]string{
		"OPERATION SENTINEL",
		"",
		"A HOSTAGE IS HELD IN THE BARRACKS OF THIS BASE.",
		"ITS RADAR MUST GO DOWN AND ITS CAMERAS MUST NOT SEE YOU.",
		"",
		"1  GET INSIDE THE COMPOUND",
		"2  HACK THE CAMERA COMPUTER IN THE HQ (HOLD E)",
		"3  DESTROY THE RADAR STATION",
		"4  RESCUE THE HOSTAGE IN THE BARRACKS (E)",
		"5  REACH THE EXTRACTION POINT (GREEN BEACON)",
		"",
		"WASD MOVE  SHIFT RUN  C CROUCH  E USE  F FLASHLIGHT  B BINOCULARS  M MAP",
		"",
		"PRESS ENTER TO BEGIN",
	}
	y := height * 0.25
	for line, index in lines {
		size := scale * (2.4 if index == 0 else 1.1)
		Render.Hud_Text(hud, (width - Render.Hud_Text_Width(line, size)) / 2, y, line, size, {1, 1, 1, 0.95} if index != 0 else {1, 0.85, 0.3, 1})
		y += 12 * size * 0.9
	}
}

@(private = "file")
draw_mission_complete :: proc(hud: ^Render.Hud, mission: ^Mission_Play, width, height, scale: f32) {
	Render.Hud_Rect(hud, 0, 0, width, height, {0, 0, 0, 0.6})
	title := "MISSION COMPLETE"
	seconds := int(mission.state.elapsed_seconds)
	Render.Hud_Text(hud, (width - Render.Hud_Text_Width(title, scale * 3)) / 2, height * 0.38, title, scale * 3, {0.5, 1, 0.6, 1})
	line := fmt.tprintf("TIME %d:%02d", seconds / 60, seconds % 60)
	Render.Hud_Text(hud, (width - Render.Hud_Text_Width(line, scale * 1.5)) / 2, height * 0.5, line, scale * 1.5, {1, 1, 1, 0.95})
}

// Whether to hold the world still: the briefing is up and nothing has begun.
mission_pauses :: proc(play: ^Play) -> bool {
	return play.mission.state.status == .Briefing
}

mission_check_start :: proc(play: ^Play, input: ^Platform.Input) {
	if Platform.Input_Key_Down(input, .Enter) do Mission.Mission_Start(&play.mission.state)
}

// Draw items for the extraction beacon (a tall green column) and the burning radar.
mission_items :: proc(play: ^Play, items: ^[dynamic]Render.Draw_Item, lights: ^[dynamic]Render.Light) {
	mission := &play.mission
	column := la.matrix4_translate_f32(mission.extraction + {0, BEACON_HEIGHT_METERS / 2, 0})
	append(items, Render.Draw_Item{mesh = &mission.beacon, model = column, material_layer = i32(Materials.Surface_Material.Gunmetal), uv_scale = {1, 1}, illumination_model = .Lambert, emission = {0.25, 4, 0.7}})
	append(lights, Render.Light_Point(mission.extraction + {0, 3, 0}, {0.3, 1, 0.5}, 160, 26))
	if play.battle.targets[mission.radar_target].destroyed {
		flicker := 0.7 + 0.3 * math.sin(play.demo_seconds * 13)
		append(lights, Render.Light_Point(mission.radar_dish + {0, 1, 0}, {1, 0.5, 0.2}, 260 * flicker, 22))
	}
}
