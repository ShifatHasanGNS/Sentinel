package Sandbox

import "../../Engine/Platform"
import "../../Engine/Procedural"
import "../../Engine/Render"
import World "../../Engine/World"
import "../Base"
import "../Characters"
import "../Gameplay"
import "../Materials"
import "../Mission"
import "../Vehicles"
import "../Weapons"
import "core:fmt"
import "core:strconv"
import "core:math"
import "core:os"
import la "core:math/linalg"
import "core:strings"

PLAY_FIELD_OF_VIEW_DEGREES :: 72.0
PROP_COLLISION_RADIUS_METERS :: 30.0 // Trees and rocks within this distance of the player are solid.
CROUCHED_BODY :: 0.6 // How far the body model sinks into its crouch pose.
TREE_TRUNK_HALF_WIDTH_METERS :: 0.2
TREE_HEIGHT_METERS :: 4.0
ROCK_HALF_WIDTH_METERS :: 0.8
ROCK_HEIGHT_METERS :: 1.0
LADDER_BOB_METERS :: 0.02
HEAD_BOB_METERS :: 0.035
BOB_STEPS_PER_METER :: 1.5
SWAY_METERS_PER_RADIAN :: 0.35
SWAY_RETURN_PER_SECOND :: 9.0
PLAY_NEAR_PLANE_METERS :: 0.1
BODY_BACK_METERS :: 0.25 // The body stands this far behind the eye so the head is not in the camera,
BODY_RIGHT_METERS :: 0.2 // a little to the right so the held weapon enters the view from the lower right,
BODY_RAISE_METERS :: 0.15 // and a little up so the weapon is inside the frame rather than below it.
RECOIL_KICK_METERS :: 0.06
RECOIL_DECAY_PER_SECOND :: 10.0
DEMO_TURN_RADIANS_PER_SECOND :: 5.0
DEMO_ENGAGE_DISTANCE_METERS :: 22.0
EFFECT_SPHERE_SEGMENTS :: 20
TRACER_THICKNESS_METERS :: 0.018
EXPLOSION_VISUAL_RADIUS_METERS :: 4.0
// A tracer seen end-on from the muzzle would be a square filling the crosshair, so the player's tracers start a few meters out.
TRACER_SKIP_METERS :: 4.0
TRACER_STREAK_METERS :: 3.5
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
	mission:       Mission_Play,
	profile:       Mission.Profile,
	save_enabled:  bool,
	was_dead:      bool,
	completion_saved: bool,
	new_best:      bool,
	sound:         Sound_Bank,
	last_pickup_flash: f32,
	particles:     Particles,
	bob_phase:     f32,
	bob_strength:  f32, // 0 standing still .. 1 walking; follows speed smoothly.
	sway:          [2]f32, // Held weapon lag behind the view turn (x right, y up), springing back to rest.
	cameras:       [dynamic]Camera_Instance,
	camera_meshes: Camera_Meshes,
	alarm:         Mission.Alarm,
	alarm_refresh_seconds: f32,
	reinforcement_waves: int,
	clock_seconds: f32,
	soldiers:      Characters.Character_Renderer,
	doors:         [dynamic]Base.Door,
	door_renderer: Base.Door_Renderer,
	door_in_reach: bool,
	vehicles:      [dynamic]Vehicles.Vehicle,
	vehicle_renderer: Vehicles.Vehicle_Renderer,
	driving:       Maybe(int), // Index into `vehicles` of the one the player is in.
	seat_view:     bool, // V toggles between the chase camera and the seat.
	view_was_down: bool,
	mouse_idle_seconds: f32,
	demo_seconds:  f32,
	restart_requested: bool,
	pause_enabled: bool,
	sound_muted:   bool,
	quit_requested: bool,
	paused:        bool,
	escape_was_down: bool,
	next_variant:  Mission.Variant, // Which mission the next playthrough is (R repeats this one, N switches).
	autoplay:      bool,
	ladder_demo:   bool, // Overlay `ladder`: the player stands at the first watchtower ladder and holds forward.
	autoplay_seconds: f32,
	autoplay_reported: bool,
	boardable:     Maybe(int), // The vehicle in reach on foot, for the prompt.
	interact_was_down: bool,
	body:          Characters.Character, // The player's own body, seen when looking down and in shadows.
	hud:           Render.Hud,
	view_weapons:  [Weapons.Weapon_Kind][dynamic]Weapon_View_Group,
	effect_cube:   Render.Mesh,
	effect_sphere: Render.Mesh,
	mode:          Control_Mode,
	tab_was_down:  bool,
	flashlight_on: bool,
	binoculars:    bool,
	binocular_zoom: f32,
	aim:           f32, // 0 hip .. 1 aimed down the sights.
	aim_held:      bool, // Aiming forced on (for screenshots).
	binocular_raise: f32, // 0 down .. 1 fully up.
	binoculars_was_down: bool,
	map_open:      bool,
	map_was_down:  bool,
	flashlight_was_down: bool,
	demo:          bool,
	recoil:        f32,
	shots_seen:    u32,
}

terrain_height :: proc(data: rawptr, x, z: f32) -> f32 {
	return Procedural.Terrain_Height((^Procedural.Terrain)(data)^, x, z)
}

play_create :: proc(sandbox: ^Sandbox, demo: bool, fly: bool, drive: string, overlay: string, interactive: bool, resume: bool, variant: Mission.Variant) -> (ok: bool) {
	play := &sandbox.play
	play.sound = sound_create(interactive && !demo)
	base_height := sandbox.terrain.base_height_meters
	boxes := Base.Layout_Solids(sandbox.base.layout, base_height)
	defer delete(boxes)
	ground := World.Ground{height_at = terrain_height, data = sandbox.terrain}
	spawn := [3]f32{0, 0, 100}
	if demo do spawn = {0, 0, 52}
	spawn.y = terrain_height(sandbox.terrain, spawn.x, spawn.z)
	play.battle = Gameplay.Battle_Create(ground, boxes[:], spawn, 99)
	play.battle.collision.ladders = Base.Layout_Ladders(sandbox.base.layout, base_height)
	mission_create(play, sandbox, interactive && !demo && !fly, variant)
	cameras_create(play, sandbox)
	play.doors = Base.Layout_Doors(sandbox.base.layout, base_height)
	Base.Doors_Register(play.doors[:], &play.battle.collision)
	play.door_renderer = Base.Door_Renderer_Create(play.doors[:])
	vehicles_create(play, sandbox)
	spawn_garrison(&play.battle, sandbox.terrain, sandbox.base.layout)
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
	if drive != "" do board_named_vehicle(play, drive)
	play.map_open, play.binoculars = overlay == "map", overlay == "binoculars"
	play.autoplay = overlay == "autoplay"
	redirected := os.get_env("SENTINEL_SAVE_DIR", context.temp_allocator) != ""
	play.pause_enabled = interactive && !demo
	play.save_enabled = (interactive && !demo && !fly && drive == "" && overlay == "") || (redirected && overlay == "autoplay")
	if play.save_enabled {
		play.profile = profile_load()
		if resume && variant == .Rescue && play.profile.checkpoint.valid {
			checkpoint_apply_to_mission(play, play.profile.checkpoint)
			checkpoint_apply_to_player(play, play.profile.checkpoint)
			sync_camera_to_player(sandbox)
		}
	}
	if overlay == "pause" do play.paused = true
	if overlay == "ladder" && len(play.battle.collision.ladders) > 0 {
		ladder := play.battle.collision.ladders[0]
		outward := World.rotate_about_y({0, 0, 1}, ladder.yaw_radians)
		start := ladder.center + outward * 2.4
		play.battle.player.controller.position = {start.x, sandbox.terrain.base_height_meters, start.z}
		play.battle.player.yaw_radians = math.atan2(outward.x, outward.z)
		play.battle.player.pitch_radians = 0.25
		play.ladder_demo = true
		play.mission.state.status = .Active
		sync_camera_to_player(sandbox)
	}
	if overlay == "scope" {
		play.battle.player.current = .Sniper_Rifle
		play.aim = 1
		play.aim_held = true
	}
	if overlay == "smoke" do Gameplay.Battle_Detonate(&play.battle, {6, sandbox.terrain.base_height_meters, 88}, 6, 0) // A harmless blast in view, for checking smoke.
	play.binocular_zoom = BINOCULAR_ZOOM_START
	play.binocular_raise = 1 if play.binoculars else 0
	return true
}

play_destroy :: proc(play: ^Play) {
	sound_destroy(&play.sound)
	Particles_Destroy(&play.particles)
	cameras_destroy(play)
	mission_destroy(&play.mission)
	vehicles_destroy(play)
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
spawn_garrison :: proc(battle: ^Gameplay.Battle, terrain: ^Procedural.Terrain, layout: Base.Layout) {
	ground := terrain.base_height_meters
	at :: proc(x, y, z: f32) -> [3]f32 {
		return {x, y, z}
	}
	for x in ([2]f32{-6, 6}) do Gameplay.Battle_Add_Enemy(battle, .Guard, at(x, ground, 48), 0, nil)
	// A sniper up in each watchtower's lookout, watching the approach (the towers face outward).
	for placement in layout.placements {
		if placement.kind != .Watchtower do continue
		yaw := math.to_radians(placement.yaw_degrees)
		lookout := [3]f32{placement.x, ground, placement.z} + World.rotate_about_y({0.5, 6.25, -0.3}, yaw)
		Gameplay.Battle_Add_Enemy(battle, .Sniper, lookout, yaw, nil)
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
	mission_check_restart(play, input)
	if mission_pauses(play) {
		mission_check_start(play, input)
		return
	}
	fill_prop_solids(sandbox)
	tab_down := Platform.Input_Key_Down(input, .Tab)
	if tab_down && !play.tab_was_down do play.mode = .Fly if play.mode == .Play else .Play
	play.tab_was_down = tab_down
	interact_down := Platform.Input_Key_Down(input, .E)
	interact_pressed := interact_down && !play.interact_was_down
	was_driving := play.driving != nil
	play.interact_was_down = interact_down
	if play.mode == .Play && play.driving == nil do interact_on_foot(play, interact_pressed)
	Base.Doors_Update(play.doors[:], &play.battle.collision, delta_seconds)
	update_optics_keys(play, input, delta_seconds)
	update_aim(play, input, delta_seconds)
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
		if play.driving != nil {
			drive_vehicle(sandbox, input, interact_pressed && was_driving, delta_seconds) // The press that boarded must not also exit.
		} else {
			player_input := demo_input(play.battle, delta_seconds) if play.demo else collect_input(input)
			player_input.look *= binocular_look_scale(play)
			player_input.use = interact_pressed
			if play.ladder_demo do player_input.move = {0, 1}
			if play.binocular_raise > 0.5 do player_input.fire = false
			Gameplay.Battle_Update(&play.battle, player_input, delta_seconds)
			sync_camera_to_player(sandbox)
			animate_body(play, delta_seconds)
		}
	}
	update_vehicles(sandbox, delta_seconds)
	if play.mode == .Play {
		held, pressed := interact_down, interact_pressed
		if play.autoplay do held, pressed = autoplay_step(sandbox, delta_seconds)
		mission_update(sandbox, held, pressed, delta_seconds)
		cameras_update(sandbox, delta_seconds)
	}
	Particles_Spawn_From_Effects(&play.particles, play.battle.effects[:], delta_seconds, Gameplay.Player_Eye(play.battle.player))
	Particles_Update(&play.particles, delta_seconds)
	update_view_motion(play, delta_seconds)
	sound_update(sandbox, delta_seconds)
	save_update(play)
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
	update_vehicles(sandbox, delta_seconds)
}

// While nobody plays (fly camera, benchmark) the soldiers still think and shoot, but the idle player is kept alive.
@(private = "file")
battle_update_unattended :: proc(battle: ^Gameplay.Battle, delta_seconds: f32) {
	Gameplay.Health_Heal(&battle.player.health, battle.player.health.maximum)
	Gameplay.Battle_Update(battle, {}, delta_seconds)
}

sync_camera_to_player :: proc(sandbox: ^Sandbox) {
	player := sandbox.play.battle.player
	bob := math.sin(sandbox.play.bob_phase) * HEAD_BOB_METERS * sandbox.play.bob_strength
	if grip := player.controller.grip; grip.phase == .Climbing && abs(grip.speed) > 0.1 do bob += math.sin(grip.height / World.LADDER_RUNG_METERS * 2 * math.PI) * LADDER_BOB_METERS // One small dip per rung.
	sandbox.camera = Fly_Camera{position = Gameplay.Player_Eye(player) + {0, bob, 0}, yaw_radians = player.yaw_radians, pitch_radians = player.pitch_radians}
}

last_look_delta: [2]f32 // The latest frame's look input in radians (yaw left, pitch up), for the weapon's sway.

collect_input :: proc(input: ^Platform.Input) -> (result: Gameplay.Player_Input) {
	axis :: proc(input: ^Platform.Input, positive, negative: Platform.Key) -> f32 {
		return f32(int(Platform.Input_Key_Down(input, positive))) - f32(int(Platform.Input_Key_Down(input, negative)))
	}
	result.move = {axis(input, .D, .A), axis(input, .W, .S)}
	result.look = {-input.mouse_delta.x * MOUSE_RADIANS_PER_PIXEL, -input.mouse_delta.y * MOUSE_RADIANS_PER_PIXEL}
	result.fire = Platform.Input_Mouse_Down(input, .Left)
	last_look_delta = {result.look.x, result.look.y}
	result.reload = Platform.Input_Key_Down(input, .R)
	result.sprint = Platform.Input_Key_Down(input, .Left_Shift)
	result.crouch = Platform.Input_Key_Down(input, .C)
	result.jump = Platform.Input_Key_Down(input, .Space)
	result.respawn = Platform.Input_Key_Down(input, .Enter)
	keys := [6]Platform.Key{.Num_1, .Num_2, .Num_3, .Num_4, .Num_5, .Num_6}
	weapons := [6]Weapons.Weapon_Kind{.Rifle, .Pistol, .Sniper_Rifle, .Rocket_Launcher, .Grenade, .Silenced_Pistol}
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
	skip_text, _ := os.lookup_env("BISECT_CHAR", context.temp_allocator)
	skip, _ := strconv.parse_int(skip_text)
	for enemy, enemy_index in play.battle.enemies {
		if enemy_index == skip - 1 do continue
		append(&characters, enemy.character)
		if skip == 0 && enemy_index == 0 {}
	}
	body_shown := !Gameplay.Health_Is_Dead(play.battle.player.health) && play.driving == nil
	if body_shown do append(&characters, play.body)
	if false do if hostage, present := mission_hostage_character(play).?; present do append(&characters, hostage)
	for item in Characters.Character_Renderer_Items(&play.soldiers, characters[:]) {
		append(items, item)
		append(shadow_items, item)
	}
	for vehicle_item in Vehicles.Vehicle_Renderer_Items(&play.vehicle_renderer, play.vehicles[:]) {
		append(items, vehicle_item)
		append(shadow_items, vehicle_item)
	}
	for door_item in Base.Door_Renderer_Items(&play.door_renderer, play.doors[:]) {
		append(items, door_item)
		append(shadow_items, door_item)
	}
	for effect in play.battle.effects do add_effect(play, effect, items, &lights)
	Particles_Items(play, items)
	projectile_items(play, items, &lights)
	mission_items(play, items, &lights)
	pickups_items(play, items)
	cameras_items(play, items)
	if play.flashlight_on && play.mode == .Play {
		player := play.battle.player
		flashlight := Render.Light_Spot(Gameplay.Player_Eye(player) + Gameplay.Player_Forward(player) * 0.3, Gameplay.Player_Forward(player), {1, 0.95, 0.85}, FLASHLIGHT_INTENSITY, FLASHLIGHT_RANGE_METERS, 10, 24)
		flashlight.casts_shadow = true
		append(&lights, flashlight)
	}
	scoped := play.aim > 0.75 && play.battle.player.current == .Sniper_Rifle // Through the scope the rifle itself is out of view.
	if body_shown && !scoped && !play.battle.player.on_ladder do add_held_weapon(play, items)
	if play.battle.player.on_ladder do ladder_hand_items(play, items)
	return lights
}

@(private = "file")
add_effect :: proc(play: ^Play, effect: Gameplay.Effect, items: ^[dynamic]Render.Draw_Item, lights: ^[dynamic]Render.Light) {
	fade := 1 - effect.age / effect.lifetime
	switch effect.kind {
	case .Tracer:
		if effect.silenced do return
		// A real tracer is a short glowing streak flying along the bullet's path, not a beam joining gun and target: draw a few metres
		// of the path at the point the round has reached by now.
		start := effect.position
		if la.length(start - Gameplay.Player_Eye(play.battle.player)) < 2 do start += la.normalize0(effect.end - start) * TRACER_SKIP_METERS
		span := effect.end - start
		length := la.length(span)
		if length < 1e-3 || la.dot(span, effect.end - effect.position) <= 0 do return
		direction := span / length
		progress := clamp(effect.age / effect.lifetime, 0, 1) * length
		streak := min(TRACER_STREAK_METERS, length)
		head := min(progress + streak, length)
		tail := max(head - streak, 0)
		model := along_axis(start + direction * ((head + tail) / 2), direction) * la.matrix4_scale_f32({TRACER_THICKNESS_METERS, TRACER_THICKNESS_METERS, head - tail})
		append(items, effect_item(&play.effect_cube, model, [3]f32{4.5, 3.2, 1.2}))
	case .Muzzle_Flash:
		if effect.silenced do return // A suppressed shot has no flash.
		// The flame itself is fire particles (Particles.odin); the effect adds the light it throws on its surroundings.
		append(lights, Render.Light_Point(effect.position, {1, 0.8, 0.45}, 70 * fade, 14))
	case .Impact:
		append(items, effect_item(&play.effect_sphere, sphere_matrix(effect.position, 0.03 + 0.12 * (1 - fade)), [3]f32{5, 3.5, 1.5} * fade))
	case .Explosion:
		append(lights, Render.Light_Point(effect.position, {1, 0.55, 0.2}, 1100 * fade * fade, 42))
	}
}

@(private = "file")
effect_item :: proc(mesh: ^Render.Mesh, model: matrix[4, 4]f32, emission: [3]f32) -> Render.Draw_Item {
	return Render.Draw_Item{mesh = mesh, model = model, material_layer = i32(Materials.Surface_Material.Gunmetal), uv_scale = {1, 1}, illumination_model = .Lambert, emission = emission}
}

sphere_matrix :: proc(center: [3]f32, radius: f32) -> matrix[4, 4]f32 {
	return la.matrix4_translate_f32(center) * la.matrix4_scale_f32({radius, radius, radius})
}

// A frame at `origin` with +Z along `axis` and +Y as upright as possible.
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
	body.crouch = CROUCHED_BODY if player.controller.crouching else 0
	body.aim_direction = forward
	Characters.Character_Step(body, delta_seconds)
}

// The selected weapon sits in the body's right hand, exactly where a soldier would hold it, kicked back by the last shot.
@(private = "file")
add_held_weapon :: proc(play: ^Play, items: ^[dynamic]Render.Draw_Item) {
	player := play.battle.player
	pose := Characters.Character_Pose(play.body)
	recoil := la.matrix4_translate_f32(-Gameplay.Player_Forward(player) * play.recoil)
	forward_unit := Gameplay.Player_Forward(player)
	right_unit := la.normalize0(la.cross(forward_unit, [3]f32{0, 1, 0}))
	bob_offset := [3]f32{0, math.sin(play.bob_phase * 2) * 0.012 * play.bob_strength, 0}
	sway_offset := right_unit * play.sway.x + [3]f32{0, play.sway.y, 0}
	model := la.matrix4_translate_f32(bob_offset + sway_offset) * recoil * Characters.Weapon_Matrix(pose)
	for &group in play.view_weapons[player.current] {
		append(items, Render.Draw_Item{mesh = &group.mesh, model = model, material_layer = group.material, uv_scale = {2, 2}, illumination_model = .Cook_Torrance})
	}
}

play_camera :: proc(sandbox: ^Sandbox, aspect: f32) -> Render.Camera {
	if sandbox.play.mode == .Play {
		fov := Render.Zoomed_Field_Of_View_Degrees(PLAY_FIELD_OF_VIEW_DEGREES, binocular_current_zoom(&sandbox.play))
		return Render.Camera_Look_At(sandbox.camera.position, sandbox.camera.position + Fly_Camera_Forward(sandbox.camera), fov, aspect, PLAY_NEAR_PLANE_METERS, 1200)
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
	if play.mode == .Play && player.damage_flash > 0 do draw_damage_vignette(hud, w, h, player.damage_flash)
	if play.mode == .Play && !Gameplay.Health_Is_Dead(player.health) {
		if !(play.aim > 0.75 && player.current == .Sniper_Rifle) do draw_crosshair(hud, w / 2, h / 2, scale, player.hit_marker > 0)
		if play.driving == nil do draw_vitals(hud, player, w, h, scale)
		else do draw_vehicle_hud(play, w, h, scale)
	}
	living := 0
	for enemy in play.battle.enemies do if Gameplay.Enemy_Is_Alive(enemy) do living += 1
	Render.Hud_Text(hud, 16, 16, fmt.tprintf("KILLS %d   ENEMIES %d", player.kills, living), scale, {1, 1, 1, 0.9})
	if play.mode == .Fly do Render.Hud_Text(hud, w - 16 - Render.Hud_Text_Width("FLY MODE - TAB TO PLAY", scale), 16, "FLY MODE - TAB TO PLAY", scale, {1, 0.9, 0.3, 0.9})
	if _, can_board := play.boardable.?; play.mode == .Play && play.driving == nil && can_board && !Gameplay.Health_Is_Dead(player.health) do Render.Hud_Text(hud, (w - Render.Hud_Text_Width("E  ENTER VEHICLE", scale)) / 2, h * 0.62, "E  ENTER VEHICLE", scale, {1, 1, 1, 0.9})
	else if play.mode == .Play && play.door_in_reach && !Gameplay.Health_Is_Dead(player.health) do Render.Hud_Text(hud, (w - Render.Hud_Text_Width("E  OPEN / CLOSE", scale)) / 2, h * 0.62, "E  OPEN / CLOSE", scale, {1, 1, 1, 0.9})
	if play.mode == .Play && play.driving == nil && !Gameplay.Health_Is_Dead(player.health) {
		forward := Gameplay.Player_Forward(player)
		prompt := ""
		switch World.Ladder_Prompt_For(play.battle.collision, player.controller, {forward.x, forward.z}) {
		case .Climb_Up: prompt = "W / E  CLIMB LADDER"
		case .Climb_Down: prompt = "E  CLIMB DOWN"
		case .None:
			if player.on_ladder do prompt = "W UP   S DOWN   SPACE JUMP OFF"
		}
		if prompt != "" do Render.Hud_Text(hud, (w - Render.Hud_Text_Width(prompt, scale)) / 2, h * 0.68, prompt, scale, {1, 1, 1, 0.9})
	}
	if Gameplay.Health_Is_Dead(player.health) do draw_death_screen(hud, w, h, scale)
	cameras_draw_hud(play, w, scale)
	if player.pickup_flash > 0 do Render.Hud_Text(hud, (w - Render.Hud_Text_Width("PICKED UP", scale)) / 2, h * 0.7, "PICKED UP", scale, {0.7, 1, 0.7, min(player.pickup_flash, 1)})
	binoculars_draw_hud(play, w, h, scale)
	scope_draw_hud(play, w, h, scale)
	compass_draw_hud(play, w, scale)
	map_draw_hud(sandbox, w, h, scale)
	mission_draw_hud(play, w, h, scale)
	if play.paused do draw_pause_screen(play, w, h, scale)
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
interact_on_foot :: proc(play: ^Play, pressed: bool) {
	index, found := Base.Doors_Nearest(play.doors[:], play.battle.collision, play.battle.ground, Gameplay.Player_Eye(play.battle.player))
	play.door_in_reach = found
	play.boardable = nearest_boardable(play)
	forward := Gameplay.Player_Forward(play.battle.player)
	if World.Ladder_Prompt_For(play.battle.collision, play.battle.player.controller, {forward.x, forward.z}) != .None do return // E belongs to the ladder.
	if !pressed || play.mission.hostage_in_reach || play.mission.terminal_in_reach do return
	if _, boardable := play.boardable.?; boardable do board_vehicle(play)
	else if found {
		Base.Doors_Toggle(play.doors[:], index)
		door_sound(play, play.doors[index].hinge)
	}
}

// Head bob follows the stride (one up-down per step while walking on foot); the weapon lags a little behind turns and returns.
@(private = "file")
update_view_motion :: proc(play: ^Play, delta_seconds: f32) {
	player := play.battle.player
	speed := la.length([2]f32{player.controller.velocity.x, player.controller.velocity.z})
	grounded := player.controller.on_ground && play.driving == nil
	target: f32 = clamp(speed / 4, 0, 1.2) if grounded else 0
	play.bob_strength += (target - play.bob_strength) * min(1, 8 * delta_seconds)
	play.bob_phase += speed * BOB_STEPS_PER_METER * math.PI * delta_seconds * (1 if grounded else 0)
	play.sway *= math.exp(-SWAY_RETURN_PER_SECOND * delta_seconds)
	play.sway += last_look_delta * SWAY_METERS_PER_RADIAN * 0.35
	play.sway = {clamp(play.sway.x, -0.06, 0.06), clamp(play.sway.y, -0.05, 0.05)}
}

// Being hit darkens and reddens the screen edges (a ring of bands, strongest at the border) instead of tinting the whole view.
@(private = "file")
draw_damage_vignette :: proc(hud: ^Render.Hud, w, h, amount: f32) {
	BANDS :: 8
	for band in 0 ..< BANDS {
		inset := f32(band) * min(w, h) * 0.03
		thickness := min(w, h) * 0.03
		alpha := amount * 0.45 * (1 - f32(band) / BANDS)
		color := [4]f32{0.55, 0, 0, alpha}
		Render.Hud_Rect(hud, inset, inset, w - 2 * inset, thickness, color)
		Render.Hud_Rect(hud, inset, h - inset - thickness, w - 2 * inset, thickness, color)
		Render.Hud_Rect(hud, inset, inset + thickness, thickness, h - 2 * inset - 2 * thickness, color)
		Render.Hud_Rect(hud, w - inset - thickness, inset + thickness, thickness, h - 2 * inset - 2 * thickness, color)
	}
}

// Rockets and shells in flight: a dark body along the velocity with a glowing motor and a light; a grenade is a small olive ball. A rocket
// also leaves a smoke trail (one puff per frame, see Particles).
@(private = "file")
projectile_items :: proc(play: ^Play, items: ^[dynamic]Render.Draw_Item, lights: ^[dynamic]Render.Light) {
	for projectile in play.battle.projectiles {
		if projectile.kind == .Grenade {
			append(items, Render.Draw_Item{mesh = &play.effect_sphere, model = sphere_matrix(projectile.position, 0.05), material_layer = i32(Materials.Surface_Material.Olive_Paint), uv_scale = {1, 1}, illumination_model = .Cook_Torrance})
			continue
		}
		speed := la.length(projectile.velocity)
		if speed < 1e-3 do continue
		direction := projectile.velocity / speed
		body := along_axis(projectile.position, direction) * la.matrix4_scale_f32({0.05, 0.05, 0.55})
		append(items, Render.Draw_Item{mesh = &play.effect_cube, model = body, material_layer = i32(Materials.Surface_Material.Gunmetal), uv_scale = {1, 1}, illumination_model = .Cook_Torrance})
		flame := projectile.position - direction * 0.32
		append(lights, Render.Light_Point(flame, {1, 0.6, 0.25}, 60, 10))
		Particles_Trail(&play.particles, flame)
	}
}

// Escape pauses and resumes (the cursor is freed while paused); Q quits from the pause screen. Returns true while paused, so the
// caller skips the frame's simulation. Does nothing when the window is not interactive (captures, benchmarks).
play_handle_pause :: proc(sandbox: ^Sandbox, input: ^Platform.Input) -> bool {
	play := &sandbox.play
	if !play.pause_enabled do return false
	escape_down := Platform.Input_Key_Down(input, .Escape)
	if escape_down && !play.escape_was_down {
		play.paused = !play.paused
		Platform.Input_Capture_Mouse(input, !play.paused)
		play.sound_muted = play.paused
		if play.sound.device != nil do play.sound.device.mixer.master = 0 if play.paused else 0.8
	}
	play.escape_was_down = escape_down
	if play.paused && Platform.Input_Key_Down(input, .Q) do play.quit_requested = true
	return play.paused
}

draw_pause_screen :: proc(play: ^Play, width, height, scale: f32) {
	hud := &play.hud
	Render.Hud_Rect(hud, 0, 0, width, height, {0, 0, 0, 0.65})
	title := "PAUSED"
	Render.Hud_Text(hud, (width - Render.Hud_Text_Width(title, scale * 3)) / 2, height * 0.34, title, scale * 3, {1, 0.9, 0.4, 1})
	lines := [?]string{"ESC  RESUME", "F11  FULLSCREEN", "Q  QUIT"}
	y := height * 0.5
	for line in lines {
		Render.Hud_Text(hud, (width - Render.Hud_Text_Width(line, scale * 1.4)) / 2, y, line, scale * 1.4, {1, 1, 1, 0.95})
		y += 14 * scale * 1.4
	}
}
