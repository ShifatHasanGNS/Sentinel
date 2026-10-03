package Render

import "../GPU"
import gl "vendor:OpenGL"
import "core:math"
import "core:slice"
import la "core:math/linalg"

PARTICLES_MAX :: 3000

Particle_Kind :: enum {
	Smoke, // Alpha-blended, lit by the sun and sky.
	Fire,  // Additive and emissive (HDR), so the bloom makes it glow.
}

// One billboard. `life` runs 0 at birth to 1 at death and drives the dissolving edge (and, for fire, the cooling colour).
Particle :: struct {
	position: [3]f32,
	size:     f32, // Radius in meters.
	rotation: f32,
	life:     f32,
	seed:     f32,
	opacity:  f32,
	tint:     [3]f32, // Smoke colour (fire ignores it).
	kind:     Particle_Kind,
}

@(private = "file")
Particle_Vertex :: struct {
	center: [3]f32,
	corner: [2]f32,
	color:  [4]f32,
	params: [4]f32,
}

Particle_Renderer :: struct {
	smoke:    GPU.Shader,
	fire:     GPU.Shader,
	buffer:   GPU.Buffer,
	array:    u32,
	vertices: [dynamic]Particle_Vertex,
}

Particle_Renderer_Create :: proc() -> (renderer: Particle_Renderer, ok: bool) {
	renderer.smoke = GPU.Shader_Create("Shaders/Particles.glsl", nil, true) or_return
	renderer.fire = GPU.Shader_Create("Shaders/Particles.glsl", {"FIRE"}, true) or_return
	renderer.buffer = GPU.Buffer_Create_Empty(.Vertex, PARTICLES_MAX * 6 * size_of(Particle_Vertex), .Dynamic)
	gl.GenVertexArrays(1, &renderer.array)
	gl.BindVertexArray(renderer.array)
	gl.BindBuffer(gl.ARRAY_BUFFER, renderer.buffer.id)
	stride := i32(size_of(Particle_Vertex))
	gl.EnableVertexAttribArray(0)
	gl.VertexAttribPointer(0, 3, gl.FLOAT, false, stride, 0)
	gl.EnableVertexAttribArray(1)
	gl.VertexAttribPointer(1, 2, gl.FLOAT, false, stride, uintptr(12))
	gl.EnableVertexAttribArray(2)
	gl.VertexAttribPointer(2, 4, gl.FLOAT, false, stride, uintptr(20))
	gl.EnableVertexAttribArray(3)
	gl.VertexAttribPointer(3, 4, gl.FLOAT, false, stride, uintptr(36))
	gl.BindVertexArray(0)
	GPU.GL_Check()
	return renderer, true
}

Particle_Renderer_Destroy :: proc(renderer: ^Particle_Renderer) {
	delete(renderer.vertices)
	gl.DeleteVertexArrays(1, &renderer.array)
	GPU.Buffer_Destroy(&renderer.buffer)
	GPU.Shader_Destroy(&renderer.fire)
	GPU.Shader_Destroy(&renderer.smoke)
}

@(private = "file")
append_quad :: proc(vertices: ^[dynamic]Particle_Vertex, particle: Particle) {
	color := [4]f32{particle.tint.x, particle.tint.y, particle.tint.z, particle.opacity}
	params := [4]f32{particle.life, particle.seed, particle.size, particle.rotation}
	corners := [4][2]f32{{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}
	for index in ([6]int{0, 1, 2, 0, 2, 3}) do append(vertices, Particle_Vertex{particle.position, corners[index], color, params})
}

// Draws the particles into the lit HDR image (bound by the caller). Smoke first, farthest to nearest so overlapping puffs blend in
// the right order (alpha blending is not commutative); then fire, additive and therefore order-independent. Both test against the
// scene's depth in the shader, so no depth attachment is needed on the HDR target.
Particle_Renderer_Draw :: proc(renderer: ^Particle_Renderer, particles: []Particle, frame: Frame, depth: ^GPU.Texture, width, height: i32) {
	if len(particles) == 0 do return
	count := min(len(particles), PARTICLES_MAX)
	sorted := make([]Particle, count, context.temp_allocator)
	copy(sorted, particles[:count])
	camera := frame.camera
	distance_squared :: proc(particle: Particle, eye: [3]f32) -> f32 {
		offset := particle.position - eye
		return la.dot(offset, offset)
	}
	eye := camera.position
	slice.sort_by_with_data(sorted, proc(a, b: Particle, data: rawptr) -> bool {
		eye := (^[3]f32)(data)^
		return distance_squared(a, eye) > distance_squared(b, eye)
	}, &eye)
	gl.Disable(gl.DEPTH_TEST)
	gl.Disable(gl.CULL_FACE)
	gl.Enable(gl.BLEND)
	gl.DepthMask(false)
	draw_kind(renderer, &renderer.smoke, sorted, .Smoke, frame, depth, width, height, true)
	draw_kind(renderer, &renderer.fire, sorted, .Fire, frame, depth, width, height, false)
	gl.Disable(gl.BLEND)
	gl.DepthMask(true)
	GPU.GL_Check()
}

@(private = "file")
draw_kind :: proc(renderer: ^Particle_Renderer, shader: ^GPU.Shader, particles: []Particle, kind: Particle_Kind, frame: Frame, depth: ^GPU.Texture, width, height: i32, alpha_blend: bool) {
	clear(&renderer.vertices)
	for particle in particles do if particle.kind == kind do append_quad(&renderer.vertices, particle)
	if len(renderer.vertices) == 0 do return
	GPU.Buffer_Write(&renderer.buffer, renderer.vertices[:])
	if alpha_blend do gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
	else do gl.BlendFunc(gl.ONE, gl.ONE)
	camera := frame.camera
	right := [3]f32{camera.view[0, 0], camera.view[0, 1], camera.view[0, 2]}
	up := [3]f32{camera.view[1, 0], camera.view[1, 1], camera.view[1, 2]}
	GPU.Shader_Use(shader)
	GPU.Texture_Units_Reset()
	GPU.Shader_Set(shader, "u_Depth", GPU.Texture_Bind_Next(depth, GPU.Sampler_Nearest_Clamp))
	GPU.Shader_Set(shader, "u_ViewProjection", camera.view_projection)
	GPU.Shader_Set(shader, "u_InverseViewProjection", la.inverse(camera.view_projection))
	GPU.Shader_Set(shader, "u_CameraRight", right)
	GPU.Shader_Set(shader, "u_CameraUp", up)
	GPU.Shader_Set(shader, "u_CameraForward", camera.forward)
	GPU.Shader_Set(shader, "u_CameraPosition", camera.position)
	GPU.Shader_Set(shader, "u_ScreenSize", [2]f32{f32(width), f32(height)})
	GPU.Shader_Set(shader, "u_SunDirection", frame.sky.to_sun)
	GPU.Shader_Set(shader, "u_SunLight", frame.sun.color * frame.sun.intensity * 0.11 * math.max(frame.sky.to_sun.y, 0.05))
	sky := frame.sky.zenith * 0.9 + frame.sky.horizon * 0.4 + 0.015
	grey := la.dot(sky, [3]f32{0.3, 0.59, 0.11}) // Smoke is mostly grey whatever the sky: keep 40% of the sky's colour, not all of it.
	GPU.Shader_Set(shader, "u_SkyLight", [3]f32{grey, grey, grey} * 0.6 + sky * 0.4)
	GPU.Shader_Set(shader, "u_Time", f32(0))
	gl.BindVertexArray(renderer.array)
	gl.DrawArrays(gl.TRIANGLES, 0, i32(len(renderer.vertices)))
	gl.BindVertexArray(0)
}
