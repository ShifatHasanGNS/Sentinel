package Showroom

import "../../Engine/Platform"
import "../../Engine/Procedural"
import "../../Engine/Render"
import "../Characters"
import "../Gameplay"
import "../Materials"
import "core:math"
import la "core:math/linalg"

LINEUP_WALK_RADIUS_METERS :: 6.0
LINEUP_HIT_INTERVAL_SECONDS :: 1.4

// Every soldier variant walking a circle (the gait), another row aiming, one crouched, and a hit now and then (the spring).
Soldier_Lineup :: struct {
	renderer:             Render.Renderer,
	materials:            Procedural.Texture_Set,
	ground:               Gallery_Item,
	soldiers:             Characters.Character_Renderer,
	characters:           [dynamic]Characters.Character,
	walk_angle_offsets:   [dynamic]f32,
	camera_angle_radians: f32,
	hit_timer_seconds:    f32,
	next_hit:             int,
	hours:                f32,
}

Soldier_Lineup_Create :: proc(width, height: i32, hours: f32) -> (lineup: Soldier_Lineup, ok: bool) {
	lineup.renderer = Render.Renderer_Create(width, height) or_return
	lineup.materials = Materials.Materials_Bake() or_return
	lineup.ground = create_ground(60, 30)
	lineup.soldiers = Characters.Character_Renderer_Create(16)
	lineup.hours = 11.5 if hours < 0 else hours
	speeds := [5]f32{1.2, 1.5, 2.2, 3.8, 1.4}
	for variant, index in Characters.Soldier_Variant {
		append(&lineup.walk_angle_offsets, f32(index) * 2 * math.PI / 5)
		append(&lineup.characters, Characters.Character{variant = variant, speed = speeds[index]})
		append(&lineup.characters, aimer(variant, f32(index) * 2 - 4))
	}
	append(&lineup.characters, crouched_sniper())
	return lineup, true
}

Soldier_Lineup_Update :: proc(lineup: ^Soldier_Lineup, clock: Platform.Clock) {
	lineup.camera_angle_radians += clock.delta_seconds * 0.12
	lineup.hit_timer_seconds += clock.delta_seconds
	walker := 0
	for &character in lineup.characters {
		if character.speed > 0 {
			lineup.walk_angle_offsets[walker] += character.speed / LINEUP_WALK_RADIUS_METERS * clock.delta_seconds
			place_on_circle(&character, lineup.walk_angle_offsets[walker])
			walker += 1
		}
		Characters.Character_Step(&character, clock.delta_seconds)
	}
	if lineup.hit_timer_seconds > LINEUP_HIT_INTERVAL_SECONDS {
		lineup.hit_timer_seconds = 0
		hit_next_aimer(lineup)
	}
}

Soldier_Lineup_Render :: proc(lineup: ^Soldier_Lineup, window: Platform.Window) {
	items := Characters.Character_Renderer_Items(&lineup.soldiers, lineup.characters[:])
	append(&items, as_draw_item(&lineup.ground))
	daylight := Gameplay.Daylight_For_Hours(lineup.hours)
	aspect := f32(window.framebuffer_width) / f32(window.framebuffer_height)
	target := [3]f32{0, 1, 3}
	eye := target + {15 * math.sin(lineup.camera_angle_radians), 3.5, 15 * math.cos(lineup.camera_angle_radians)}
	frame := Render.Frame{
		camera = Render.Camera_Look_At(eye, target, 55, aspect, 0.2, 400),
		items = items[:],
		sun = daylight.sun,
		sky = daylight.sky,
		sun_shadows = true,
		shadow_distance_meters = 60,
		materials = &lineup.materials,
		exposure = daylight.exposure,
		vignette_strength = 0.3,
	}
	Render.Renderer_Render(&lineup.renderer, frame, window.framebuffer_width, window.framebuffer_height)
}

Soldier_Lineup_Destroy :: proc(lineup: ^Soldier_Lineup) {
	delete(lineup.characters)
	delete(lineup.walk_angle_offsets)
	Characters.Character_Renderer_Destroy(&lineup.soldiers)
	Render.Mesh_Destroy(&lineup.ground.mesh)
	Procedural.Texture_Set_Destroy(&lineup.materials)
	Render.Renderer_Destroy(&lineup.renderer)
}

@(private = "file")
aimer :: proc(variant: Characters.Soldier_Variant, x: f32) -> Characters.Character {
	return Characters.Character{variant = variant, position = {x, 0, 10}, heading_radians = math.PI, aiming = true, aim_direction = la.normalize([3]f32{-x * 0.02, 0.05, -1})}
}

@(private = "file")
crouched_sniper :: proc() -> Characters.Character {
	character := aimer(.Sniper, 6.5)
	character.crouch = 0.8
	return character
}

@(private = "file")
place_on_circle :: proc(character: ^Characters.Character, angle: f32) {
	character.position = {math.cos(angle) * LINEUP_WALK_RADIUS_METERS, 0, math.sin(angle) * LINEUP_WALK_RADIUS_METERS}
	character.heading_radians = math.atan2(-math.sin(angle), math.cos(angle))
}

@(private = "file")
hit_next_aimer :: proc(lineup: ^Soldier_Lineup) {
	aimers := make([dynamic]int, context.temp_allocator)
	for character, index in lineup.characters do if character.aiming do append(&aimers, index)
	target := aimers[lineup.next_hit % len(aimers)]
	lineup.next_hit += 1
	Characters.Character_Hit(&lineup.characters[target], {0.3, 0.1, 1})
}
