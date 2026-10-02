package main

import "../../Engine/GPU"
import "../../Engine/Platform"
import "../../Engine/Render"
import "../Support"
import "core:fmt"
import "core:math"
import "core:os"

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
