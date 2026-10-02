package Showroom

import "../../Engine/GPU"
import "../../Engine/Platform"
import "../../Engine/Procedural"
import "../../Engine/Render"
import "../Materials"
import "core:math"
import la "core:math/linalg"
import gl "vendor:OpenGL"

GROUND_HALF_EXTENT_METERS :: 40
GROUND_TILES :: 40

Showroom :: struct {
	materials:            Procedural.Texture_Set,
	lit:                  GPU.Shader,
	gallery:              [dynamic]Gallery_Item,
	ground:               Gallery_Item,
	camera_angle_radians: f32,
}

Showroom_Create :: proc() -> (showroom: Showroom, ok: bool) {
	showroom.lit = GPU.Shader_Create("Shaders/Lit.glsl") or_return
	showroom.materials = Materials.Materials_Bake() or_return
	showroom.gallery = Gallery_Create()
	showroom.ground = create_ground()
	gl.Enable(gl.DEPTH_TEST)
	return showroom, true
}

Showroom_Update :: proc(showroom: ^Showroom, clock: Platform.Clock) {
	showroom.camera_angle_radians += clock.delta_seconds * 0.15
}

Showroom_Render :: proc(showroom: ^Showroom, window: Platform.Window) {
	GPU.Framebuffer_Bind_Default(window.framebuffer_width, window.framebuffer_height)
	gl.ClearColor(0.45, 0.6, 0.8, 1)
	gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
	GPU.Shader_Use(&showroom.lit)
	Render.Texture_Set_Bind(&showroom.lit, &showroom.materials)
	eye, view_projection := camera(showroom, window)
	GPU.Shader_Set(&showroom.lit, "u_ViewProjection", view_projection)
	GPU.Shader_Set(&showroom.lit, "u_CameraPosition", eye)
	GPU.Shader_Set(&showroom.lit, "u_LightDirection", [3]f32{0.4, 0.8, 0.5})
	GPU.Shader_Set(&showroom.lit, "u_TriplanarScale", f32(TRIPLANAR_TILES_PER_METER))
	draw_item(showroom, &showroom.ground)
	for &item in showroom.gallery do draw_item(showroom, &item)
}

Showroom_Destroy :: proc(showroom: ^Showroom) {
	Render.Mesh_Destroy(&showroom.ground.mesh)
	Gallery_Destroy(&showroom.gallery)
	Procedural.Texture_Set_Destroy(&showroom.materials)
	GPU.Shader_Destroy(&showroom.lit)
	GPU.Sampler_Cache_Destroy()
}

@(private = "file")
draw_item :: proc(showroom: ^Showroom, item: ^Gallery_Item) {
	GPU.Shader_Set(&showroom.lit, "u_Model", item.model)
	GPU.Shader_Set(&showroom.lit, "u_Layer", f32(item.material))
	GPU.Shader_Set(&showroom.lit, "u_UvScale", item.uv_scale)
	GPU.Shader_Set(&showroom.lit, "u_Triplanar", i32(item.triplanar))
	Render.Mesh_Draw(&item.mesh)
}

@(private = "file")
camera :: proc(showroom: ^Showroom, window: Platform.Window) -> (eye: [3]f32, view_projection: matrix[4, 4]f32) {
	aspect := f32(window.framebuffer_width) / f32(window.framebuffer_height)
	projection := la.matrix4_perspective_f32(math.to_radians(f32(60)), aspect, 0.1, 200)
	target := [3]f32{0, 1, GALLERY_ROW_SPACING_METERS}
	eye = target + {13 * math.sin(showroom.camera_angle_radians), 5, 13 * math.cos(showroom.camera_angle_radians)}
	view := la.matrix4_look_at_f32(eye, target, {0, 1, 0})
	return eye, projection * view
}

// A thin slab whose top face is the floor; its [0,1] uv is scaled to tile the dirt material across it.
@(private = "file")
create_ground :: proc() -> Gallery_Item {
	slab := Procedural.Box_Create({2 * GROUND_HALF_EXTENT_METERS, 0.2, 2 * GROUND_HALF_EXTENT_METERS})
	defer Procedural.Mesh_Destroy(&slab)
	return Gallery_Item{Render.Mesh_Upload(slab), la.matrix4_translate_f32({0, -0.1, 0}), .Dirt, {GROUND_TILES, GROUND_TILES}, false}
}
