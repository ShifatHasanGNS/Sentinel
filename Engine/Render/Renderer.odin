package Render

import "../GPU"
import "../Procedural"
import "core:fmt"
import "core:math"
import la "core:math/linalg"
import gl "vendor:OpenGL"

TRIPLANAR_TILES_PER_METER :: 0.5
LIGHT_VOLUME_SEGMENTS :: 24
LIGHT_VOLUME_RINGS :: 12
SHADOW_MAP_SIZE :: 2048
CASCADE_SPLIT_LAMBDA :: 0.75

Render_Pass :: enum {
	Sky_Lut,
	Shadows,
	Geometry,
	Ssao,
	Lighting_Base,
	Lighting_Volumes,
	Post,
}

Renderer :: struct {
	timers:          [Render_Pass]GPU.Timer,
	gbuffer:         GPU.Framebuffer, // albedo + model, normal + roughness + metallic, emission + occlusion, depth
	hdr:             GPU.Framebuffer,
	ldr:             GPU.Framebuffer,
	bloom:           Bloom,
	ssao:            Ssao,
	geometry:        GPU.Shader,
	geometry_instanced: GPU.Shader,
	base_lighting:   GPU.Shader,
	volume_lighting: GPU.Shader,
	tonemap:         GPU.Shader,
	fxaa:            GPU.Shader,
	fullscreen:      GPU.Fullscreen_Pass,
	light_volume:    Mesh,
	shadows:         Shadow_Map,
	spot_shadows:    Shadow_Map, // One layer per granted spot light.
	spot_set:        Spot_Shadow_Set, // Chosen for the current frame.
	sky_lut:         Sky_Lut,
	cascades:        Cascade_Set, // Fitted for the current frame.
}

Renderer_Create :: proc(width, height: i32) -> (renderer: Renderer, ok: bool) {
	renderer.geometry = GPU.Shader_Create("Shaders/Geometry.glsl", nil, true) or_return
	renderer.geometry_instanced = GPU.Shader_Create("Shaders/Geometry.glsl", {"INSTANCED"}, true) or_return
	renderer.base_lighting = GPU.Shader_Create("Shaders/DeferredBase.glsl", {"CASCADE_COUNT 3"}, true) or_return
	renderer.volume_lighting = GPU.Shader_Create("Shaders/DeferredLight.glsl", nil, true) or_return
	renderer.tonemap = GPU.Shader_Create("Shaders/PostTonemap.glsl", nil, true) or_return
	renderer.fxaa = GPU.Shader_Create("Shaders/PostFxaa.glsl", nil, true) or_return
	renderer.gbuffer = GPU.Framebuffer_Create({width, height, {.SRGB8_A8, .RGBA16F, .RGBA16F}, .Depth32F})
	renderer.hdr = GPU.Framebuffer_Create({width, height, {.RGBA16F}, .None})
	renderer.ldr = GPU.Framebuffer_Create({width, height, {.RGBA8}, .None})
	renderer.bloom = Bloom_Create(width, height) or_return
	renderer.ssao = Ssao_Create(width, height) or_return
	renderer.fullscreen = GPU.Fullscreen_Pass_Create()
	renderer.shadows = Shadow_Map_Create(SHADOW_MAP_SIZE) or_return
	renderer.spot_shadows = Shadow_Map_Create(SPOT_SHADOW_SIZE, SPOT_SHADOWS_MAX) or_return
	renderer.sky_lut = Sky_Lut_Create()
	for &timer in renderer.timers do timer = GPU.Timer_Create()
	sphere := Procedural.Sphere_Create(1, LIGHT_VOLUME_SEGMENTS, LIGHT_VOLUME_RINGS)
	defer Procedural.Mesh_Destroy(&sphere)
	renderer.light_volume = Mesh_Upload(sphere)
	return renderer, true
}

Renderer_Destroy :: proc(renderer: ^Renderer) {
	for &timer in renderer.timers do GPU.Timer_Destroy(&timer)
	Sky_Lut_Destroy(&renderer.sky_lut)
	Shadow_Map_Destroy(&renderer.shadows)
	Shadow_Map_Destroy(&renderer.spot_shadows)
	Mesh_Destroy(&renderer.light_volume)
	GPU.Fullscreen_Pass_Destroy(&renderer.fullscreen)
	Bloom_Destroy(&renderer.bloom)
	Ssao_Destroy(&renderer.ssao)
	GPU.Framebuffer_Destroy(&renderer.ldr)
	GPU.Framebuffer_Destroy(&renderer.hdr)
	GPU.Framebuffer_Destroy(&renderer.gbuffer)
	GPU.Shader_Destroy(&renderer.fxaa)
	GPU.Shader_Destroy(&renderer.tonemap)
	GPU.Shader_Destroy(&renderer.volume_lighting)
	GPU.Shader_Destroy(&renderer.base_lighting)
	GPU.Shader_Destroy(&renderer.geometry_instanced)
	GPU.Shader_Destroy(&renderer.geometry)
}

Renderer_Render :: proc(renderer: ^Renderer, frame: Frame, width, height: i32) {
	GPU.Framebuffer_Resize(&renderer.gbuffer, width, height)
	GPU.Framebuffer_Resize(&renderer.hdr, width, height)
	GPU.Framebuffer_Resize(&renderer.ldr, width, height)
	for &timer in renderer.timers do GPU.Timer_Collect(&timer)
	timed(renderer, .Sky_Lut, proc(renderer: ^Renderer, frame: Frame) {
		Sky_Lut_Render(&renderer.sky_lut, frame.sky.to_sun, frame.sky.sun_intensity)
	}, frame)
	timed(renderer, .Shadows, shadow_pass, frame)
	timed(renderer, .Geometry, geometry_pass, frame)
	if frame.ssao_radius_meters > 0 do timed(renderer, .Ssao, ssao_pass, frame)
	lighting_pass(renderer, frame)
	timed(renderer, .Post, post_pass, frame)
}

// Runs a pass between GPU timer begin and end.
@(private = "file")
timed :: proc(renderer: ^Renderer, pass: Render_Pass, body: proc(renderer: ^Renderer, frame: Frame), frame: Frame) {
	GPU.Timer_Begin(&renderer.timers[pass])
	body(renderer, frame)
	GPU.Timer_End(&renderer.timers[pass])
}

// Average GPU milliseconds per pass since the last reset.
Renderer_Pass_Milliseconds :: proc(renderer: ^Renderer) -> (milliseconds: [Render_Pass]f32) {
	for timer, pass in renderer.timers do milliseconds[pass] = GPU.Timer_Average_Milliseconds(timer)
	return
}

Renderer_Reset_Timers :: proc(renderer: ^Renderer) {
	for &timer in renderer.timers do GPU.Timer_Reset(&timer)
}

@(private = "file")
shadow_pass :: proc(renderer: ^Renderer, frame: Frame) {
	casters := frame.shadow_items if len(frame.shadow_items) > 0 else frame.items
	if frame.sun_shadows {
		renderer.cascades = Shadow_Cascades_Fit(frame.camera, frame.sun.direction, frame.shadow_distance_meters, CASCADE_SPLIT_LAMBDA, SHADOW_MAP_SIZE)
		Shadow_Map_Render(&renderer.shadows, renderer.cascades, casters)
	}
	renderer.spot_set = Spot_Shadows_Choose(frame.local_lights, frame.camera.position)
	if renderer.spot_set.count > 0 do Shadow_Map_Render_Layers(&renderer.spot_shadows, renderer.spot_set.matrices[:renderer.spot_set.count], casters)
}

@(private = "file")
geometry_pass :: proc(renderer: ^Renderer, frame: Frame) {
	GPU.Framebuffer_Bind(&renderer.gbuffer)
	gl.Enable(gl.DEPTH_TEST)
	gl.DepthMask(true)
	gl.Enable(gl.CULL_FACE)
	gl.CullFace(gl.BACK)
	gl.ClearColor(0, 0, 0, 0)
	gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
	gl.Enable(gl.FRAMEBUFFER_SRGB)
	draw_geometry_items(&renderer.geometry, frame, false)
	draw_geometry_items(&renderer.geometry_instanced, frame, true)
	gl.Disable(gl.FRAMEBUFFER_SRGB)
}

@(private = "file")
draw_geometry_items :: proc(shader: ^GPU.Shader, frame: Frame, instanced: bool) {
	GPU.Shader_Use(shader)
	Texture_Set_Bind(shader, frame.materials)
	GPU.Shader_Set(shader, "u_ViewProjection", frame.camera.view_projection)
	GPU.Shader_Set(shader, "u_TriplanarScale", f32(TRIPLANAR_TILES_PER_METER))
	GPU.Shader_Set(shader, "u_GroundLevel", frame.ground_level_meters)
	GPU.Shader_Set(shader, "u_CameraPosition", frame.camera.position)
	shading := frame.terrain_shading
	GPU.Shader_Set(shader, "u_TerrainLayers", [4]f32{f32(shading.grass_layer), f32(shading.dirt_layer), f32(shading.rock_layer), f32(shading.sand_layer)})
	GPU.Shader_Set(shader, "u_PlateauCenter", shading.plateau_center)
	GPU.Shader_Set(shader, "u_PlateauRange", [2]f32{shading.plateau_radius_meters, shading.plateau_blend_meters})
	for &item in frame.items {
		if item.mesh.instanced == instanced do draw_geometry_item(shader, &item)
	}
}

@(private = "file")
draw_geometry_item :: proc(shader: ^GPU.Shader, item: ^Draw_Item) {
	GPU.Shader_Set(shader, "u_Model", item.model)
	GPU.Shader_Set(shader, "u_Layer", f32(item.material_layer))
	GPU.Shader_Set(shader, "u_UvScale", item.uv_scale)
	GPU.Shader_Set(shader, "u_Triplanar", i32(item.triplanar))
	GPU.Shader_Set(shader, "u_IlluminationModel", i32(item.illumination_model))
	GPU.Shader_Set(shader, "u_Emission", item.emission)
	GPU.Shader_Set(shader, "u_Terrain", i32(item.terrain))
	GPU.Shader_Set(shader, "u_Transparency", item.transparency)
	Mesh_Draw(item.mesh)
}

@(private = "file")
ssao_pass :: proc(renderer: ^Renderer, frame: Frame) {
	Ssao_Render(renderer, frame.camera, frame.ssao_radius_meters)
}

@(private = "file")
lighting_pass :: proc(renderer: ^Renderer, frame: Frame) {
	GPU.Framebuffer_Bind(&renderer.hdr)
	gl.Disable(gl.DEPTH_TEST)
	gl.Disable(gl.CULL_FACE)
	gl.Disable(gl.BLEND)
	timed(renderer, .Lighting_Base, light_base, frame)
	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.ONE, gl.ONE)
	gl.Enable(gl.CULL_FACE)
	gl.CullFace(gl.FRONT) // Back faces of the volume cover the lit pixels even when the camera is inside it.
	timed(renderer, .Lighting_Volumes, light_volumes, frame)
	gl.CullFace(gl.BACK)
	gl.Disable(gl.BLEND)
}

@(private = "file")
light_base :: proc(renderer: ^Renderer, frame: Frame) {
	shader := &renderer.base_lighting
	GPU.Shader_Use(shader)
	bind_gbuffer(shader, renderer, frame.camera)
	Sky_Lut_Bind(shader, &renderer.sky_lut)
	GPU.Shader_Set(shader, "u_SkyZenith", frame.sky.zenith)
	GPU.Shader_Set(shader, "u_SkyHorizon", frame.sky.horizon)
	GPU.Shader_Set(shader, "u_SkyGround", frame.sky.ground)
	GPU.Shader_Set(shader, "u_SunColor", frame.sky.sun_color)
	GPU.Shader_Set(shader, "u_ToSun", frame.sky.to_sun)
	GPU.Shader_Set(shader, "u_ToMoon", frame.sky.to_moon)
	GPU.Shader_Set(shader, "u_MoonColor", frame.sky.moon_color)
	GPU.Shader_Set(shader, "u_MoonIntensity", frame.sky.moon_intensity)
	Light_Set_Uniforms(shader, "u_Sun", frame.sun)
	GPU.Shader_Set(shader, "u_CameraForward", frame.camera.forward)
	GPU.Shader_Set(shader, "u_SunShadows", i32(frame.sun_shadows))
	set_interior_uniforms(shader, frame.interiors)
	GPU.Shader_Set(shader, "u_Ssao", GPU.Texture_Bind_Next(&renderer.ssao.blurred.colors[0], GPU.Sampler_Nearest_Clamp))
	GPU.Shader_Set(shader, "u_SsaoEnabled", i32(frame.ssao_radius_meters > 0))
	if frame.sun_shadows do Shadow_Map_Bind(shader, &renderer.shadows, renderer.cascades)
	GPU.Fullscreen_Pass_Draw(&renderer.fullscreen)
}

@(private = "file")
light_volumes :: proc(renderer: ^Renderer, frame: Frame) {
	shader := &renderer.volume_lighting
	GPU.Shader_Use(shader)
	bind_gbuffer(shader, renderer, frame.camera)
	GPU.Shader_Set(shader, "u_ViewProjection", frame.camera.view_projection)
	GPU.Shader_Set(shader, "u_ScreenSize", [2]f32{f32(renderer.gbuffer.width), f32(renderer.gbuffer.height)})
	GPU.Shader_Set(shader, "u_SpotShadows", GPU.Texture_Bind_Next(&renderer.spot_shadows.depth, GPU.Sampler_Shadow))
	GPU.Shader_Set(shader, "u_SpotShadowSize", f32(SPOT_SHADOW_SIZE))
	set_interior_uniforms(shader, frame.interiors)
	for light, index in frame.local_lights {
		set_spot_shadow(shader, renderer.spot_set, light, index)
		GPU.Shader_Set(shader, "u_LightRoom", i32(Interior_Index_At(frame.interiors, light.position)))
		volume := la.matrix4_translate_f32(light.position) * la.matrix4_scale_f32({light.range_meters, light.range_meters, light.range_meters})
		GPU.Shader_Set(shader, "u_Model", volume)
		Light_Set_Uniforms(shader, "u_Light", light)
		Mesh_Draw(&renderer.light_volume)
	}
}

bind_gbuffer :: proc(shader: ^GPU.Shader, renderer: ^Renderer, camera: Camera) {
	GPU.Texture_Units_Reset()
	GPU.Shader_Set(shader, "u_GAlbedo", GPU.Texture_Bind_Next(&renderer.gbuffer.colors[0], GPU.Sampler_Nearest_Clamp))
	GPU.Shader_Set(shader, "u_GNormal", GPU.Texture_Bind_Next(&renderer.gbuffer.colors[1], GPU.Sampler_Nearest_Clamp))
	GPU.Shader_Set(shader, "u_GEmission", GPU.Texture_Bind_Next(&renderer.gbuffer.colors[2], GPU.Sampler_Nearest_Clamp))
	GPU.Shader_Set(shader, "u_GDepth", GPU.Texture_Bind_Next(&renderer.gbuffer.depth, GPU.Sampler_Nearest_Clamp))
	GPU.Shader_Set(shader, "u_InverseViewProjection", la.inverse(camera.view_projection))
	GPU.Shader_Set(shader, "u_CameraPosition", camera.position)
}

@(private = "file")
post_pass :: proc(renderer: ^Renderer, frame: Frame) {
	width, height := renderer.gbuffer.width, renderer.gbuffer.height
	if frame.bloom_strength > 0 do Bloom_Render(&renderer.bloom, &renderer.hdr.colors[0], width, height, &renderer.fullscreen)
	GPU.Framebuffer_Bind(&renderer.ldr)
	GPU.Shader_Use(&renderer.tonemap)
	GPU.Texture_Units_Reset()
	GPU.Shader_Set(&renderer.tonemap, "u_Hdr", GPU.Texture_Bind_Next(&renderer.hdr.colors[0], GPU.Sampler_Linear_Clamp))
	GPU.Shader_Set(&renderer.tonemap, "u_Bloom", GPU.Texture_Bind_Next(&renderer.bloom.levels[0].colors[0], GPU.Sampler_Linear_Clamp))
	GPU.Shader_Set(&renderer.tonemap, "u_BloomStrength", frame.bloom_strength)
	GPU.Shader_Set(&renderer.tonemap, "u_Depth", GPU.Texture_Bind_Next(&renderer.gbuffer.depth, GPU.Sampler_Nearest_Clamp))
	sun_uv, shaft_color := shaft_inputs(frame)
	GPU.Shader_Set(&renderer.tonemap, "u_SunUv", sun_uv)
	GPU.Shader_Set(&renderer.tonemap, "u_ShaftColor", shaft_color)
	GPU.Shader_Set(&renderer.tonemap, "u_Exposure", frame.exposure)
	GPU.Shader_Set(&renderer.tonemap, "u_VignetteStrength", frame.vignette_strength)
	GPU.Fullscreen_Pass_Draw(&renderer.fullscreen)

	GPU.Framebuffer_Bind_Default(width, height)
	GPU.Shader_Use(&renderer.fxaa)
	GPU.Texture_Units_Reset()
	GPU.Shader_Set(&renderer.fxaa, "u_Ldr", GPU.Texture_Bind_Next(&renderer.ldr.colors[0], GPU.Sampler_Linear_Clamp))
	GPU.Shader_Set(&renderer.fxaa, "u_ScreenSize", [2]f32{f32(width), f32(height)})
	GPU.Fullscreen_Pass_Draw(&renderer.fullscreen)
}

// Where the sun lands on screen, and the shaft tint (zero when the sun is behind the camera, below the horizon, or shafts are off).
@(private = "file")
shaft_inputs :: proc(frame: Frame) -> (sun_uv: [2]f32, color: [3]f32) {
	if frame.shaft_strength <= 0 || frame.sky.to_sun.y <= 0.02 do return
	clip := frame.camera.view_projection * [4]f32{frame.camera.position.x + frame.sky.to_sun.x * 1000, frame.camera.position.y + frame.sky.to_sun.y * 1000, frame.camera.position.z + frame.sky.to_sun.z * 1000, 1}
	if clip.w <= 0 do return
	sun_uv = {clip.x / clip.w * 0.5 + 0.5, clip.y / clip.w * 0.5 + 0.5}
	return sun_uv, frame.sky.sun_color * frame.shaft_strength * min(frame.sky.to_sun.y * 4, 1)
}

// Tells the light-volume shader which depth layer (if any) belongs to this light.
@(private = "file")
set_spot_shadow :: proc(shader: ^GPU.Shader, set: Spot_Shadow_Set, light: Light, light_index: int) {
	slot := -1
	for candidate in 0 ..< set.count do if set.light_index[candidate] == light_index do slot = candidate
	GPU.Shader_Set(shader, "u_ShadowSlot", i32(slot))
	if slot < 0 do return
	GPU.Shader_Set(shader, "u_SpotMatrix", set.matrices[slot])
	GPU.Shader_Set(shader, "u_SpotTexelPerMeter", Spot_Shadow_Texel_Per_Meter(light))
}

@(private = "file")
set_interior_uniforms :: proc(shader: ^GPU.Shader, interiors: []Interior_Volume) {
	count := min(len(interiors), INTERIORS_MAX)
	GPU.Shader_Set(shader, "u_InteriorCount", i32(count))
	for volume, index in interiors[:count] {
		GPU.Shader_Set(shader, fmt.tprintf("u_InteriorCenter[%d]", index), [4]f32{volume.center.x, volume.center.y, volume.center.z, 0})
		GPU.Shader_Set(shader, fmt.tprintf("u_InteriorTurn[%d]", index), [2]f32{math.cos(volume.yaw_radians), math.sin(volume.yaw_radians)})
		GPU.Shader_Set(shader, fmt.tprintf("u_InteriorHalf[%d]", index), volume.half_extents)
	}
}
