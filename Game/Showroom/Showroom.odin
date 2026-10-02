package Showroom

import "../../Engine/GPU"
import "../../Engine/Platform"
import "../../Engine/Procedural"
import "../../Engine/Render"
import "../Gameplay"
import "../Materials"
import "core:math"
import la "core:math/linalg"
import gl "vendor:OpenGL"

GROUND_HALF_EXTENT_METERS :: 40
GROUND_TILES :: 40
BULB_RADIUS_METERS :: 0.18

Showroom :: struct {
	renderer:             Render.Renderer,
	materials:            Procedural.Texture_Set,
	gallery:              [dynamic]Gallery_Item,
	ground:               Gallery_Item,
	bulb:                 Render.Mesh,
	local_lights:         [dynamic]Render.Light,
	camera_angle_radians: f32,
}

Showroom_Create :: proc(width, height: i32) -> (showroom: Showroom, ok: bool) {
	showroom.renderer = Render.Renderer_Create(width, height) or_return
	showroom.materials = Materials.Materials_Bake() or_return
	showroom.gallery = Gallery_Create()
	showroom.ground = create_ground()
	showroom.bulb = create_bulb()
	showroom.local_lights = create_lights()
	return showroom, true
}

Showroom_Update :: proc(showroom: ^Showroom, clock: Platform.Clock) {
	showroom.camera_angle_radians += clock.delta_seconds * 0.15
}

Showroom_Render :: proc(showroom: ^Showroom, window: Platform.Window) {
	items := make([dynamic]Render.Draw_Item, context.temp_allocator)
	append(&items, as_draw_item(&showroom.ground))
	for &item in showroom.gallery do append(&items, as_draw_item(&item))
	for light in showroom.local_lights do append(&items, bulb_draw_item(showroom, light))
	daylight := Gameplay.Daylight_For_Hours(17.3)
	frame := Render.Frame{
		camera = camera(showroom, window),
		items = items[:],
		sun = daylight.sun,
		local_lights = showroom.local_lights[:],
		sky = daylight.sky,
		materials = &showroom.materials,
		sun_shadows = true,
		shadow_distance_meters = 70,
		exposure = 1,
		vignette_strength = 0.35,
	}
	Render.Renderer_Render(&showroom.renderer, frame, window.framebuffer_width, window.framebuffer_height)
}

Showroom_Destroy :: proc(showroom: ^Showroom) {
	Render.Mesh_Destroy(&showroom.bulb)
	delete(showroom.local_lights)
	Render.Mesh_Destroy(&showroom.ground.mesh)
	Gallery_Destroy(&showroom.gallery)
	Procedural.Texture_Set_Destroy(&showroom.materials)
	Render.Renderer_Destroy(&showroom.renderer)
	GPU.Sampler_Cache_Destroy()
}

// One of every local light type, placed over the gallery.
@(private = "file")
create_lights :: proc() -> (lights: [dynamic]Render.Light) {
	append(&lights, Render.Light_Point({-9, 1.6, 5}, {1, 0.45, 0.15}, 60, 12))
	append(&lights, Render.Light_Point({9, 1.6, 5}, {0.2, 0.5, 1}, 60, 12))
	append(&lights, Render.Light_Spot({0, 7, 12}, {0, -1, -0.25}, {1, 0.95, 0.85}, 400, 22, 14, 26))
	append(&lights, Render.Light_Area({0, 3.2, 3.5}, {0, -1, 0}, {1, 1, 1}, 4, 1.2, 160, 14))
	return lights
}

@(private = "file")
as_draw_item :: proc(item: ^Gallery_Item) -> Render.Draw_Item {
	return Render.Draw_Item{&item.mesh, item.model, i32(item.material), item.uv_scale, item.triplanar, item.illumination_model, {}}
}

// A small emissive sphere marking each local light's position.
@(private = "file")
bulb_draw_item :: proc(showroom: ^Showroom, light: Render.Light) -> Render.Draw_Item {
	model := la.matrix4_translate_f32(light.position) * la.matrix4_scale_f32({BULB_RADIUS_METERS, BULB_RADIUS_METERS, BULB_RADIUS_METERS})
	return Render.Draw_Item{&showroom.bulb, model, i32(Materials.Surface_Material.Concrete), {1, 1}, false, .Lambert, light.color * 6}
}

@(private = "file")
camera :: proc(showroom: ^Showroom, window: Platform.Window) -> Render.Camera {
	aspect := f32(window.framebuffer_width) / f32(window.framebuffer_height)
	target := [3]f32{0, 1, 5}
	eye := target + {19 * math.sin(showroom.camera_angle_radians), 7, 19 * math.cos(showroom.camera_angle_radians)}
	return Render.Camera_Look_At(eye, target, 60, aspect, 0.1, 200)
}

@(private = "file")
create_bulb :: proc() -> Render.Mesh {
	sphere := Procedural.Sphere_Create(1, 16, 8)
	defer Procedural.Mesh_Destroy(&sphere)
	return Render.Mesh_Upload(sphere)
}

// A thin slab whose top face is the floor; its [0,1] uv is scaled to tile the dirt material across it.
@(private = "file")
create_ground :: proc() -> Gallery_Item {
	slab := Procedural.Box_Create({2 * GROUND_HALF_EXTENT_METERS, 0.2, 2 * GROUND_HALF_EXTENT_METERS})
	defer Procedural.Mesh_Destroy(&slab)
	return Gallery_Item{Render.Mesh_Upload(slab), la.matrix4_translate_f32({0, -0.1, 0}), .Dirt, {GROUND_TILES, GROUND_TILES}, false, .Cook_Torrance}
}
