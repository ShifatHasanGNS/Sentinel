package Sandbox

import "../../Engine/Procedural"
import "../../Engine/Render"
import World "../../Engine/World"
import "../Gameplay"
import "../Materials"
import "../Mission"
import "core:math"
import la "core:math/linalg"

CAMERA_TARGET_RADIUS_METERS :: 0.4
CAMERA_HEALTH :: 20.0
ALARM_ALERT_RADIUS_METERS :: 90.0
ALARM_REFRESH_SECONDS :: 3.0 // While the alarm sounds, soldiers are re-told where the player was this often.
LED_ACTIVE_EMISSION :: [3]f32{7, 0.4, 0.3}
LED_OFF_EMISSION :: [3]f32{0.15, 0.03, 0.03}

Camera_Instance :: struct {
	camera:       Mission.Security_Camera,
	target_index: int, // Its slot among the battle's targets: shooting it breaks it.
}

Camera_Meshes :: struct {
	body: [dynamic]Camera_Group,
	led:  Render.Mesh,
}

Camera_Group :: struct {
	mesh:     Render.Mesh,
	material: i32,
}

// A camera mounted on each watchtower (looking in over the yard), on the HQ's front corner, and on each gate guard post
// (looking out over the approach). Mount points are in the object's own frame.
cameras_create :: proc(play: ^Play, sandbox: ^Sandbox) {
	ground := sandbox.terrain.base_height_meters
	phase: f32
	for placement in sandbox.base.layout.placements {
		yaw := math.to_radians(placement.yaw_degrees)
		local: [3]f32
		center_yaw := yaw
		#partial switch placement.kind {
		case .Watchtower: local, center_yaw = {0, 7.1, -1.55}, yaw + math.PI
		case .Headquarters: local = {6.9, 3.5, 5.3}
		case .Guard_Post: local = {0, 3.0, 1.9}
		case: continue
		}
		position := [3]f32{placement.x, ground, placement.z} + World.rotate_about_y(local, yaw)
		phase += 1.3
		target := Gameplay.Battle_Add_Target(&play.battle, position, CAMERA_TARGET_RADIUS_METERS, CAMERA_HEALTH)
		append(&play.cameras, Camera_Instance{camera = Mission.Security_Camera{position = position, center_yaw = center_yaw, sweep_phase = phase}, target_index = target})
	}
	play.camera_meshes = build_camera_meshes()
}

cameras_destroy :: proc(play: ^Play) {
	for &group in play.camera_meshes.body do Render.Mesh_Destroy(&group.mesh)
	delete(play.camera_meshes.body)
	Render.Mesh_Destroy(&play.camera_meshes.led)
	delete(play.cameras)
}

@(private = "file")
build_camera_meshes :: proc() -> (meshes: Camera_Meshes) {
	parts := [?]Procedural.Part{
		{primitive = Procedural.Box({0.3, 0.25, 0.55}), position = {0, 0, 0}, material = i32(Materials.Surface_Material.Painted_Metal)},
		{primitive = Procedural.Cylinder(0.09, 0.12, 12), position = {0, 0, 0.32}, rotation_degrees = {90, 0, 0}, material = i32(Materials.Surface_Material.Glass)},
		{primitive = Procedural.Box({0.06, 0.4, 0.06}), position = {0, 0.3, -0.15}, material = i32(Materials.Surface_Material.Rusted_Metal)},
	}
	assembly := Procedural.Assembly_Build(parts[:])
	defer Procedural.Assembly_Destroy(&assembly)
	for group in assembly.groups do append(&meshes.body, Camera_Group{Render.Mesh_Upload(group.mesh), group.material})
	led := Procedural.Sphere_Create(0.04, 8, 4)
	defer Procedural.Mesh_Destroy(&led)
	meshes.led = Render.Mesh_Upload(led)
	return meshes
}

// One frame: the hack and bullets disable cameras; working ones look for the player; a sighting raises the alarm and tells nearby
// soldiers where the player is.
cameras_update :: proc(sandbox: ^Sandbox, delta_seconds: f32) {
	play := &sandbox.play
	Mission.Alarm_Update(&play.alarm, delta_seconds)
	play.clock_seconds += delta_seconds
	player := play.battle.player
	target := Gameplay.Player_Eye(player)
	hacked := play.mission.state.done[.Hack_Cameras]
	for &instance in play.cameras {
		if hacked || play.battle.targets[instance.target_index].destroyed do instance.camera.disabled = true
		if instance.camera.disabled do continue
		sees := !Gameplay.Health_Is_Dead(player.health) && camera_has_clear_line(play, instance.camera.position, target) && Mission.Camera_Sees(instance.camera, play.clock_seconds, target, true, Gameplay.Player_Visibility(player))
		if Mission.Camera_Update(&instance.camera, sees, delta_seconds) do raise_alarm(play, target)
	}
	if Mission.Alarm_Active(play.alarm) {
		play.alarm_refresh_seconds -= delta_seconds
		if play.alarm_refresh_seconds <= 0 {
			play.alarm_refresh_seconds = ALARM_REFRESH_SECONDS
			Gameplay.Battle_Alert_Nearby(&play.battle, player.controller.position, ALARM_ALERT_RADIUS_METERS)
		}
	}
}

@(private = "file")
raise_alarm :: proc(play: ^Play, position: [3]f32) {
	was_quiet := !Mission.Alarm_Active(play.alarm)
	Mission.Alarm_Raise(&play.alarm)
	if was_quiet do play.alarm_refresh_seconds = 0
}

@(private = "file")
camera_has_clear_line :: proc(play: ^Play, from, to: [3]f32) -> bool {
	offset := to - from
	distance := la.length(offset)
	if distance < 1e-3 do return true
	hit := World.Raycast_World(play.battle.collision, play.battle.ground, from, offset / distance, distance)
	return !hit.hit || hit.distance > distance - 0.4
}

// Draw items: each camera housing at its sweeping heading with a red light while it is working.
cameras_items :: proc(play: ^Play, items: ^[dynamic]Render.Draw_Item) {
	for &instance in play.cameras {
		yaw := Mission.Camera_Yaw(instance.camera, play.clock_seconds)
		pitch: f32 = Mission.CAMERA_PITCH_RADIANS
		model := la.matrix4_translate_f32(instance.camera.position) * la.matrix4_rotate_f32(yaw, {0, 1, 0}) * la.matrix4_rotate_f32(-pitch, {1, 0, 0})
		for &group in play.camera_meshes.body {
			append(items, Render.Draw_Item{mesh = &group.mesh, model = model, material_layer = group.material, uv_scale = {1, 1}, triplanar = true, illumination_model = .Cook_Torrance})
		}
		led_model := model * la.matrix4_translate_f32({0.11, 0.1, 0.25})
		emission := LED_OFF_EMISSION if instance.camera.disabled else LED_ACTIVE_EMISSION
		append(items, Render.Draw_Item{mesh = &play.camera_meshes.led, model = led_model, material_layer = i32(Materials.Surface_Material.Gunmetal), uv_scale = {1, 1}, illumination_model = .Lambert, emission = emission})
	}
}

// ALARM across the top while it sounds.
cameras_draw_hud :: proc(play: ^Play, width, scale: f32) {
	if !Mission.Alarm_Active(play.alarm) do return
	pulse := 0.6 + 0.4 * math.sin(play.clock_seconds * 8)
	text := "ALARM"
	Render.Hud_Text(&play.hud, (width - Render.Hud_Text_Width(text, scale * 2.5)) / 2, 16, text, scale * 2.5, {1, 0.15, 0.1, pulse})
}
