package main

import "../../Engine/GPU"
import "../../Engine/Platform"
import "../../Engine/Procedural"
import "../../Engine/Render"
import "../Support"
import "core:fmt"
import "core:math"
import la "core:math/linalg"
import "core:os"
import gl "vendor:OpenGL"

// Lighting, tonemap and shadow functions are probed on the GPU: a fixture shader includes the real GLSL and writes results to pixels.
main :: proc() {
	checks: Support.Checks
	window, window_ok := Platform.Window_Create("Render check", 64, 64, false)
	if !window_ok do os.exit(1)
	defer Platform.Window_Destroy(&window)
	defer GPU.Sampler_Cache_Destroy()

	check_normal_encoding_round_trip(&checks)
	check_tonemap_is_monotonic_and_bounded(&checks)
	check_illumination_models(&checks)
	check_light_falloff_and_shapes(&checks)
	check_sun_shadows(&checks)
	check_atmosphere(&checks)
	check_instancing(&checks)
	check_sky_lut(&checks)
	fmt.printfln("%d checks passed, %d failed", checks.passed, checks.failed)
	if checks.failed > 0 do os.exit(1)
}

// Encoded normals are stored in a half-float target, so the round trip includes half-float precision.
check_normal_encoding_round_trip :: proc(checks: ^Support.Checks) {
	shader, ok := GPU.Shader_Create("Tests/RenderCheck/Fixtures/NormalProbe.glsl")
	Support.expect(checks, ok)
	if !ok do return
	defer GPU.Shader_Destroy(&shader)
	pass := GPU.Fullscreen_Pass_Create()
	defer GPU.Fullscreen_Pass_Destroy(&pass)
	encoded := GPU.Framebuffer_Create({64, 64, {.RGBA16F}, .None})
	defer GPU.Framebuffer_Destroy(&encoded)

	GPU.Framebuffer_Bind(&encoded)
	GPU.Shader_Use(&shader)
	GPU.Shader_Set(&shader, "u_Mode", i32(0))
	GPU.Fullscreen_Pass_Draw(&pass)
	GPU.Texture_Units_Reset()
	GPU.Shader_Set(&shader, "u_Encoded", GPU.Texture_Bind_Next(&encoded.colors[0], GPU.Sampler_Nearest_Clamp))
	GPU.Shader_Set(&shader, "u_Mode", i32(1))
	for pixel in Support.Probe_Render(&shader, 64, 64) {
		Support.expect(checks, pixel.x > 0.99999 && abs(pixel.y - 1) < 1e-4)
	}
}

check_tonemap_is_monotonic_and_bounded :: proc(checks: ^Support.Checks) {
	shader, ok := GPU.Shader_Create("Tests/RenderCheck/Fixtures/TonemapProbe.glsl")
	Support.expect(checks, ok)
	if !ok do return
	defer GPU.Shader_Destroy(&shader)
	row := Support.Probe_Render(&shader, 64, 1)
	Support.expect_value(checks, row[0].x, 0)
	for pixel, index in row {
		Support.expect(checks, pixel.x >= 0 && pixel.x <= 1)
		if index > 0 do Support.expect(checks, pixel.x >= row[index - 1].x)
	}
	Support.expect(checks, row[63].x > 0.99) // Very bright input saturates near white.
}

Model :: Render.Illumination_Model

set_brdf :: proc(shader: ^GPU.Shader, mode: i32, model: Model, roughness, metallic: f32, albedo: [3]f32 = {1, 1, 1}, view_cosine: f32 = 0.7) {
	GPU.Shader_Set(shader, "u_Mode", mode)
	GPU.Shader_Set(shader, "u_Model", i32(model))
	GPU.Shader_Set(shader, "u_Roughness", roughness)
	GPU.Shader_Set(shader, "u_Metallic", metallic)
	GPU.Shader_Set(shader, "u_Albedo", albedo)
	GPU.Shader_Set(shader, "u_ViewCosine", view_cosine)
}

check_illumination_models :: proc(checks: ^Support.Checks) {
	shader, ok := GPU.Shader_Create("Tests/RenderCheck/Fixtures/BrdfProbe.glsl", nil, true)
	Support.expect(checks, ok)
	if !ok do return
	defer GPU.Shader_Destroy(&shader)

	for model in Model do for roughness in ([3]f32{0.3, 0.6, 1.0}) do for metallic in ([2]f32{0, 1}) {
		set_brdf(&shader, 0, model, roughness, metallic)
		samples := Support.Probe_Render(&shader, 64, 64)
		defer delete(samples)
		reciprocal := model != .Phong // Phong uses the reflection vector R.V, which is not symmetric in l and v by design.
		for sample in samples {
			Support.expect(checks, sample.x >= 0 && sample.y >= 0 && sample.z >= 0 && sample.x < 1e3)
			if reciprocal do Support.expect(checks, abs(sample.x - sample.w) < 1e-4 * (1 + sample.x))
		}
		check_white_furnace(checks, &shader, model, roughness, metallic)
	}

	set_brdf(&shader, 0, .Lambert, 0.5, 0, {0.6, 0.6, 0.6})
	for sample in Support.Probe_Render(&shader, 64, 64) do Support.expect(checks, abs(sample.x - 0.6 / math.PI) < 1e-5)

	set_brdf(&shader, 0, .Oren_Nayar, 0, 0)
	for sample in Support.Probe_Render(&shader, 64, 64) do Support.expect(checks, abs(sample.x - 1 / math.PI) < 1e-5)

	for model in Model {
		if model == .Subsurface do continue // Wrapped lighting deliberately lets light arrive from just below the horizon.
		set_brdf(&shader, 1, model, 0.5, 0)
		for sample in Support.Probe_Render(&shader, 64, 64) do Support.expect_value(checks, sample.x, 0)
	}

	set_brdf(&shader, 3, .Lambert, 0.5, 0)
	for sample, index in Support.Probe_Render(&shader, 64, 1) {
		Support.expect(checks, abs(sample.y - max(sample.z, 0)) < 1e-5) // Standard cosine.
		Support.expect(checks, sample.x >= sample.y - 1e-6) // Wrapped light is never darker.
		if sample.z <= -0.99 do Support.expect(checks, sample.x < 0.01)
		if sample.z > 0.9 && index == 63 do Support.expect(checks, sample.x > 0.95)
		if sample.z > -0.1 && sample.z < 0.1 do Support.expect(checks, sample.x > 0.2) // Light wraps past the terminator.
	}
}

FURNACE_GRID :: 256

// Directional albedo = integral of f * cos over the hemisphere. Energy conservation bounds it by 1; Lambert gives its albedo.
// Phong and Blinn-Phong normalisations are approximations that overshoot slightly at normal incidence, so they get a looser bound.
check_white_furnace :: proc(checks: ^Support.Checks, shader: ^GPU.Shader, model: Model, roughness, metallic: f32) {
	diffuse_only_metal := (model == .Lambert || model == .Oren_Nayar) && metallic == 1
	upper_bound: f32 = 1.10 if model == .Phong || model == .Blinn_Phong else 1.03
	for view_cosine in ([3]f32{0.2, 0.7, 1.0}) {
		set_brdf(shader, 2, model, roughness, metallic, {1, 1, 1}, view_cosine)
		GPU.Shader_Set(shader, "u_GridSize", f32(FURNACE_GRID))
		samples := Support.Probe_Render(shader, FURNACE_GRID, FURNACE_GRID)
		defer delete(samples)
		total: f32
		for sample in samples do total += sample.x
		albedo := total * (math.PI / 2 / FURNACE_GRID) * (2 * math.PI / FURNACE_GRID)
		if albedo > upper_bound do fmt.eprintfln("furnace %v rough %v metal %v view %v: %v", model, roughness, metallic, view_cosine, albedo)
		Support.expect(checks, albedo <= upper_bound)
		Support.expect(checks, albedo < 1e-4 if diffuse_only_metal else albedo > 0.05)
		if model == .Lambert && metallic == 0 do Support.expect(checks, abs(albedo - 1) < 0.01)
	}
}

check_light_falloff_and_shapes :: proc(checks: ^Support.Checks) {
	shader, ok := GPU.Shader_Create("Tests/RenderCheck/Fixtures/LightProbe.glsl", nil, true)
	Support.expect(checks, ok)
	if !ok do return
	defer GPU.Shader_Destroy(&shader)

	GPU.Shader_Set(&shader, "u_Mode", i32(0))
	attenuation := Support.Probe_Render(&shader, 64, 1)
	defer delete(attenuation)
	Support.expect(checks, attenuation[0].x > 0.97 && attenuation[0].x <= 1) // Finite at the light itself (first sample is 0.16 m away: 1 / (1 + 0.16^2) = 0.976).
	for sample, index in attenuation {
		if index > 0 do Support.expect(checks, sample.x <= attenuation[index - 1].x)
		if sample.y >= 10 do Support.expect_value(checks, sample.x, 0) // Exactly zero at and beyond range.
		if sample.y < 9.5 do Support.expect(checks, sample.x > 0)
	}

	GPU.Shader_Set(&shader, "u_Mode", i32(1))
	cone := Support.Probe_Render(&shader, 64, 1)
	defer delete(cone)
	for sample, index in cone {
		if index > 0 do Support.expect(checks, sample.x >= cone[index - 1].x)
		if sample.y >= 0.9 do Support.expect_value(checks, sample.x, 1)
		if sample.y <= 0.7 do Support.expect_value(checks, sample.x, 0)
	}

	GPU.Shader_Set(&shader, "u_Mode", i32(2))
	far_field := Support.Probe_Render(&shader, 64, 1)
	defer delete(far_field)
	for sample in far_field {
		Support.expect(checks, sample.x > 0 && abs(sample.y / sample.x - 1) < 0.03) // Seen on axis from afar, a small emitter is a point source.
	}

	GPU.Shader_Set(&shader, "u_Mode", i32(3))
	for sample in Support.Probe_Render(&shader, 64, 1) {
		Support.expect_value(checks, sample.x, 0) // Behind the emitter: nothing.
		Support.expect(checks, sample.y > 0 && sample.y < 1e4) // Close to the emitter: bright but finite.
	}

	GPU.Shader_Set(&shader, "u_Mode", i32(4))
	sun := Support.Probe_Render(&shader, 64, 1)
	defer delete(sun)
	for sample in sun do Support.expect(checks, abs(sample.x - sun[0].x) < 1e-6 && sample.x > 0) // Directional light does not depend on position.
}

// A floor with a 2 m box on it. Points under the box's shadow must be dark, nearby points lit, and a lit stretch of floor must
// show no acne (false self-shadowing) even under a low, oblique sun.
check_sun_shadows :: proc(checks: ^Support.Checks) {
	floor_cpu := Procedural.Box_Create({20, 0.2, 20})
	defer Procedural.Mesh_Destroy(&floor_cpu)
	occluder_cpu := Procedural.Box_Create({2, 2, 2})
	defer Procedural.Mesh_Destroy(&occluder_cpu)
	floor_mesh := Render.Mesh_Upload(floor_cpu)
	defer Render.Mesh_Destroy(&floor_mesh)
	occluder_mesh := Render.Mesh_Upload(occluder_cpu)
	defer Render.Mesh_Destroy(&occluder_mesh)
	items := []Render.Draw_Item{
		{mesh = &floor_mesh, model = la.matrix4_translate_f32({0, -0.1, 0})},
		{mesh = &occluder_mesh, model = la.matrix4_translate_f32({0, 1, 0})},
	}
	shadow_map, map_ok := Render.Shadow_Map_Create(1024)
	Support.expect(checks, map_ok)
	if !map_ok do return
	defer Render.Shadow_Map_Destroy(&shadow_map)
	probe, probe_ok := GPU.Shader_Create("Tests/RenderCheck/Fixtures/ShadowProbe.glsl", {"CASCADE_COUNT 3"}, true)
	Support.expect(checks, probe_ok)
	if !probe_ok do return
	defer GPU.Shader_Destroy(&probe)
	camera := Render.Camera_Look_At({0, 6, 10}, {0, 0, 0}, 60, 1.5, 0.5, 60)

	steep: [3]f32 = la.normalize([3]f32{-0.3, -1, -0.2})
	cascades := Render.Shadow_Cascades_Fit(camera, steep, 40, 0.75, 1024)
	Render.Shadow_Map_Render(&shadow_map, cascades, items)
	points := [8][3]f32{{0, 0, 0}, {8, 0, 8}, {-8, 0, 5}, {0, 0, -6}, {3, 0, 0}, {0, 2.0, 0}, {-1.5, 0, -0.5}, {0, 0, 4}}
	run_shadow_probe(&probe, &shadow_map, cascades, camera, steep, 0, points)
	row := Support.Probe_Render(&probe, 8, 1)
	defer delete(row)
	for index in ([2]int{0, 6}) do Support.expect(checks, row[index].x < 0.1) // Under the box's shadow.
	for index in ([6]int{1, 2, 3, 4, 5, 7}) do Support.expect(checks, row[index].x > 0.9) // In the sun, including the box's own lit top.

	oblique: [3]f32 = la.normalize([3]f32{-0.95, -0.12, -0.3})
	cascades = Render.Shadow_Cascades_Fit(camera, oblique, 40, 0.75, 1024)
	Render.Shadow_Map_Render(&shadow_map, cascades, items)
	run_shadow_probe(&probe, &shadow_map, cascades, camera, oblique, 1, points)
	for sample in Support.Probe_Render(&probe, 64, 64) do Support.expect(checks, sample.x > 0.95)
}

run_shadow_probe :: proc(probe: ^GPU.Shader, shadow_map: ^Render.Shadow_Map, cascades: Render.Cascade_Set, camera: Render.Camera, light_travel: [3]f32, mode: i32, points: [8][3]f32) {
	GPU.Shader_Use(probe)
	GPU.Texture_Units_Reset()
	Render.Shadow_Map_Bind(probe, shadow_map, cascades)
	GPU.Shader_Set(probe, "u_Mode", mode)
	for point, index in points do GPU.Shader_Set(probe, fmt.tprintf("u_Points[%d]", index), point)
	GPU.Shader_Set(probe, "u_ToLight", -light_travel)
	GPU.Shader_Set(probe, "u_ProbeCameraPosition", camera.position)
	GPU.Shader_Set(probe, "u_ProbeCameraForward", camera.forward)
}

sky_at :: proc(shader: ^GPU.Shader, to_sun, direction: [3]f32) -> [3]f32 {
	GPU.Shader_Set(shader, "u_Mode", i32(0))
	GPU.Shader_Set(shader, "u_ToSun", to_sun)
	GPU.Shader_Set(shader, "u_Direction", direction)
	pixels := Support.Probe_Render(shader, 1, 1)
	defer delete(pixels)
	return pixels[0].xyz
}

sky_luminance :: proc(color: [3]f32) -> f32 {
	return 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b
}

check_atmosphere :: proc(checks: ^Support.Checks) {
	shader, ok := GPU.Shader_Create("Tests/RenderCheck/Fixtures/AtmosphereProbe.glsl", nil, true)
	Support.expect(checks, ok)
	if !ok do return
	defer GPU.Shader_Destroy(&shader)

	for elevation_degrees in ([5]f32{60, 20, 2, -5, -30}) {
		elevation := math.to_radians(elevation_degrees)
		GPU.Shader_Set(&shader, "u_Mode", i32(1))
		GPU.Shader_Set(&shader, "u_ToSun", [3]f32{math.cos(elevation), math.sin(elevation), 0})
		for pixel in Support.Probe_Render(&shader, 64, 32) {
			Support.expect(checks, pixel.x >= 0 && pixel.y >= 0 && pixel.z >= 0 && pixel.x < 1e4 && pixel.y < 1e4 && pixel.z < 1e4)
		}
	}

	overhead: [3]f32 = {0, 1, 0}
	noon_zenith := sky_at(&shader, overhead, overhead)
	noon_horizon := sky_at(&shader, overhead, {1, 0.05, 0})
	Support.expect(checks, noon_zenith.z > noon_zenith.x * 1.3) // Rayleigh scattering favours blue.
	Support.expect(checks, noon_horizon.x / noon_horizon.z > noon_zenith.x / noon_zenith.z) // The horizon is whiter: a longer path scatters the blue away.

	sunset: [3]f32 = la.normalize([3]f32{1, 0.03, 0})
	toward_sun := sky_at(&shader, sunset, {1, 0.12, 0})
	away_from_sun := sky_at(&shader, sunset, {-1, 0.8, 0}) // High on the far side: the pink band hugs the horizon.
	Support.expect(checks, toward_sun.x > toward_sun.z) // Reddened at the sun.
	Support.expect(checks, away_from_sun.z > away_from_sun.x) // Blue opposite the sun.

	afternoon: [3]f32 = {0.7071, 0.7071, 0}
	near_sun := sky_at(&shader, afternoon, la.normalize([3]f32{0.9, 0.5, 0}))
	far_from_sun := sky_at(&shader, afternoon, {-0.3, 0.95, 0})
	Support.expect(checks, sky_luminance(near_sun) > sky_luminance(far_from_sun)) // Forward scattering brightens the sky toward the sun.

	night := sky_at(&shader, {0.866, -0.5, 0}, overhead)
	Support.expect(checks, sky_luminance(night) < 0.01 * sky_luminance(noon_zenith))
}

// Five boxes at x = -4, -2, 0, 2, 4 with layers 1..5, seen from above through a 64-pixel-wide strip. Each box must appear at
// its own place with its own layer; the gaps stay empty; fewer instances draw fewer boxes; none draws nothing.
// A second, smaller mesh sharing the same instance buffer (a shadow proxy) must land on exactly the same places.
check_instancing :: proc(checks: ^Support.Checks) {
	source := Procedural.Box_Create({0.5, 0.5, 0.5})
	defer Procedural.Mesh_Destroy(&source)
	proxy_source := Procedural.Box_Create({0.25, 0.25, 0.25})
	defer Procedural.Mesh_Destroy(&proxy_source)
	mesh := Render.Mesh_Upload_Instanced(source, 8)
	defer Render.Mesh_Destroy(&mesh)
	proxy := Render.Mesh_Upload_Instanced_Sharing(proxy_source, &mesh)
	defer Render.Mesh_Destroy(&proxy)
	shader, ok := GPU.Shader_Create("Tests/RenderCheck/Fixtures/InstanceProbe.glsl", nil, true)
	Support.expect(checks, ok)
	if !ok do return
	defer GPU.Shader_Destroy(&shader)
	target := GPU.Framebuffer_Create({64, 1, {.RGBA32F}, .None})
	defer GPU.Framebuffer_Destroy(&target)

	instances: [5]Render.Instance
	for index in 0 ..< 5 do instances[index] = Render.Instance{model = la.matrix4_translate_f32({f32(index) * 2 - 4, 0, 0}), material_layer = f32(index + 1)}
	centers := [5]int{6, 19, 32, 44, 57}
	gaps := [4]int{12, 25, 38, 51}

	for count in ([3]int{5, 3, 0}) {
		Render.Mesh_Set_Instances(&mesh, instances[:count])
		for drawn in ([2]^Render.Mesh{&mesh, &proxy}) {
			row := draw_instance_strip(&target, &shader, drawn)
			for center, index in centers {
				expected: f32 = f32(index + 1) / 10 if index < count else 0
				Support.expect(checks, abs(row[center].x - expected) < 1e-4)
			}
			for gap in gaps do Support.expect_value(checks, row[gap].x, 0)
		}
	}
}

draw_instance_strip :: proc(target: ^GPU.Framebuffer, shader: ^GPU.Shader, mesh: ^Render.Mesh) -> (row: [64][4]f32) {
	GPU.Framebuffer_Bind(target)
	gl.Disable(gl.CULL_FACE)
	gl.Disable(gl.DEPTH_TEST)
	gl.ClearColor(0, 0, 0, 0)
	gl.Clear(gl.COLOR_BUFFER_BIT)
	GPU.Shader_Use(shader)
	GPU.Shader_Set(shader, "u_ViewProjection", la.matrix_ortho3d_f32(-5, 5, -1, 1, -10, 10))
	Render.Mesh_Draw(mesh)
	GPU.Texture_Read_2D(&target.colors[0], row[:])
	return
}

// The look-up table is only a cache: sampled away from the sun and the horizon singularity it must match direct evaluation.
check_sky_lut :: proc(checks: ^Support.Checks) {
	shader, ok := GPU.Shader_Create("Tests/RenderCheck/Fixtures/SkyLutProbe.glsl", nil, true)
	Support.expect(checks, ok)
	if !ok do return
	defer GPU.Shader_Destroy(&shader)
	lut := Render.Sky_Lut_Create()
	defer Render.Sky_Lut_Destroy(&lut)
	pass := GPU.Fullscreen_Pass_Create()
	defer GPU.Fullscreen_Pass_Destroy(&pass)
	for sun_elevation_degrees in ([3]f32{60, 15, 3}) {
		elevation := math.to_radians(sun_elevation_degrees)
		to_sun := [3]f32{math.cos(elevation), math.sin(elevation), 0}
		Render.Sky_Lut_Render(&lut, to_sun, 20)
		for direction_elevation in ([3]f32{5, 25, 60}) {
			for azimuth_step in 0 ..< 8 {
				azimuth, lift := f32(azimuth_step) * math.PI / 4, math.to_radians(direction_elevation)
				direction := [3]f32{math.cos(lift) * math.cos(azimuth), math.sin(lift), math.cos(lift) * math.sin(azimuth)}
				if la.dot(la.normalize(direction), to_sun) > math.cos(math.to_radians(f32(20))) do continue // Skip the sun's glare.
				direct := sky_with_lut(&shader, &lut, to_sun, direction, 0)
				cached := sky_with_lut(&shader, &lut, to_sun, direction, 1)
				Support.expect(checks, abs(sky_luminance(cached) - sky_luminance(direct)) <= 0.08 * sky_luminance(direct) + 1e-4)
			}
		}
	}
}

sky_with_lut :: proc(shader: ^GPU.Shader, lut: ^Render.Sky_Lut, to_sun, direction: [3]f32, mode: i32) -> [3]f32 {
	GPU.Shader_Use(shader)
	GPU.Texture_Units_Reset()
	GPU.Shader_Set(shader, "u_SkyLut", GPU.Texture_Bind_Next(&lut.target.colors[0], GPU.Sampler_Linear_Repeat))
	GPU.Shader_Set(shader, "u_Mode", mode)
	GPU.Shader_Set(shader, "u_ToSun", to_sun)
	GPU.Shader_Set(shader, "u_Direction", direction)
	pixels := Support.Probe_Render(shader, 1, 1)
	defer delete(pixels)
	return pixels[0].xyz
}
