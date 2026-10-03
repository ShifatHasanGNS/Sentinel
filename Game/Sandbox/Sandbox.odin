package Sandbox

import "../../Engine/Platform"
import "../../Engine/Procedural"
import "../../Engine/Render"
import World "../../Engine/World"
import "../Base"
import "../Gameplay"
import "../Materials"
import "core:fmt"
import "core:math"
import la "core:math/linalg"

BASE_SEED :: 5
LOAD_RADIUS_CHUNKS :: 4
UNLOAD_RADIUS_CHUNKS :: 6
CHUNK_BUILDS_PER_FRAME_MAX :: 1
PROP_SHADOW_KEEP_METERS :: 60.0
BLOOM_STRENGTH :: 0.06
SHAFT_STRENGTH :: 0.2
SSAO_RADIUS_METERS :: 0.8
SHADOW_DISTANCE_METERS :: 100.0
HOURS_PER_REAL_SECOND :: 0.02 // A full day passes in twenty minutes.
FIELD_OF_VIEW_DEGREES :: 65.0
SCRIPTED_FLIGHT_RADIUS_METERS :: 380.0
SCRIPTED_FLIGHT_SPEED :: 30.0

// An open world of streamed terrain with scattered trees, rocks and bushes under a day/night cycle.
Sandbox :: struct {
	renderer:       Render.Renderer,
	materials:      Procedural.Texture_Set,
	terrain:        ^Procedural.Terrain, // On the heap: the battle's ground function points at it.
	scatter_rules:  Procedural.Scatter_Rules,
	grass_rules:    Procedural.Scatter_Rules,
	grass_instances: [dynamic]Render.Instance,
	props:          Props,
	base:           Base.Base_Scene,
	play:           Play,
	chunks:         map[World.Chunk_Coordinate]Chunk,
	stream:         World.Chunk_Stream,
	build_queue:    [dynamic]World.Chunk_Coordinate,
	to_load:        [dynamic]World.Chunk_Coordinate,
	to_unload:      [dynamic]World.Chunk_Coordinate,
	camera:         Fly_Camera,
	hours:          f32,
	clock_runs:     bool,
	trunk_instances:  [dynamic]Render.Instance,
	canopy_instances: [dynamic]Render.Instance,
	far_trunk_instances:  [dynamic]Render.Instance,
	far_canopy_instances: [dynamic]Render.Instance,
	rock_instances:   [dynamic]Render.Instance,
	bush_instances:   [dynamic]Render.Instance,
}

// hours < 0 starts the day cycle at 9:00 and lets it run; otherwise time is fixed at the given hour.
Sandbox_Create :: proc(width, height: i32, hours: f32, view: string, demo: bool, drive: string, overlay: string, interactive: bool) -> (sandbox: Sandbox, ok: bool) {
	sandbox.renderer = Render.Renderer_Create(width, height) or_return
	sandbox.materials = Materials.Materials_Bake() or_return
	sandbox.terrain = new(Procedural.Terrain)
	sandbox.terrain^ = Procedural.Terrain{
		seed = 7,
		base_height_meters = 10,
		amplitude_meters = 30,
		frequency_per_meter = 1.0 / 180,
		octaves = 5,
		plateau_radius_meters = 90,
		plateau_blend_meters = 55,
	}
	sandbox.grass_rules = Procedural.Scatter_Rules{seed = 8, attempts_per_chunk = 1400, min_normal_y = 0.88, exclusion_radius_meters = 92, scale_range = {0.7, 1.4}}
	sandbox.scatter_rules = Procedural.Scatter_Rules{seed = 3, attempts_per_chunk = 120, min_normal_y = 0.93, exclusion_radius_meters = 105, scale_range = {0.8, 1.5}}
	sandbox.props = Props_Create()
	sandbox.base = Base.Base_Scene_Create(Base.Layout_Create(BASE_SEED, sandbox.terrain.plateau_radius_meters), sandbox.terrain.base_height_meters)
	sandbox.camera = camera_for_view(view)
	sandbox.clock_runs = hours < 0
	sandbox.hours = 9 if hours < 0 else hours
	if view == "sun" do sandbox.camera = camera_facing_sun(sandbox.hours)
	play_create(&sandbox, demo, view != "", drive, overlay, interactive) or_return
	if !(view != "") do sync_camera_to_player(&sandbox)
	update_stream(&sandbox)
	for len(sandbox.build_queue) > 0 do build_next_chunk(&sandbox)
	return sandbox, true
}

Sandbox_Destroy :: proc(sandbox: ^Sandbox) {
	for _, &chunk in sandbox.chunks do Chunk_Destroy(&chunk)
	delete(sandbox.chunks)
	World.Chunk_Stream_Destroy(&sandbox.stream)
	delete(sandbox.build_queue)
	delete(sandbox.to_load)
	delete(sandbox.to_unload)
	delete(sandbox.trunk_instances)
	delete(sandbox.canopy_instances)
	delete(sandbox.far_trunk_instances)
	delete(sandbox.far_canopy_instances)
	delete(sandbox.rock_instances)
	delete(sandbox.bush_instances)
	delete(sandbox.grass_instances)
	play_destroy(&sandbox.play)
	Base.Base_Scene_Destroy(&sandbox.base)
	Props_Destroy(&sandbox.props)
	free(sandbox.terrain)
	Procedural.Texture_Set_Destroy(&sandbox.materials)
	Render.Renderer_Destroy(&sandbox.renderer)
}

// scripted_seconds >= 0 flies a fixed circuit (for repeatable benchmarks); otherwise the player plays, or flies (Tab).
Sandbox_Update :: proc(sandbox: ^Sandbox, clock: Platform.Clock, input: ^Platform.Input, scripted_seconds: f32) {
	if scripted_seconds >= 0 {
		sandbox.camera = scripted_camera(sandbox.terrain^, scripted_seconds)
		play_update_idle(sandbox, clock.delta_seconds)
	} else {
		play_update(sandbox, input, clock.delta_seconds)
	}
	if sandbox.clock_runs do sandbox.hours = math.mod(sandbox.hours + HOURS_PER_REAL_SECOND * clock.delta_seconds, 24)
	update_stream(sandbox)
	for _ in 0 ..< CHUNK_BUILDS_PER_FRAME_MAX {
		if len(sandbox.build_queue) == 0 do break
		build_next_chunk(sandbox)
	}
}

Sandbox_Render :: proc(sandbox: ^Sandbox, window: Platform.Window) {
	aspect := f32(window.framebuffer_width) / f32(window.framebuffer_height)
	camera := play_camera(sandbox, aspect)
	items, shadow_items := gather_items(sandbox, camera)
	lights := play_items(sandbox, &items, &shadow_items)
	darkness := clamp((0.08 - Gameplay.Sun_Direction_To_Sun(sandbox.hours).y) / 0.2, 0, 1)
	for light in Base.Layout_Night_Lights(sandbox.base.layout, sandbox.terrain.base_height_meters, darkness) do append(&lights, light)
	for light in Base.Layout_Interior_Lights(sandbox.base.layout, sandbox.terrain.base_height_meters) do append(&lights, light)
	daylight := Gameplay.Daylight_For_Hours(sandbox.hours)
	frame := Render.Frame{
		camera = camera,
		items = items[:],
		shadow_items = shadow_items[:],
		terrain_shading = Render.Terrain_Shading{
			grass_layer = i32(Materials.Surface_Material.Grass),
			dirt_layer = i32(Materials.Surface_Material.Dirt),
			rock_layer = i32(Materials.Surface_Material.Rock),
			sand_layer = i32(Materials.Surface_Material.Sand),
			plateau_center = sandbox.terrain.plateau_center,
			plateau_radius_meters = sandbox.terrain.plateau_radius_meters,
			plateau_blend_meters = sandbox.terrain.plateau_blend_meters,
		},
		sun = daylight.sun,
		ground_level_meters = sandbox.terrain.base_height_meters,
		local_lights = lights[:],
		interiors = Base.Layout_Interiors(sandbox.base.layout, sandbox.terrain.base_height_meters)[:],
		sky = daylight.sky,
		bloom_strength = BLOOM_STRENGTH,
		shaft_strength = SHAFT_STRENGTH,
		ssao_radius_meters = SSAO_RADIUS_METERS,
		sun_shadows = true,
		shadow_distance_meters = SHADOW_DISTANCE_METERS,
		materials = &sandbox.materials,
		exposure = daylight.exposure,
		vignette_strength = 0.3,
	}
	Render.Renderer_Render(&sandbox.renderer, frame, window.framebuffer_width, window.framebuffer_height)
	play_draw_hud(sandbox, window.framebuffer_width, window.framebuffer_height)
}

// Named starting points: the default overview, an aerial of the compound, the gate from the road, the motor pool, the airfield.
@(private = "file")
camera_for_view :: proc(view: string) -> Fly_Camera {
	switch view {
	case "base": return Fly_Camera_Looking_At({-75, 42, 100}, {0, 10, -5})
	case "gate": return Fly_Camera_Looking_At({0, 14, 100}, {0, 12, 40})
	case "yard": return Fly_Camera_Looking_At({-34, 16, 70}, {14, 11, 44})
	case "airfield": return Fly_Camera_Looking_At({60, 26, 50}, {32, 11, -4})
	case "player": return Fly_Camera_Looking_At({4, 12.4, 107}, {0, 11.2, 100})
	case "hq": return Fly_Camera_Looking_At({-6, 11.7, 14}, {0, 12.0, -1})
	case "inside": return Fly_Camera_Looking_At({3, 11.75, -2.6}, {-3.5, 11.2, -10})
	case "barracks": return Fly_Camera_Looking_At({-31, 11.7, -4}, {-44, 11.5, -2})
	case "camera": return Fly_Camera_Looking_At({-30, 15.5, 33}, {-43.8, 16, 43.8})
	case "field": return Fly_Camera_Looking_At({10, 9, 215}, {10, 5, 190})
	case "tower": return Fly_Camera_Looking_At({-36, 16, 58}, {-43.8, 16, 43.8})
	case "command": return Fly_Camera_Looking_At({-20, 24, 62}, {-8, 11, -12})
	}
	return Fly_Camera{position = {-150, 45, 190}, yaw_radians = -0.67, pitch_radians = -0.15}
}

// Looks toward the sun from inside the base, with the sun in the upper part of the frame (for checking glare and light shafts).
@(private = "file")
camera_facing_sun :: proc(hours: f32) -> Fly_Camera {
	position := [3]f32{0, 12, 40}
	to_sun := Gameplay.Sun_Direction_To_Sun(hours)
	return Fly_Camera_Looking_At(position, position + to_sun * 100 - {0, to_sun.y * 60, 0})
}

@(private = "file")
update_stream :: proc(sandbox: ^Sandbox) {
	position := sandbox.camera.position
	World.Chunk_Stream_Update(&sandbox.stream, position.x, position.z, CHUNK_SIZE_METERS, LOAD_RADIUS_CHUNKS, UNLOAD_RADIUS_CHUNKS, &sandbox.to_load, &sandbox.to_unload)
	for coordinate in sandbox.to_load do append(&sandbox.build_queue, coordinate)
	for coordinate in sandbox.to_unload {
		if chunk, built := &sandbox.chunks[coordinate]; built {
			Chunk_Destroy(chunk)
			delete_key(&sandbox.chunks, coordinate)
		}
		if queued_index, queued := find_queued(sandbox.build_queue[:], coordinate); queued do ordered_remove(&sandbox.build_queue, queued_index)
	}
}

@(private = "file")
find_queued :: proc(queue: []World.Chunk_Coordinate, coordinate: World.Chunk_Coordinate) -> (index: int, found: bool) {
	for queued, queued_index in queue {
		if queued == coordinate do return queued_index, true
	}
	return 0, false
}

@(private = "file")
build_next_chunk :: proc(sandbox: ^Sandbox) {
	coordinate := sandbox.build_queue[0]
	ordered_remove(&sandbox.build_queue, 0)
	sandbox.chunks[coordinate] = Chunk_Build(sandbox.terrain^, sandbox.scatter_rules, sandbox.grass_rules, coordinate)
}

// Terrain chunks in view are drawn; every loaded chunk and every prop casts shadows, so trees behind the camera still shade the scene.
@(private = "file")
gather_items :: proc(sandbox: ^Sandbox, camera: Render.Camera) -> (items, shadow_items: [dynamic]Render.Draw_Item) {
	items = make([dynamic]Render.Draw_Item, context.temp_allocator)
	shadow_items = make([dynamic]Render.Draw_Item, context.temp_allocator)
	frustum := Render.Frustum_From_View_Projection(camera.view_projection)
	for _, &chunk in sandbox.chunks {
		item := terrain_item(&chunk)
		append(&shadow_items, item)
		if Render.Frustum_Intersects_Aabb(frustum, chunk.lowest, chunk.highest) do append(&items, item)
	}
	collect_instances(sandbox, frustum, camera.position)
	for prop_item in prop_items(sandbox) do append(&items, prop_item)
	night_amount := clamp((0.08 - Gameplay.Sun_Direction_To_Sun(sandbox.hours).y) / 0.2, 0, 1)
	for base_item in Base.Base_Scene_Items(&sandbox.base, night_amount) do append(&items, base_item)
	for shadow_item in Base.Base_Scene_Shadow_Items(&sandbox.base) do append(&shadow_items, shadow_item)
	for proxy_item in shadow_proxy_items(sandbox) do append(&shadow_items, proxy_item)
	return
}

@(private = "file")
terrain_item :: proc(chunk: ^Chunk) -> Render.Draw_Item {
	return Render.Draw_Item{mesh = &chunk.mesh, model = la.MATRIX4F32_IDENTITY, uv_scale = {1, 1}, illumination_model = .Cook_Torrance, terrain = true, bounds = Render.Bounds{chunk.lowest, chunk.highest}}
}

@(private = "file")
prop_items :: proc(sandbox: ^Sandbox) -> [7]Render.Draw_Item {
	prop :: proc(mesh: ^Render.Mesh) -> Render.Draw_Item {
		return Render.Draw_Item{mesh = mesh, model = la.MATRIX4F32_IDENTITY, uv_scale = {1, 1}, triplanar = true, illumination_model = .Cook_Torrance}
	}
	return {prop(&sandbox.props.tree_trunk), prop(&sandbox.props.tree_canopy), prop(&sandbox.props.rock), prop(&sandbox.props.bush), prop(&sandbox.props.grass), prop(&sandbox.props.tree_far_trunk), prop(&sandbox.props.tree_far_canopy)}
}

@(private = "file")
shadow_proxy_items :: proc(sandbox: ^Sandbox) -> [4]Render.Draw_Item {
	proxy :: proc(mesh: ^Render.Mesh) -> Render.Draw_Item {
		return Render.Draw_Item{mesh = mesh, model = la.MATRIX4F32_IDENTITY}
	}
	return {proxy(&sandbox.props.tree_trunk_shadow), proxy(&sandbox.props.tree_canopy_shadow), proxy(&sandbox.props.rock_shadow), proxy(&sandbox.props.bush_shadow)}
}

@(private = "file")
// Props are instanced from every chunk that can matter this frame: chunks in view, plus chunks near enough to cast a shadow into view.
// Chunks that are both behind the camera and beyond the shadow distance cost nothing.
collect_instances :: proc(sandbox: ^Sandbox, frustum: Render.Frustum, camera_position: [3]f32) {
	clear(&sandbox.trunk_instances)
	clear(&sandbox.canopy_instances)
	clear(&sandbox.far_trunk_instances)
	clear(&sandbox.far_canopy_instances)
	clear(&sandbox.rock_instances)
	clear(&sandbox.bush_instances)
	clear(&sandbox.grass_instances)
	for _, &chunk in sandbox.chunks {
		if chunk_matters(chunk, frustum, camera_position) do for point in chunk.scatter do if prop_is_needed(point, frustum, camera_position) do place_prop(sandbox, point, camera_position)
		if Render.Frustum_Intersects_Aabb(frustum, chunk.lowest, chunk.highest) do for point in chunk.grass do place_grass(sandbox, point, camera_position)
	}
	Render.Mesh_Set_Instances(&sandbox.props.tree_trunk, sandbox.trunk_instances[:min(len(sandbox.trunk_instances), TREE_CAPACITY)])
	Render.Mesh_Set_Instances(&sandbox.props.tree_canopy, sandbox.canopy_instances[:min(len(sandbox.canopy_instances), TREE_CAPACITY)])
	Render.Mesh_Set_Instances(&sandbox.props.tree_far_trunk, sandbox.far_trunk_instances[:min(len(sandbox.far_trunk_instances), TREE_CAPACITY)])
	Render.Mesh_Set_Instances(&sandbox.props.tree_far_canopy, sandbox.far_canopy_instances[:min(len(sandbox.far_canopy_instances), TREE_CAPACITY)])
	Render.Mesh_Set_Instances(&sandbox.props.rock, sandbox.rock_instances[:min(len(sandbox.rock_instances), ROCK_CAPACITY)])
	Render.Mesh_Set_Instances(&sandbox.props.bush, sandbox.bush_instances[:min(len(sandbox.bush_instances), BUSH_CAPACITY)])
	Render.Mesh_Set_Instances(&sandbox.props.grass, sandbox.grass_instances[:min(len(sandbox.grass_instances), GRASS_CAPACITY)])
}

@(private = "file")
chunk_matters :: proc(chunk: Chunk, frustum: Render.Frustum, camera_position: [3]f32) -> bool {
	if Render.Frustum_Intersects_Aabb(frustum, chunk.lowest, chunk.highest) do return true
	nearest := [3]f32{clamp(camera_position.x, chunk.lowest.x, chunk.highest.x), clamp(camera_position.y, chunk.lowest.y, chunk.highest.y), clamp(camera_position.z, chunk.lowest.z, chunk.highest.z)}
	return la.length(nearest - camera_position) < SHADOW_DISTANCE_METERS
}

@(private = "file")
place_grass :: proc(sandbox: ^Sandbox, point: Procedural.Scatter_Point, camera_position: [3]f32) {
	offset := point.position - camera_position
	if offset.x * offset.x + offset.z * offset.z > GRASS_DRAW_DISTANCE_METERS * GRASS_DRAW_DISTANCE_METERS do return
	model := la.matrix4_translate_f32(point.position) * la.matrix4_rotate_f32(point.yaw_radians, {0, 1, 0}) * la.matrix4_scale_f32({point.scale, point.scale, point.scale})
	append(&sandbox.grass_instances, Render.Instance{model = model, material_layer = f32(Materials.Surface_Material.Grass)})
}

// Per-instance culling: a prop is kept when it is in view, or close enough that its shadow may fall into view (a 6 m tree at a low sun
// casts about 25 m, so 60 m is generous). Everything else is dropped before it costs a vertex.
@(private = "file")
prop_is_needed :: proc(point: Procedural.Scatter_Point, frustum: Render.Frustum, camera_position: [3]f32) -> bool {
	radius := 4 * point.scale if point.variant < TREE_VARIANT_LIMIT else 1.5 * point.scale
	if Render.Frustum_Intersects_Sphere(frustum, point.position + {0, radius * 0.6, 0}, radius) do return true
	offset := point.position - camera_position
	return offset.x * offset.x + offset.z * offset.z < PROP_SHADOW_KEEP_METERS * PROP_SHADOW_KEEP_METERS
}

@(private = "file")
place_prop :: proc(sandbox: ^Sandbox, point: Procedural.Scatter_Point, camera_position: [3]f32) {
	model := la.matrix4_translate_f32(point.position) * la.matrix4_rotate_f32(point.yaw_radians, {0, 1, 0}) * la.matrix4_scale_f32({point.scale, point.scale, point.scale})
	switch {
	case point.variant < TREE_VARIANT_LIMIT && la.length(point.position - camera_position) > TREE_DETAIL_DISTANCE_METERS:
		append(&sandbox.far_trunk_instances, Render.Instance{model = model, material_layer = f32(Materials.Surface_Material.Dirt)})
		append(&sandbox.far_canopy_instances, Render.Instance{model = model, material_layer = f32(Materials.Surface_Material.Grass)})
	case point.variant < TREE_VARIANT_LIMIT:
		append(&sandbox.trunk_instances, Render.Instance{model = model, material_layer = f32(Materials.Surface_Material.Dirt)})
		append(&sandbox.canopy_instances, Render.Instance{model = model, material_layer = f32(Materials.Surface_Material.Grass)})
	case point.variant < ROCK_VARIANT_LIMIT:
		append(&sandbox.rock_instances, Render.Instance{model = model, material_layer = f32(Materials.Surface_Material.Rock)})
	case:
		append(&sandbox.bush_instances, Render.Instance{model = model, material_layer = f32(Materials.Surface_Material.Grass)})
	}
}

// A circle around the base at constant speed, 35 m above the ground, looking along the direction of travel and slightly down.
@(private = "file")
scripted_camera :: proc(terrain: Procedural.Terrain, seconds: f32) -> Fly_Camera {
	angle := seconds * SCRIPTED_FLIGHT_SPEED / SCRIPTED_FLIGHT_RADIUS_METERS
	x, z := math.cos(angle) * SCRIPTED_FLIGHT_RADIUS_METERS, math.sin(angle) * SCRIPTED_FLIGHT_RADIUS_METERS
	height := Procedural.Terrain_Height(terrain, x, z) + 35
	heading := la.normalize([3]f32{-math.sin(angle), -0.15, math.cos(angle)})
	return Fly_Camera{position = {x, height, z}, yaw_radians = math.atan2(-heading.x, -heading.z), pitch_radians = math.asin(heading.y)}
}

// Prints the average GPU time of each renderer pass.
Sandbox_Report :: proc(sandbox: ^Sandbox) {
	milliseconds := Render.Renderer_Pass_Milliseconds(&sandbox.renderer)
	total: f32
	for pass in Render.Render_Pass {
		fmt.printfln("  %-18v %6.2f ms", pass, milliseconds[pass])
		total += milliseconds[pass]
	}
	fmt.printfln("  %-18s %6.2f ms", "GPU total", total)
}

Sandbox_Restart_Requested :: proc(sandbox: ^Sandbox) -> bool {
	return sandbox.play.restart_requested
}
