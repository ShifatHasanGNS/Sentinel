package main

import "../../Engine/GPU"
import "../../Engine/Platform"
import "../Support"
import "core:fmt"
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
