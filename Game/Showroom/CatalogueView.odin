package Showroom

import "../../Engine/Platform"
import "../../Engine/Procedural"
import "../../Engine/Render"
import "../Catalogue"
import "../Gameplay"
import "../Materials"
import "core:math"
import la "core:math/linalg"

CATALOGUE_GRID_SPACING_METERS :: 32.0
CATALOGUE_GRID_COLUMNS :: 6

View_Group :: struct {
	mesh:     Render.Mesh,
	material: i32,
	emission: [3]f32,
}

View_Object :: struct {
	groups:   [dynamic]View_Group,
	position: [3]f32, // Where its origin stands.
	center:   [3]f32, // Middle of its bounds, in world space.
	extent:   f32, // Largest dimension.
}

// Every catalogue object on a grid, or a single one filled by the camera, for inspecting the models.
Catalogue_View :: struct {
	renderer:             Render.Renderer,
	materials:            Procedural.Texture_Set,
	ground:               Gallery_Item,
	objects:              [dynamic]View_Object,
	focus:                bool,
	camera_angle_radians: f32,
	hours:                f32,
}

// focus_kind < 0 shows the whole grid; otherwise only that Object_Kind.
Catalogue_View_Create :: proc(width, height: i32, focus_name: string, hours: f32) -> (view: Catalogue_View, ok: bool) {
	view.renderer = Render.Renderer_Create(width, height) or_return
	view.materials = Materials.Materials_Bake() or_return
	view.ground = create_ground(300, 150)
	view.hours = 11.5 if hours < 0 else hours
	kinds := make([dynamic]Catalogue.Object_Kind, context.temp_allocator)
	for kind in Catalogue.Object_Kind {
		if focus_name == "" || Catalogue.Object_Name_Matches(kind, focus_name) do append(&kinds, kind)
	}
	view.focus = focus_name != "" && len(kinds) == 1
	for kind, index in kinds {
		column, row := index % CATALOGUE_GRID_COLUMNS, index / CATALOGUE_GRID_COLUMNS
		position := [3]f32{f32(column) * CATALOGUE_GRID_SPACING_METERS, 0, f32(row) * CATALOGUE_GRID_SPACING_METERS}
		if view.focus do position = {}
		append(&view.objects, upload_object(kind, position))
	}
	return view, len(view.objects) > 0
}

Catalogue_View_Update :: proc(view: ^Catalogue_View, clock: Platform.Clock) {
	view.camera_angle_radians += clock.delta_seconds * 0.2
}

Catalogue_View_Render :: proc(view: ^Catalogue_View, window: Platform.Window) {
	items := make([dynamic]Render.Draw_Item, context.temp_allocator)
	append(&items, as_draw_item(&view.ground))
	for &object in view.objects {
		for &group in object.groups {
			append(&items, Render.Draw_Item{mesh = &group.mesh, model = la.matrix4_translate_f32(object.position), material_layer = group.material, uv_scale = {2, 2}, triplanar = true, illumination_model = .Cook_Torrance, emission = group.emission})
		}
	}
	daylight := Gameplay.Daylight_For_Hours(view.hours)
	frame := Render.Frame{
		camera = catalogue_camera(view, window),
		items = items[:],
		sun = daylight.sun,
		sky = daylight.sky,
		sun_shadows = true,
		shadow_distance_meters = 200,
		materials = &view.materials,
		exposure = daylight.exposure,
		vignette_strength = 0.3,
	}
	Render.Renderer_Render(&view.renderer, frame, window.framebuffer_width, window.framebuffer_height)
}

Catalogue_View_Destroy :: proc(view: ^Catalogue_View) {
	for &object in view.objects {
		for &group in object.groups do Render.Mesh_Destroy(&group.mesh)
		delete(object.groups)
	}
	delete(view.objects)
	Render.Mesh_Destroy(&view.ground.mesh)
	Procedural.Texture_Set_Destroy(&view.materials)
	Render.Renderer_Destroy(&view.renderer)
}

@(private = "file")
upload_object :: proc(kind: Catalogue.Object_Kind, position: [3]f32) -> (object: View_Object) {
	assembly := Catalogue.Catalogue_Build(kind)
	defer Procedural.Assembly_Destroy(&assembly)
	lowest, highest := Procedural.Assembly_Bounds(assembly)
	object.position = position
	object.center = position + (lowest + highest) / 2
	size := highest - lowest
	object.extent = max(size.x, max(size.y, size.z))
	for group in assembly.groups {
		append(&object.groups, View_Group{Render.Mesh_Upload(group.mesh), group.material, group.emission})
	}
	return object
}

@(private = "file")
catalogue_camera :: proc(view: ^Catalogue_View, window: Platform.Window) -> Render.Camera {
	aspect := f32(window.framebuffer_width) / f32(window.framebuffer_height)
	target: [3]f32
	distance: f32
	if view.focus {
		target = view.objects[0].center
		distance = view.objects[0].extent * 1.7
	} else {
		columns := f32(min(len(view.objects), CATALOGUE_GRID_COLUMNS))
		rows := f32((len(view.objects) + CATALOGUE_GRID_COLUMNS - 1) / CATALOGUE_GRID_COLUMNS)
		target = {(columns - 1) * CATALOGUE_GRID_SPACING_METERS / 2, 4, (rows - 1) * CATALOGUE_GRID_SPACING_METERS / 2}
		distance = max(columns, rows) * CATALOGUE_GRID_SPACING_METERS * 0.9
	}
	eye := target + {distance * math.sin(view.camera_angle_radians), distance * 0.35, distance * math.cos(view.camera_angle_radians)}
	return Render.Camera_Look_At(eye, target, 55, aspect, 0.3, 1500)
}
