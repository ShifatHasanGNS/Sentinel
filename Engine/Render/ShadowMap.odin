package Render

import "../GPU"
import "core:fmt"
import gl "vendor:OpenGL"

Shadow_Map :: struct {
	depth:  GPU.Texture, // 2D array, one layer per cascade.
	target: GPU.Framebuffer,
	shader: GPU.Shader,
	instanced_shader: GPU.Shader,
	size:   i32,
}

Shadow_Map_Create :: proc(size: i32, layers: i32 = CASCADE_COUNT) -> (shadow_map: Shadow_Map, ok: bool) {
	shadow_map.shader = GPU.Shader_Create("Shaders/ShadowDepth.glsl", nil, true) or_return
	shadow_map.instanced_shader = GPU.Shader_Create("Shaders/ShadowDepth.glsl", {"INSTANCED"}, true) or_return
	shadow_map.depth = GPU.Texture_Create({.Texture_2D_Array, .Depth32F, size, size, layers, 1})
	shadow_map.target = GPU.Framebuffer_Create_For_Layers(size, size)
	shadow_map.size = size
	return shadow_map, true
}

Shadow_Map_Destroy :: proc(shadow_map: ^Shadow_Map) {
	GPU.Framebuffer_Destroy(&shadow_map.target)
	GPU.Texture_Destroy(&shadow_map.depth)
	GPU.Shader_Destroy(&shadow_map.instanced_shader)
	GPU.Shader_Destroy(&shadow_map.shader)
}

// Draws every item's depth once per cascade. Leaves the shadow framebuffer bound; callers bind their own target next.
Shadow_Map_Render :: proc(shadow_map: ^Shadow_Map, cascades: Cascade_Set, items: []Draw_Item) {
	matrices: [CASCADE_COUNT]matrix[4, 4]f32
	for cascade, index in cascades do matrices[index] = cascade.view_projection
	Shadow_Map_Render_Layers(shadow_map, matrices[:], items)
}

// One depth layer per matrix.
Shadow_Map_Render_Layers :: proc(shadow_map: ^Shadow_Map, matrices: []matrix[4, 4]f32, items: []Draw_Item) {
	gl.Enable(gl.DEPTH_TEST)
	gl.DepthMask(true)
	gl.Disable(gl.CULL_FACE)
	gl.Enable(gl.POLYGON_OFFSET_FILL)
	gl.PolygonOffset(2, 4)
	for view_projection, index in matrices {
		GPU.Framebuffer_Set_Depth_Layer(&shadow_map.target, &shadow_map.depth, i32(index))
		GPU.Framebuffer_Bind(&shadow_map.target)
		gl.Clear(gl.DEPTH_BUFFER_BIT)
		frustum := Frustum_From_View_Projection(view_projection)
		draw_casters(&shadow_map.shader, view_projection, frustum, items, false)
		draw_casters(&shadow_map.instanced_shader, view_projection, frustum, items, true)
	}
	gl.Disable(gl.POLYGON_OFFSET_FILL)
}

@(private = "file")
draw_casters :: proc(shader: ^GPU.Shader, view_projection: matrix[4, 4]f32, frustum: Frustum, items: []Draw_Item, instanced: bool) {
	GPU.Shader_Use(shader)
	GPU.Shader_Set(shader, "u_LightViewProjection", view_projection)
	for &item in items {
		if item.mesh.instanced != instanced do continue
		if bounds, known := item.bounds.?; known && !Frustum_Intersects_Aabb(frustum, bounds.lowest, bounds.highest) do continue // Outside this cascade's light frustum: its depth would never be seen.
		GPU.Shader_Set(shader, "u_Model", item.model)
		Mesh_Draw(item.mesh)
	}
}

// Binds the depth array to the next texture unit and sets the uniforms Shaders/Include/Shadow.glsl reads.
Shadow_Map_Bind :: proc(shader: ^GPU.Shader, shadow_map: ^Shadow_Map, cascades: Cascade_Set) {
	GPU.Shader_Set(shader, "u_ShadowMap", GPU.Texture_Bind_Next(&shadow_map.depth, GPU.Sampler_Shadow))
	GPU.Shader_Set(shader, "u_ShadowMapSize", f32(shadow_map.size))
	for cascade, index in cascades {
		GPU.Shader_Set(shader, fmt.tprintf("u_ShadowMatrices[%d]", index), cascade.view_projection)
		GPU.Shader_Set(shader, fmt.tprintf("u_CascadeFar[%d]", index), cascade.far_distance)
		GPU.Shader_Set(shader, fmt.tprintf("u_CascadeTexel[%d]", index), cascade.texel_world_meters)
	}
}
