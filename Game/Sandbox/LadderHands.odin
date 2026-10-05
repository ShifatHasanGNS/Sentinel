package Sandbox

import "../../Engine/Render"
import World "../../Engine/World"
import "../Gameplay"
import "../Materials"
import la "core:math/linalg"

LADDER_HAND_REACH_METERS :: 1.1 // The higher hand holds the rung this far above the feet (below the eye, so the hands fill the lower view).
LADDER_HAND_SPREAD_METERS :: 0.16 // Hands sit this far either side of the ladder's centre line.
LADDER_RUNG_DEPTH_METERS :: 0.04 // Rung centre line behind the climbable face.
GLOVE_SIZE_METERS :: [3]f32{0.1, 0.07, 0.11}
SLEEVE_THICKNESS_METERS :: 0.055
SHOULDER_DROP_METERS :: 0.38
SHOULDER_BACK_METERS :: 0.12
SHOULDER_HALF_WIDTH_METERS :: 0.2

// Two gloved hands on the rungs, hand over hand: the left hand takes the even rungs and the right the odd ones, each within
// reach of the chest, so as the body rises the hands leapfrog upward one after the other. A sleeve joins each to its shoulder.
ladder_hand_items :: proc(play: ^Play, items: ^[dynamic]Render.Draw_Item) {
	player := play.battle.player
	grip := player.controller.grip
	if grip.phase != .Mounting && grip.phase != .Climbing do return
	ladder := play.battle.collision.ladders[grip.index]
	top_rung := int(World.Ladder_Top_Meters(ladder) / World.LADDER_RUNG_METERS) - 1
	eye := Gameplay.Player_Eye(player)
	forward := Gameplay.Player_Forward(player)
	right := la.normalize0(la.cross(forward, [3]f32{0, 1, 0}))
	reach_height := grip.height + LADDER_HAND_REACH_METERS
	for side in ([2]int{0, 1}) {
		rung := highest_rung_with_parity(reach_height, side, top_rung)
		hand := rung_grip_point(ladder, rung, f32(side * 2 - 1) * LADDER_HAND_SPREAD_METERS)
		shoulder := eye + [3]f32{0, -SHOULDER_DROP_METERS, 0} - forward * SHOULDER_BACK_METERS + right * (f32(side * 2 - 1) * SHOULDER_HALF_WIDTH_METERS)
		append(items, limb_item(play, shoulder, hand, SLEEVE_THICKNESS_METERS, .Fabric_Dark))
		append(items, glove_item(play, hand, ladder.yaw_radians))
	}
}

@(private = "file")
highest_rung_with_parity :: proc(height_meters: f32, parity, top_rung: int) -> int {
	rung := int(height_meters / World.LADDER_RUNG_METERS)
	if rung % 2 != parity do rung -= 1
	return clamp(rung, 1 + (parity + 1) % 2, max(top_rung - (top_rung + parity) % 2, 1))
}

// A point on a rung (rung k sits k * 0.3 m above the ladder's foot), `across_meters` along the rung from the centre line.
@(private = "file")
rung_grip_point :: proc(ladder: World.Solid, rung: int, across_meters: f32) -> [3]f32 {
	local := [3]f32{across_meters, 0, ladder.half_extents.z - LADDER_RUNG_DEPTH_METERS}
	offset := World.rotate_about_y(local, ladder.yaw_radians)
	return {ladder.center.x + offset.x, World.Ladder_Bottom_Meters(ladder) + f32(rung) * World.LADDER_RUNG_METERS, ladder.center.z + offset.z}
}

@(private = "file")
limb_item :: proc(play: ^Play, from, to: [3]f32, thickness_meters: f32, material: Materials.Surface_Material) -> Render.Draw_Item {
	span := to - from
	length := la.length(span)
	model := along_axis((from + to) / 2, span / length) * la.matrix4_scale_f32({thickness_meters, thickness_meters, length})
	return Render.Draw_Item{mesh = &play.effect_cube, model = model, material_layer = i32(material), uv_scale = {2, 2}, triplanar = true, illumination_model = .Oren_Nayar}
}

@(private = "file")
glove_item :: proc(play: ^Play, position: [3]f32, yaw_radians: f32) -> Render.Draw_Item {
	model := la.matrix4_translate_f32(position) * la.matrix4_rotate_f32(yaw_radians, {0, 1, 0}) * la.matrix4_scale_f32(GLOVE_SIZE_METERS)
	return Render.Draw_Item{mesh = &play.effect_cube, model = model, material_layer = i32(Materials.Surface_Material.Rubber), uv_scale = {1, 1}, triplanar = true, illumination_model = .Cook_Torrance}
}
