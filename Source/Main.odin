// Package main — SENTINEL entry point: window, GL context, main loop, mode
// switching, and input dispatch. Ties together `Library/Engine`,
// `Library/Geometry`, `Library/Scene`, and core:math/linalg (allowed
// directly, CLAUDE.md §2 item 3 — no separate hand-written math package);
// itself stays thin (Requirements.md §7, CLAUDE.md §8/§13).
//
// Session 0 status (CLAUDE.md/Plan.md roadmap "prep"): opened a GLFW +
// OpenGL 3.3 core-profile window and drew ONE throwaway triangle to prove
// the pipeline end-to-end, plus the --capture self-verification flag. This
// deliberately did NOT go through Library/Engine/Shader yet — that
// package's Shader.New expects one combined file with "#shader vertex"/
// "#shader fragment" markers, while Shaders/Scene.vert and Scene.frag were
// two separate files; vendor:OpenGL's own gl.load_shaders_file(vert, frag)
// matched that two-file layout in the meantime, with built-in compile/link
// error reporting.
//
// Session 1 status (roadmap step 1): the throwaway triangle was replaced by
// a rotating cube — still a temporary pipeline smoke test, proving the
// core:math/linalg conventions fixed in Library/Camera/Camera.odin (model
// matrix from matrix4_rotate, a fixed matrix4_look_at view, a
// matrix4_perspective projection) rather than just the draw call. See
// make_rotating_cube's own doc comment for why it generates 8 vertices/12
// triangles procedurally instead of a literal table.
//
// Session 1b status (roadmap step 1b, Engine integration): this file now
// draws through Library/Engine (Shader/VertexBuffer/IndexBuffer/
// VertexArray/VertexBufferLayout/Renderer) instead of ad-hoc gl.* calls —
// only glfw/window setup, GL state toggles (depth test, viewport, clear),
// and the capture flag still call vendor:OpenGL directly, since Engine has
// no window/context-management scope of its own. As part of this, the two
// shader files merged into Shaders/Scene.glsl to match Shader.New's
// required "#shader vertex"/"#shader fragment" combined-file format — see
// that file's own header for why.
//
// TODO(roadmap step 3): make_rotating_cube/generate_cube are a one-off
// pipeline smoke test (CLAUDE.md §2 item 5) — delete them and their call
// once Library/Geometry produces real meshes.
//
// Source/Input.odin (added once Inspection Mode exists, roadmap step 10):
// GLFW key/mouse callbacks, object selection, all interactive controls
// (CLAUDE.md §7's suggested key layout — Tab mode switch, P projection,
// 1/2/3 shading, C culling, Z depth test, [ ] select object, translate/
// rotate keys). Document the final key map in README.md, not just here.
//
// Source/Renderer.odin (grows alongside `Library/Engine/Renderer`, see that
// package's own known-limitation note): per-frame uniform upload for real
// scene objects, the single shared draw loop used by BOTH Patrol and
// Inspection modes (CLAUDE.md §2 item 9 — never fork rendering logic per
// mode). `Library/Engine/Renderer.Draw`'s one-VAO/IndexBuffer/Shader-triple
// design is left as-is until then — see PROGRESS.md for where it'll need
// to grow.
package main

import "core:fmt"
import "core:math"
import la "core:math/linalg"
import "core:os"
import "core:strconv"

import "vendor:glfw"
import gl "vendor:OpenGL"

import dbg "../Library/Engine/Debugger"
import ib "../Library/Engine/IndexBuffer"
import rd "../Library/Engine/Renderer"
import sd "../Library/Engine/Shader"
import va "../Library/Engine/VertexArray"
import vb "../Library/Engine/VertexBuffer"
import vbl "../Library/Engine/VertexBufferLayout"
import capture "../Debug"

// ---------------------------------------------------------------------------
// Window/GL conventions fixed here (see PROGRESS.md "Fixed conventions").
// Coordinate-system, matrix-layout, angle-unit, and rotation-direction
// conventions for core:math/linalg are now fixed in
// Library/Camera/Camera.odin (Session 1) — this file's model/view/
// projection matrices below follow those conventions exactly.
//   - OpenGL 3.3, core profile, forward-compatible (macOS requires forward
//     compatibility for any core-profile context above 3.2).
//   - Depth testing is enabled starting this session: the rotating cube is
//     the first genuinely 3D thing drawn here, and without a depth buffer
//     its own triangles would draw in whatever order the index buffer lists
//     them rather than nearest-to-camera order, making the cube look
//     "broken open" from most angles. GPU depth-buffer hidden-surface
//     removal is a syllabus topic in its own right (CLAUDE.md §4) with a
//     dedicated toggle/explanation due in roadmap step 8 — turning it on
//     now is just what a correct 3D draw already requires.
//   - Both future Patrol and Inspection modes share this one render path
//     (CLAUDE.md §2 item 9); nothing here branches on a mode yet because
//     there is no mode yet.
// ---------------------------------------------------------------------------

GL_VERSION_MAJOR :: 3
GL_VERSION_MINOR :: 3

DEFAULT_WINDOW_WIDTH :: 1280
DEFAULT_WINDOW_HEIGHT :: 720

// Cool, near-black clear colour — the fixed baseline "night sky" every
// session's lighting will be judged against.
CLEAR_COLOR :: [4]f32{0.02, 0.02, 0.05, 1.0}

COMBINED_SHADER_PATH :: "Shaders/Scene.glsl"

// Fixed camera for this session's smoke test — a real free-fly Camera comes
// in roadmap step 2 (Library/Camera). Eye position chosen so all three
// visible cube faces read clearly at once, which is what actually lets a
// screenshot prove the rotation and the winding/depth setup are correct.
CAMERA_EYE :: la.Vector3f32{2.5, 2.0, 4.0}
CAMERA_TARGET :: la.Vector3f32{0, 0, 0}
CAMERA_UP :: la.Vector3f32{0, 1, 0}

CAMERA_FOV_Y_DEGREES :: 45.0
CAMERA_NEAR :: 0.1
CAMERA_FAR :: 100.0

CUBE_HALF_EXTENT :: 0.75

// Degrees of rotation added per frame (converted to radians at use per the
// angle-unit convention in Library/Camera/Camera.odin — angle STATE stays
// in degrees only here, at this one human-facing edge). Frame-count-driven,
// not wall-clock time, so "--capture N ..." at two different N always
// reproduces the exact same rotation — useful for this session's visual
// check. A real delta-time clock arrives with free-fly movement in roadmap
// step 2.
CUBE_SPIN_DEGREES_PER_FRAME :: 1.0

// Deliberately NOT a coordinate axis: a cube has 90-degree rotational
// symmetry about any axis through opposite face centres (e.g. +Y), so
// spinning purely around +Y would make frame N and frame N+90 visually
// identical — a false negative for "did it actually rotate?" that bit this
// session's first capture. A tilted axis has no such small-integer
// symmetry, so any two different frame counts genuinely look different.
CUBE_SPIN_AXIS :: la.Vector3f32{0.4, 1, 0.3}

main :: proc() {
	capture_frames, capture_path, do_capture := parse_capture_flag(os.args[1:])

	if !glfw.Init() {
		fmt.eprintln("Failed to initialize GLFW")
		os.exit(1)
	}
	defer glfw.Terminate()

	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, GL_VERSION_MAJOR)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, GL_VERSION_MINOR)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
	glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, true)
	glfw.WindowHint(glfw.RESIZABLE, true)
	// A capture run has no one watching the window; hiding it avoids an
	// on-screen flash for a run that closes itself after N frames.
	glfw.WindowHint(glfw.VISIBLE, !do_capture)

	window := glfw.CreateWindow(DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT, "SENTINEL", nil, nil)
	if window == nil {
		fmt.eprintln("Failed to create GLFW window")
		os.exit(1)
	}
	defer glfw.DestroyWindow(window)

	glfw.MakeContextCurrent(window)
	glfw.SwapInterval(1)
	glfw.SetFramebufferSizeCallback(window, framebuffer_size_callback)
	glfw.SetKeyCallback(window, key_callback)

	gl.load_up_to(GL_VERSION_MAJOR, GL_VERSION_MINOR, glfw.gl_set_proc_address)

	fmt.printfln("GPU vendor:   %s", gl.GetString(gl.VENDOR))
	fmt.printfln("GPU renderer: %s", gl.GetString(gl.RENDERER))
	fmt.printfln("OpenGL:       %s", gl.GetString(gl.VERSION))
	fmt.printfln("GLSL:         %s", gl.GetString(gl.SHADING_LANGUAGE_VERSION))

	fb_width, fb_height := glfw.GetFramebufferSize(window)
	gl.Viewport(0, 0, fb_width, fb_height); dbg.GL_Check()

	gl.Enable(gl.DEPTH_TEST); dbg.GL_Check()

	cube_vertex_buffer, cube_index_buffer, cube_vertex_array, cube_layout := make_rotating_cube(CUBE_HALF_EXTENT)
	defer vb.Delete(&cube_vertex_buffer)
	defer vbl.Delete(&cube_layout)

	shader := sd.New(COMBINED_SHADER_PATH)
	if shader.RendererID == 0 {
		// sd.New already logged why (bad path, or a compile/link panic would
		// have already aborted the process before returning at all).
		fmt.eprintln("Failed to build the shader program; see the log above")
		os.exit(1)
	}
	fmt.printfln("Shader program linked: id=%d", shader.RendererID)

	cube_renderer := rd.New(&cube_vertex_array, &cube_index_buffer, &shader)
	defer rd.Delete(&cube_renderer)

	// Fixed for this smoke test (Library/Camera's real free-fly camera and
	// resize-aware projection arrive in roadmap step 2).
	view := la.matrix4_look_at(CAMERA_EYE, CAMERA_TARGET, CAMERA_UP)

	frame_count := 0
	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents()

		gl.ClearColor(CLEAR_COLOR.x, CLEAR_COLOR.y, CLEAR_COLOR.z, CLEAR_COLOR.w); dbg.GL_Check()
		gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT); dbg.GL_Check()

		// Re-read the framebuffer size each frame (not just in the resize
		// callback) so the aspect ratio used here can never go stale between
		// a resize event and the next projection matrix build.
		current_fb_width, current_fb_height := glfw.GetFramebufferSize(window)
		aspect := f32(current_fb_width) / f32(current_fb_height)
		projection := la.matrix4_perspective(math.to_radians(f32(CAMERA_FOV_Y_DEGREES)), aspect, CAMERA_NEAR, CAMERA_FAR)

		spin_angle := math.to_radians(f32(frame_count) * f32(CUBE_SPIN_DEGREES_PER_FRAME))
		model := la.matrix4_rotate(spin_angle, CUBE_SPIN_AXIS)

		// Composition order matches the column-vector convention recorded in
		// Library/Camera/Camera.odin: apply `model` first, then `view`, then
		// `projection`, to a point on the right.
		mvp := la.mul(projection, la.mul(view, model))

		sd.SetUniform(&shader, "u_MVP", &mvp)
		rd.Draw(&cube_renderer)

		frame_count += 1

		if do_capture && frame_count == capture_frames {
			if err := capture.Save_Screenshot(capture_path, int(fb_width), int(fb_height)); err != nil {
				fmt.eprintfln("Capture failed: %v", err)
				os.exit(1)
			}
			fmt.printfln("Captured frame %d/%d to %s", frame_count, capture_frames, capture_path)
			glfw.SetWindowShouldClose(window, true)
		}

		glfw.SwapBuffers(window)
	}
}

framebuffer_size_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
	gl.Viewport(0, 0, width, height)
}

key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
	if key == glfw.KEY_ESCAPE && action == glfw.PRESS {
		glfw.SetWindowShouldClose(window, true)
	}
}

// parse_capture_flag looks for "--capture <frames> <path>" anywhere in argv
// (there is nothing else to parse yet, so position doesn't matter). Exits
// the process on a malformed flag rather than silently ignoring it, since a
// typo'd capture request should never be mistaken for "capture disabled".
parse_capture_flag :: proc(args: []string) -> (frames: int, path: string, requested: bool) {
	for i := 0; i < len(args); i += 1 {
		if args[i] != "--capture" do continue

		if i + 2 >= len(args) {
			fmt.eprintln("--capture requires two arguments: <frames> <path>")
			os.exit(1)
		}

		parsed_frames, ok := strconv.parse_int(args[i + 1])
		if !ok || parsed_frames <= 0 {
			fmt.eprintfln("--capture: frame count must be a positive integer, got '%s'", args[i + 1])
			os.exit(1)
		}

		return parsed_frames, args[i + 2], true
	}

	return 0, "", false
}

// generate_cube computes a cube's 8 corners and 12 triangles (2 per face x
// 6 faces) entirely from a loop over sign/axis combinations — never a
// literal table of numbers (CLAUDE.md §2 item 5). This is a *miniature* of
// the same technique Library/Geometry.cube() will formalize properly in
// roadmap step 3 (which will also duplicate vertices per face for correct
// flat-shading normals); this throwaway version skips that because there is
// no lighting yet to need per-face normals.
//
// Corners are indexed 0-7 by a 3-bit code (bit 0 = +X, bit 1 = +Y, bit 2 =
// +Z) — a direct loop over sign combinations, not copied-in coordinates.
// Each face's 4 corners are found the same way: fix the bit for this face's
// axis, then walk the other two axes' bits in a fixed traversal order.
// That order is reversed for the two faces of a given axis (`pos_order` vs
// `neg_order`) so every face winds CCW when viewed from outside — verified
// by checking, for every generated triangle, that (v1-v0) x (v2-v0) points
// away from the cube's centre (see PROGRESS.md for that check).
generate_cube :: proc(half_extent: f32) -> (positions: [8]la.Vector3f32, indices: [36]u32) {
	for i in 0 ..< 8 {
		sign_x: f32 = -1 if i & 1 == 0 else 1
		sign_y: f32 = -1 if i & 2 == 0 else 1
		sign_z: f32 = -1 if i & 4 == 0 else 1
		positions[i] = la.Vector3f32{sign_x, sign_y, sign_z} * half_extent
	}

	pos_order := [4][2]uint{{0, 0}, {1, 0}, {1, 1}, {0, 1}}
	neg_order := [4][2]uint{{0, 1}, {1, 1}, {1, 0}, {0, 0}}

	index_i := 0
	for axis in 0 ..< 3 {
		u := uint((axis + 1) % 3)
		v := uint((axis + 2) % 3)

		for sign_bit in 0 ..< 2 {
			order := pos_order if sign_bit == 1 else neg_order

			corner: [4]u32
			for k in 0 ..< 4 {
				corner_index: uint = 0
				corner_index |= uint(sign_bit) << uint(axis)
				corner_index |= order[k][0] << u
				corner_index |= order[k][1] << v
				corner[k] = u32(corner_index)
			}

			indices[index_i + 0] = corner[0]
			indices[index_i + 1] = corner[1]
			indices[index_i + 2] = corner[2]
			indices[index_i + 3] = corner[0]
			indices[index_i + 4] = corner[2]
			indices[index_i + 5] = corner[3]
			index_i += 6
		}
	}

	return
}

// make_rotating_cube uploads generate_cube's output into Library/Engine
// buffer/array objects, ready for Library/Engine/Renderer.Draw. The
// returned VertexBuffer and VertexBufferLayout aren't referenced by
// anything else (VertexArray only stores a GL id, not a pointer back to the
// buffer/layout that described it), so the caller owns their cleanup
// separately from the Renderer built on top of the other two. Temporary
// pipeline smoke test — see the file header TODO to delete it once
// Library/Geometry exists.
make_rotating_cube :: proc(
	half_extent: f32,
) -> (
	vertex_buffer: vb.VertexBuffer,
	index_buffer: ib.IndexBuffer,
	vertex_array: va.VertexArray,
	layout: vbl.VertexBufferLayout,
) {
	positions, indices := generate_cube(half_extent)

	vertex_buffer = vb.New(positions[:])
	index_buffer = ib.New(indices[:])

	layout = vbl.New()
	vbl.Push(&layout, f32, 3, false) // a_Position: vec3

	vertex_array = va.New()
	va.AddBuffer(&vertex_array, &vertex_buffer, &layout)

	return
}
