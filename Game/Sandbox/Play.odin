package Sandbox

import "../../Engine/Platform"
import "../../Engine/Procedural"
import "../../Engine/Render"
import World "../../Engine/World"
import "../Base"
import "../Characters"
import "../Gameplay"
import "../Materials"
import "../Weapons"
import "core:fmt"
import "core:math"
import la "core:math/linalg"
import "core:strings"

PLAY_FIELD_OF_VIEW_DEGREES :: 72.0
PROP_COLLISION_RADIUS_METERS :: 30.0 // Trees and rocks within this distance of the player are solid.
TREE_TRUNK_HALF_WIDTH_METERS :: 0.2
TREE_HEIGHT_METERS :: 4.0
ROCK_HALF_WIDTH_METERS :: 0.8
ROCK_HEIGHT_METERS :: 1.0
PLAY_NEAR_PLANE_METERS :: 0.1
BODY_BACK_METERS :: 0.25 // The body stands this far behind the eye so the head is not in the camera,
BODY_RIGHT_METERS :: 0.2 // a little to the right so the held weapon enters the view from the lower right,
BODY_RAISE_METERS :: 0.15 // and a little up so the weapon is inside the frame rather than below it.
RECOIL_KICK_METERS :: 0.06
RECOIL_DECAY_PER_SECOND :: 10.0
DEMO_TURN_RADIANS_PER_SECOND :: 5.0
DEMO_ENGAGE_DISTANCE_METERS :: 22.0
EFFECT_SPHERE_SEGMENTS :: 12
TRACER_THICKNESS_METERS :: 0.025
EXPLOSION_VISUAL_RADIUS_METERS :: 4.0
// A tracer seen end-on from the muzzle would be a square filling the crosshair, so the player's tracers start a few meters out.
TRACER_SKIP_METERS :: 4.0
FLASHLIGHT_INTENSITY :: 90.0
FLASHLIGHT_RANGE_METERS :: 40.0
CHARACTERS_PER_VARIANT :: 64

Control_Mode :: enum {
	Play,
	Fly,
}

Weapon_View_Group :: struct {
	mesh:     Render.Mesh,
	material: i32,
}

// Everything the playable game adds to the world: the simulation, how soldiers and effects are drawn, the held weapon and the HUD.
Play :: struct {
	battle:        Gameplay.Battle,
	soldiers:      Characters.Character_Renderer,
	doors:         [dynamic]Base.Door,
	door_renderer: Base.Door_Renderer,
	door_in_reach: bool,
	interact_was_down: bool,
	body:          Characters.Character, // The player's own body, seen when looking down and in shadows.
	hud:           Render.Hud,
	view_weapons:  [Weapons.Weapon_Kind][dynamic]Weapon_View_Group,
	effect_cube:   Render.Mesh,
	effect_sphere: Render.Mesh,
	mode:          Control_Mode,
	tab_was_down:  bool,
	flashlight_on: bool,
	flashlight_was_down: bool,
	demo:          bool,
	recoil:        f32,
	shots_seen:    u32,
}

terrain_height :: proc(data: rawptr, x, z: f32) -> f32 {
	return Procedural.Terrain_Height((^Procedural.Terrain)(data)^, x, z)
}

play_create :: proc(sandbox: ^Sandbox, demo: bool, fly: bool) -> (ok: bool) {
	play := &sandbox.play
	base_height := sandbox.terrain.base_height_meters
	boxes := Base.Layout_Solids(sandbox.base.layout, base_height)
	defer delete(boxes)
	ground := World.Ground{height_at = terrain_height, data = sandbox.terrain}
	spawn := [3]f32{0, 0, 100}
	if demo do spawn = {0, 0, 52}
	spawn.y = terrain_height(sandbox.terrain, spawn.x, spawn.z)
	play.battle = Gameplay.Battle_Create(ground, boxes[:], spawn, 99)
	play.doors = Base.Layout_Doors(sandbox.base.layout, base_height)
	Base.Doors_Register(play.doors[:], &play.battle.collision)
	play.door_renderer = Base.Door_Renderer_Create(play.doors[:])
	spawn_garrison(&play.battle, sandbox.terrain)
	play.soldiers = Characters.Character_Renderer_Create(CHARACTERS_PER_VARIANT)
	play.hud = Render.Hud_Create() or_return
	for kind in Weapons.Weapon_Kind {
		assembly := Weapons.Weapon_Build(kind)
		defer Procedural.Assembly_Destroy(&assembly)
		for group in assembly.groups do append(&play.view_weapons[kind], Weapon_View_Group{Render.Mesh_Upload(group.mesh), group.material})
	}
	play.effect_cube = upload_unit(Procedural.Box_Create({1, 1, 1}))
	play.effect_sphere = upload_unit(Procedural.Sphere_Create(1, EFFECT_SPHERE_SEGMENTS, EFFECT_SPHERE_SEGMENTS / 2))
	play.body = Characters.Character{variant = .Rifleman, aiming = true, hide_weapon = true}
	play.demo = demo
	play.flashlight_on = demo
	play.mode = .Fly if fly else .Play
	return true
}

play_destroy :: proc(play: ^Play) {
	Base.Door_Renderer_Destroy(&play.door_renderer)
	delete(play.doors)
	Render.Mesh_Destroy(&play.effect_sphere)
	Render.Mesh_Destroy(&play.effect_cube)
	for &groups in play.view_weapons {
		for &group in groups do Render.Mesh_Destroy(&group.mesh)
		delete(groups)
	}
	Render.Hud_Destroy(&play.hud)
	Characters.Character_Renderer_Destroy(&play.soldiers)
	Gameplay.Battle_Destroy(&play.battle)
}

@(private = "file")
upload_unit :: proc(mesh: Procedural.Mesh) -> Render.Mesh {
	mesh := mesh
	defer Procedural.Mesh_Destroy(&mesh)
	return Render.Mesh_Upload(mesh)
}

// Gate guards, snipers beside the watchtowers, and three patrols through the compound.
@(private = "file")
spawn_garrison :: proc(battle: ^Gameplay.Battle, terrain: ^Procedural.Terrain) {
	ground := terrain.base_height_meters
	at :: proc(x, y, z: f32) -> [3]f32 {
		return {x, y, z}
	}
	for x in ([2]f32{-6, 6}) do Gameplay.Battle_Add_Enemy(battle, .Guard, at(x, ground, 48), 0, nil)
	for angle in ([4]f32{45, 135, 225, 315}) {
		position := [2]f32{math.cos(math.to_radians(angle)), math.sin(math.to_radians(angle))} * 57
		Gameplay.Battle_Add_Enemy(battle, .Sniper, at(position.x, ground, position.y), math.atan2(-position.x, -position.y) + math.PI, nil)
	}
	west_loop := [][3]f32{at(-32, ground, -34), at(-32, ground, 34), at(-20, ground, 34), at(-20, ground, -34)}
	yard_loop := [][3]f32{at(-12, ground, -20), at(14, ground, -20), at(14, ground, 18), at(-12, ground, 18)}
	gate_loop := [][3]f32{at(-24, ground, 44), at(24, ground, 44)}
	Gameplay.Battle_Add_Enemy(battle, .Enemy, west_loop[0], 0, west_loop)
	Gameplay.Battle_Add_Enemy(battle, .Rifleman, west_loop[2], 0, west_loop[2:])
	Gameplay.Battle_Add_Enemy(battle, .Enemy, yard_loop[0], 0, yard_loop)
	Gameplay.Battle_Add_Enemy(battle, .Officer, yard_loop[2], 0, yard_loop[2:])
	Gameplay.Battle_Add_Enemy(battle, .Enemy, gate_loop[0], 0, gate_loop)
	Gameplay.Battle_Add_Enemy(battle, .Rifleman, gate_loop[1], 0, gate_loop[1:])
}

// Tab flips between playing and the free debug camera; then the simulation advances one frame.
play_update :: proc(sandbox: ^Sandbox, input: ^Platform.Input, delta_seconds: f32) {
	play := &sandbox.play
	fill_prop_solids(sandbox)
	tab_down := Platform.Input_Key_Down(input, .Tab)
	if tab_down && !play.tab_was_down do play.mode = .Fly if play.mode == .Play else .Play
	play.tab_was_down = tab_down
	interact_down := Platform.Input_Key_Down(input, .E)
	if play.mode == .Play do interact_with_doors(play, interact_down && !play.interact_was_down)
	play.interact_was_down = interact_down
	Base.Doors_Update(play.doors[:], &play.battle.collision, delta_seconds)
	flashlight_down := Platform.Input_Key_Down(input, .F)
	if flashlight_down && !play.flashlight_was_down do play.flashlight_on = !play.flashlight_on
	play.flashlight_was_down = flashlight_down
	play.recoil = max(play.recoil - RECOIL_DECAY_PER_SECOND * RECOIL_KICK_METERS * delta_seconds * 10, 0)
	switch play.mode {
	case .Fly:
		Fly_Camera_Update(&sandbox.camera, input, delta_seconds)
		battle_update_unattended(&play.battle, delta_seconds)
		animate_body(play, delta_seconds)
	case .Play:
		player_input := demo_input(play.battle, delta_seconds) if play.demo else collect_input(input)
		Gameplay.Battle_Update(&play.battle, player_input, delta_seconds)
		sync_camera_to_player(sandbox)
		animate_body(play, delta_seconds)
	}
	if play.battle.player.shots_fired != play.shots_seen {
		play.shots_seen = play.battle.player.shots_fired
		play.recoil = RECOIL_KICK_METERS
	}
}

// The benchmark flies a fixed circuit but the soldiers still think, so their cost is measured.
play_update_idle :: proc(sandbox: ^Sandbox, delta_seconds: f32) {
	fill_prop_solids(sandbox)
	Base.Doors_Update(sandbox.play.doors[:], &sandbox.play.battle.collision, delta_seconds)
	battle_update_unattended(&sandbox.play.battle, delta_seconds)
}

// While nobody plays (fly camera, benchmark) the soldiers still think and shoot, but the idle player is kept alive.
@(private = "file")
battle_update_unattended :: proc(battle: ^Gameplay.Battle, delta_seconds: f32) {
	Gameplay.Health_Heal(&battle.player.health, battle.player.health.maximum)
	Gameplay.Battle_Update(battle, {}, delta_seconds)
}

sync_camera_to_player :: proc(sandbox: ^Sandbox) {
	player := sandbox.play.battle.player
	sandbox.camera = Fly_Camera{position = Gameplay.Player_Eye(player), yaw_radians = player.yaw_radians, pitch_radians = player.pitch_radians}
}

@(private = "file")
collect_input :: proc(input: ^Platform.Input) -> (result: Gameplay.Player_Input) {
	axis :: proc(input: ^Platform.Input, positive, negative: Platform.Key) -> f32 {
		return f32(int(Platform.Input_Key_Down(input, positive))) - f32(int(Platform.Input_Key_Down(input, negative)))
	}
	result.move = {axis(input, .D, .A), axis(input, .W, .S)}
	result.look = {-input.mouse_delta.x * MOUSE_RADIANS_PER_PIXEL, -input.mouse_delta.y * MOUSE_RADIANS_PER_PIXEL}
	result.fire = Platform.Input_Mouse_Down(input, .Left)
	result.reload = Platform.Input_Key_Down(input, .R)
	result.sprint = Platform.Input_Key_Down(input, .Left_Shift)
	result.jump = Platform.Input_Key_Down(input, .Space)
	result.respawn = Platform.Input_Key_Down(input, .Enter)
	keys := [5]Platform.Key{.Num_1, .Num_2, .Num_3, .Num_4, .Num_5}
	weapons := [5]Weapons.Weapon_Kind{.Rifle, .Pistol, .Sniper_Rifle, .Rocket_Launcher, .Grenade}
	for key, index in keys do if Platform.Input_Key_Down(input, key) do result.select = weapons[index]
	return result
}

// A bot for hands-free verification: turn toward the nearest living enemy, walk to engagement range and fire when aimed.
@(private = "file")
demo_input :: proc(battle: Gameplay.Battle, delta_seconds: f32) -> (result: Gameplay.Player_Input) {
	eye := Gameplay.Player_Eye(battle.player)
	nearest := math.INF_F32
	target: [3]f32
	for enemy in battle.enemies {
		if !Gameplay.Enemy_Is_Alive(enemy) do continue
		chest := Gameplay.Enemy_Chest_Position(enemy)
		if distance := la.length(chest - eye); distance < nearest do nearest, target = distance, chest
	}
	if nearest == math.INF_F32 do return
	direction := (target - eye) / nearest
	wanted_yaw := math.atan2(-direction.x, -direction.z)
	wanted_pitch := math.atan2(direction.y, math.sqrt(direction.x * direction.x + direction.z * direction.z))
	max_turn := DEMO_TURN_RADIANS_PER_SECOND * delta_seconds
	yaw_error := wrap_angle(wanted_yaw - battle.player.yaw_radians)
	pitch_error := wanted_pitch - battle.player.pitch_radians
	result.look = {clamp(yaw_error, -max_turn, max_turn), clamp(pitch_error, -max_turn, max_turn)}
	result.fire = abs(yaw_error) < 0.04 && abs(pitch_error) < 0.04
	if nearest > DEMO_ENGAGE_DISTANCE_METERS do result.move = {0, 1}
	return result
}

@(private = "file")
wrap_angle :: proc(angle: f32) -> f32 {
	wrapped := math.mod(angle + math.PI, 2 * math.PI)
	if wrapped < 0 do wrapped += 2 * math.PI
	return wrapped - math.PI
}

// Adds soldiers, effects and the held weapon to the draw lists, and returns the lights the effects cast.
play_items :: proc(sandbox: ^Sandbox, items, shadow_items: ^[dynamic]Render.Draw_Item) -> (lights: [dynamic]Render.Light) {
	play := &sandbox.play
	lights = make([dynamic]Render.Light, context.temp_allocator)
	characters := make([dynamic]Characters.Character, context.temp_allocator)
	for enemy in play.battle.enemies do append(&characters, enemy.character)
	body_shown := !Gameplay.Health_Is_Dead(play.battle.player.health)
	if body_shown do append(&characters, play.body)
	for item in Characters.Character_Renderer_Items(&play.soldiers, characters[:]) {
		append(items, item)
		append(shadow_items, item)
	}
	for door_item in Base.Door_Renderer_Items(&play.door_renderer, play.doors[:]) {
		append(items, door_item)
		append(shadow_items, door_item)
	}
	for effect in play.battle.effects do add_effect(play, effect, items, &lights)
	if play.flashlight_on && play.mode == .Play {
		player := play.battle.player
		flashlight := Render.Light_Spot(Gameplay.Player_Eye(player) + Gameplay.Player_Forward(player) * 0.3, Gameplay.Player_Forward(player), {1, 0.95, 0.85}, FLASHLIGHT_INTENSITY, FLASHLIGHT_RANGE_METERS, 10, 24)
		flashlight.casts_shadow = true
		append(&lights, flashlight)
	}
	if body_shown do add_held_weapon(play, items)
	return lights
}

@(private = "file")
add_effect :: proc(play: ^Play, effect: Gameplay.Effect, items: ^[dynamic]Render.Draw_Item, lights: ^[dynamic]Render.Light) {
	fade := 1 - effect.age / effect.lifetime
	switch effect.kind {
	case .Tracer:
		start := effect.position
		if la.length(start - Gameplay.Player_Eye(play.battle.player)) < 2 do start += la.normalize0(effect.end - start) * TRACER_SKIP_METERS
		span := effect.end - start
		length := la.length(span)
		if length < 1e-3 || la.dot(span, effect.end - effect.position) <= 0 do return
		model := along_axis(start + span / 2, span / length) * la.matrix4_scale_f32({TRACER_THICKNESS_METERS, TRACER_THICKNESS_METERS, length})
		append(items, effect_item(&play.effect_cube, model, [3]f32{9, 6.5, 2.5} * fade))
	case .Muzzle_Flash:
		// The player's own flash sits at the camera and would fill the screen, so only its light is kept.
		if la.length(effect.position - Gameplay.Player_Eye(play.battle.player)) > 2 {
			append(items, effect_item(&play.effect_sphere, sphere_matrix(effect.position, 0.1), [3]f32{14, 10, 4} * fade))
		}
		append(lights, Render.Light_Point(effect.position, {1, 0.8, 0.45}, 70 * fade, 14))
	case .Impact:
		append(items, effect_item(&play.effect_sphere, sphere_matrix(effect.position, 0.03 + 0.12 * (1 - fade)), [3]f32{5, 3.5, 1.5} * fade))
	case .Explosion:
		radius := EXPLOSION_VISUAL_RADIUS_METERS * math.sqrt(1 - fade)
		append(items, effect_item(&play.effect_sphere, sphere_matrix(effect.position, max(radius, 0.1)), [3]f32{10, 5, 1.5} * fade * fade))
		append(lights, Render.Light_Point(effect.position, {1, 0.55, 0.2}, 1100 * fade * fade, 42))
	}
}

@(private = "file")
effect_item :: proc(mesh: ^Render.Mesh, model: matrix[4, 4]f32, emission: [3]f32) -> Render.Draw_Item {
	return Render.Draw_Item{mesh = mesh, model = model, material_layer = i32(Materials.Surface_Material.Gunmetal), uv_scale = {1, 1}, illumination_model = .Lambert, emission = emission}
}

@(private = "file")
sphere_matrix :: proc(center: [3]f32, radius: f32) -> matrix[4, 4]f32 {
	return la.matrix4_translate_f32(center) * la.matrix4_scale_f32({radius, radius, radius})
}

// A frame at `origin` with +Z along `axis` and +Y as upright as possible.
@(private = "file")
along_axis :: proc(origin, axis: [3]f32) -> matrix[4, 4]f32 {
	up := [3]f32{0, 1, 0}
	if abs(axis.y) > 0.99 do up = {1, 0, 0}
	y := la.normalize(up - axis * la.dot(up, axis))
	x := la.cross(y, axis)
	return matrix[4, 4]f32{
		x.x, y.x, axis.x, origin.x,
		x.y, y.y, axis.y, origin.y,
		x.z, y.z, axis.z, origin.z,
		0, 0, 0, 1,
	}
}

// The body stands just behind the eye, facing where the player faces and aiming where the player looks; its stride follows the
// controller's speed. The heading that makes Enemy_Forward equal the player's forward is yaw + pi (player yaw 0 looks along -Z).
@(private = "file")
animate_body :: proc(play: ^Play, delta_seconds: f32) {
	player := play.battle.player
	forward := Gameplay.Player_Forward(player)
	flat := la.normalize0([3]f32{forward.x, 0, forward.z})
	body := &play.body
	right := [3]f32{-flat.z, 0, flat.x} // Forward rotated a quarter turn clockwise seen from above.
	body.position = player.controller.position - flat * BODY_BACK_METERS + right * BODY_RIGHT_METERS + {0, BODY_RAISE_METERS, 0}
	body.heading_radians = player.yaw_radians + math.PI
	body.speed = la.length([2]f32{player.controller.velocity.x, player.controller.velocity.z})
	body.aim_direction = forward
	Characters.Character_Step(body, delta_seconds)
}

// The selected weapon sits in the body's right hand, exactly where a soldier would hold it, kicked back by the last shot.
@(private = "file")
add_held_weapon :: proc(play: ^Play, items: ^[dynamic]Render.Draw_Item) {
	player := play.battle.player
	pose := Characters.Character_Pose(play.body)
	recoil := la.matrix4_translate_f32(-Gameplay.Player_Forward(player) * play.recoil)
	model := recoil * Characters.Weapon_Matrix(pose)
	for &group in play.view_weapons[player.current] {
		append(items, Render.Draw_Item{mesh = &group.mesh, model = model, material_layer = group.material, uv_scale = {2, 2}, illumination_model = .Cook_Torrance})
	}
}

play_camera :: proc(sandbox: ^Sandbox, aspect: f32) -> Render.Camera {
	if sandbox.play.mode == .Play {
		return Render.Camera_Look_At(sandbox.camera.position, sandbox.camera.position + Fly_Camera_Forward(sandbox.camera), PLAY_FIELD_OF_VIEW_DEGREES, aspect, PLAY_NEAR_PLANE_METERS, 1200)
	}
	return Render.Camera_Look_At(sandbox.camera.position, sandbox.camera.position + Fly_Camera_Forward(sandbox.camera), FIELD_OF_VIEW_DEGREES, aspect, 0.3, 1200)
}

// Crosshair, health, ammunition, hit confirmation, damage flash, and the death screen, queued and flushed over the frame.
play_draw_hud :: proc(sandbox: ^Sandbox, width, height: i32) {
	play := &sandbox.play
	hud := &play.hud
	player := play.battle.player
	w, h := f32(width), f32(height)
	scale := max(h / 360, 2)
	if play.mode == .Play && player.damage_flash > 0 do Render.Hud_Rect(hud, 0, 0, w, h, {0.8, 0, 0, 0.4 * player.damage_flash})
	if play.mode == .Play && !Gameplay.Health_Is_Dead(player.health) {
		draw_crosshair(hud, w / 2, h / 2, scale, player.hit_marker > 0)
		draw_vitals(hud, player, w, h, scale)
	}
	living := 0
	for enemy in play.battle.enemies do if Gameplay.Enemy_Is_Alive(enemy) do living += 1
	Render.Hud_Text(hud, 16, 16, fmt.tprintf("KILLS %d   ENEMIES %d", player.kills, living), scale, {1, 1, 1, 0.9})
	if play.mode == .Fly do Render.Hud_Text(hud, w - 16 - Render.Hud_Text_Width("FLY MODE - TAB TO PLAY", scale), 16, "FLY MODE - TAB TO PLAY", scale, {1, 0.9, 0.3, 0.9})
	if play.mode == .Play && play.door_in_reach && !Gameplay.Health_Is_Dead(player.health) do Render.Hud_Text(hud, (w - Render.Hud_Text_Width("E  OPEN / CLOSE", scale)) / 2, h * 0.62, "E  OPEN / CLOSE", scale, {1, 1, 1, 0.9})
	if Gameplay.Health_Is_Dead(player.health) do draw_death_screen(hud, w, h, scale)
	Render.Hud_Flush(hud, width, height)
}

@(private = "file")
draw_crosshair :: proc(hud: ^Render.Hud, x, y, scale: f32, hit: bool) {
	color := [4]f32{1, 0.25, 0.2, 1} if hit else {1, 1, 1, 0.85}
	gap, length, thickness := 4 * scale / 2, 6 * scale / 2, max(scale * 0.75, 1)
	Render.Hud_Rect(hud, x - gap - length, y - thickness / 2, length, thickness, color)
	Render.Hud_Rect(hud, x + gap, y - thickness / 2, length, thickness, color)
	Render.Hud_Rect(hud, x - thickness / 2, y - gap - length, thickness, length, color)
	Render.Hud_Rect(hud, x - thickness / 2, y + gap, thickness, length, color)
}

@(private = "file")
draw_vitals :: proc(hud: ^Render.Hud, player: Gameplay.Player, w, h, scale: f32) {
	bar_width, bar_height := 60 * scale, 5 * scale
	fraction := player.health.current / player.health.maximum
	Render.Hud_Rect(hud, 16, h - 16 - bar_height, bar_width, bar_height, {0, 0, 0, 0.55})
	Render.Hud_Rect(hud, 16, h - 16 - bar_height, bar_width * fraction, bar_height, {1 - fraction, fraction * 0.9, 0.15, 0.9})
	Render.Hud_Text(hud, 16, h - 16 - bar_height - 9 * scale, fmt.tprintf("HP %d", int(math.ceil(player.health.current))), scale, {1, 1, 1, 0.95})
	state := player.weapons[player.current]
	name, _ := strings.replace_all(fmt.tprintf("%v", player.current), "_", " ", context.temp_allocator)
	status := "RELOADING" if state.reload_remaining_seconds > 0 else fmt.tprintf("%d / %d", state.ammo, state.reserve)
	Render.Hud_Text(hud, w - 16 - Render.Hud_Text_Width(status, scale * 1.5), h - 16 - 9 * scale * 1.5, status, scale * 1.5, {1, 0.95, 0.6, 0.95})
	Render.Hud_Text(hud, w - 16 - Render.Hud_Text_Width(name, scale), h - 16 - 9 * scale * 1.5 - 9 * scale, name, scale, {1, 1, 1, 0.8})
}

@(private = "file")
draw_death_screen :: proc(hud: ^Render.Hud, w, h, scale: f32) {
	Render.Hud_Rect(hud, 0, 0, w, h, {0, 0, 0, 0.55})
	title, hint := "YOU DIED", "PRESS ENTER TO RESPAWN"
	Render.Hud_Text(hud, (w - Render.Hud_Text_Width(title, scale * 3)) / 2, h / 2 - 16 * scale, title, scale * 3, {0.9, 0.15, 0.1, 1})
	Render.Hud_Text(hud, (w - Render.Hud_Text_Width(hint, scale)) / 2, h / 2 + 12 * scale, hint, scale, {1, 1, 1, 0.9})
}

// The scattered props near the player become this frame's temporary solids: trunks and boulders block, bushes do not.
@(private = "file")
fill_prop_solids :: proc(sandbox: ^Sandbox) {
	collision := &sandbox.play.battle.collision
	clear(&collision.temporary)
	player := sandbox.play.battle.player.controller.position
	for _, &chunk in sandbox.chunks {
		for point in chunk.scatter {
			if abs(point.position.x - player.x) > PROP_COLLISION_RADIUS_METERS || abs(point.position.z - player.z) > PROP_COLLISION_RADIUS_METERS do continue
			if solid, solid_ok := prop_solid(point); solid_ok do append(&collision.temporary, solid)
		}
	}
}

@(private = "file")
prop_solid :: proc(point: Procedural.Scatter_Point) -> (solid: World.Solid, ok: bool) {
	switch {
	case point.variant < TREE_VARIANT_LIMIT:
		half := TREE_TRUNK_HALF_WIDTH_METERS * point.scale
		height := TREE_HEIGHT_METERS * point.scale
		return World.Solid{center = point.position + {0, height / 2, 0}, half_extents = {half, height / 2, half}, yaw_radians = point.yaw_radians}, true
	case point.variant < ROCK_VARIANT_LIMIT:
		half := ROCK_HALF_WIDTH_METERS * point.scale
		height := ROCK_HEIGHT_METERS * point.scale
		return World.Solid{center = point.position + {0, height / 2, 0}, half_extents = {half, height / 2, half}, yaw_radians = point.yaw_radians}, true
	}
	return {}, false
}

// E toggles the door in reach (a gate's two leaves together); `pressed` is the key's rising edge. Also records whether a door is in
// reach, for the on-screen prompt.
@(private = "file")
interact_with_doors :: proc(play: ^Play, pressed: bool) {
	index, found := Base.Doors_Nearest(play.doors[:], play.battle.player.controller.position)
	play.door_in_reach = found
	if found && pressed do Base.Doors_Toggle(play.doors[:], index)
}
