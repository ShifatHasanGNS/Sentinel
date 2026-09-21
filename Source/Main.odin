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
// Session 2 status (roadmap step 2, Library/Camera): the fixed matrix4_
// look_at/matrix4_perspective pair from Session 1 is replaced by a real
// Library/Camera.Camera driven by free-fly input polled here every frame
// (WASD move, mouse look with the cursor captured, Q/E world up/down,
// Shift to sprint, P to toggle perspective/orthographic, scroll wheel to
// zoom the orthographic volume) — see the key/cursor/scroll handling in
// main() below and Library/Camera/Camera.odin for why the GLFW-facing glue
// lives here rather than in the Camera package. A second temporary mesh,
// generate_grid, was added alongside generate_cube so both projections have
// something to visually compare (parallel ground-grid lines stay parallel
// in orthographic, converge in perspective) — see that proc's own comment.
// Interactive input is skipped entirely during a --capture run so captures
// stay reproducible regardless of the real system cursor/keyboard state;
// --projection lets a capture run choose its starting projection instead.
//
// TODO(roadmap step 3): generate_cube/generate_grid/box_corners_and_
// triangles and their make_* callers are a one-off pipeline smoke test
// (CLAUDE.md §2 item 5) — delete them and their calls once Library/Geometry
// produces real meshes.
//
// Source/Input.odin (added once Inspection Mode exists, roadmap step 10):
// GLFW key/mouse callbacks, object selection, and the remaining interactive
// controls this session doesn't need yet (CLAUDE.md §7's suggested key
// layout — Tab mode switch, 1/2/3 shading, C culling, Z depth test, [ ]
// select object, translate/rotate keys). The free-fly camera controls and
// P projection toggle added this session stay in this file for now since
// there's no mode/selection state yet to justify splitting them out; that
// split can happen alongside roadmap step 10 if this file gets crowded.
// Document the final key map in README.md, not just here.
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

import cam "../Library/Camera"

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

// Starting eye position and look target for this session's free-fly
// Camera (Library/Camera.Camera_Looking_At) — chosen so both the ground
// grid and the rotating cube are comfortably in frame at startup. Lens
// parameters (FOV/near/far) now live on the Camera itself
// (Library/Camera.Default_Camera), not here.
CAMERA_START_EYE :: la.Vector3f32{6.0, 2.5, 8.0}

// Also passed to Toggle_Projection each time (CLAUDE.md §7: the
// orthographic volume is sized from the camera's distance to this point),
// so the framing stays sensible across a projection toggle regardless of
// where free-fly movement has since taken the camera.
SCENE_FOCUS :: la.Vector3f32{0, 0, 0}

CUBE_HALF_EXTENT :: 0.75

// Degrees of rotation added per frame (converted to radians at use per the
// angle-unit convention in Library/Camera/Camera.odin — angle STATE stays
// in degrees only here, at this one human-facing edge). Frame-count-driven,
// not wall-clock time, so "--capture N ..." at two different N always
// reproduces the exact same rotation — useful for this session's visual
// check. Free-fly camera movement (added this session) DOES use a real
// delta-time clock (`dt_seconds` in main()'s loop below); only the cube's
// spin stays frame-counted, since that's what keeps --capture reproducible.
CUBE_SPIN_DEGREES_PER_FRAME :: 1.0

// Deliberately NOT a coordinate axis: a cube has 90-degree rotational
// symmetry about any axis through opposite face centres (e.g. +Y), so
// spinning purely around +Y would make frame N and frame N+90 visually
// identical — a false negative for "did it actually rotate?" that bit this
// session's first capture. A tilted axis has no such small-integer
// symmetry, so any two different frame counts genuinely look different.
CUBE_SPIN_AXIS :: la.Vector3f32{0.4, 1, 0.3}

// Ground-grid parameters (Session 2 test scene, see generate_grid's own
// comment for why it's built as thin triangle "bars" instead of GL_LINES).
// GRID_HALF_EXTENT of 5 with GRID_LINE_COUNT of 11 gives an 11x11 grid of
// lines, i.e. 10x10 grid CELLS spanning -5..+5 on both X and Z, per the
// task's "10x10 ground grid." GRID_Y_OFFSET sits it comfortably below the
// rotating cube's largest possible bounding extent
// (CUBE_HALF_EXTENT * sqrt(3), for a corner-on rotation) so the cube never
// visually clips through the grid at any spin angle.
GRID_HALF_EXTENT :: 5.0
GRID_LINE_COUNT :: 11
GRID_BAR_HALF_WIDTH :: 0.025
GRID_Y_OFFSET :: -1.5

main :: proc() {
	capture_frames, capture_path, do_capture := parse_capture_flag(os.args[1:])
	start_projection := parse_projection_flag(os.args[1:])

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
	glfw.SetScrollCallback(window, scroll_callback)

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

	grid_vertex_buffer, grid_index_buffer, grid_vertex_array, grid_layout := make_grid(GRID_HALF_EXTENT, GRID_LINE_COUNT, GRID_BAR_HALF_WIDTH)
	defer vb.Delete(&grid_vertex_buffer)
	defer vbl.Delete(&grid_layout)

	shader := sd.New(COMBINED_SHADER_PATH)
	if shader.RendererID == 0 {
		// sd.New already logged why (bad path, or a compile/link panic would
		// have already aborted the process before returning at all).
		fmt.eprintln("Failed to build the shader program; see the log above")
		os.exit(1)
	}
	fmt.printfln("Shader program linked: id=%d", shader.RendererID)

	// Both renderers share one Shader (there is only one, trivial, shared
	// material so far). Renderer.Delete deletes ALL THREE of its fields,
	// including the Shader — sharing one Shader pointer across two
	// Renderers and calling Delete on both would double-delete it (a real
	// bug: Shader.Delete frees shader.FilePath's backing memory, so a
	// second call is a double-free, not just a harmless redundant GL call).
	// cube_renderer owns the shared shader's cleanup; the grid's own
	// VertexArray/IndexBuffer are deleted directly instead of through
	// rd.Delete, exactly like cube_vertex_buffer/cube_layout above are
	// already deleted directly rather than through the Renderer.
	cube_renderer := rd.New(&cube_vertex_array, &cube_index_buffer, &shader)
	defer rd.Delete(&cube_renderer)

	grid_renderer := rd.New(&grid_vertex_array, &grid_index_buffer, &shader)
	defer va.Delete(&grid_vertex_array)
	defer ib.Delete(&grid_index_buffer)

	camera := cam.Camera_Looking_At(CAMERA_START_EYE, SCENE_FOCUS)
	if start_projection == .Orthographic {
		// Reuses Toggle_Projection's perspective -> orthographic sync
		// (CLAUDE.md §7's "roughly the same framing" requirement) instead
		// of duplicating its distance/fov_y formula here.
		cam.Toggle_Projection(&camera, SCENE_FOCUS)
	}

	// Cursor capture and live input are both skipped for a --capture run:
	// there's no one to move the mouse, but GLFW would still report
	// whatever the real system cursor happens to be doing, which would
	// make captured frames depend on host-machine state instead of purely
	// on --capture's frame count — breaking the reproducibility the
	// --capture flag exists for (CLAUDE.md §1.2). --projection above is
	// the supported way to change a capture run's starting view.
	last_cursor_x, last_cursor_y: f64
	if !do_capture {
		glfw.SetInputMode(window, glfw.CURSOR, glfw.CURSOR_DISABLED)
		last_cursor_x, last_cursor_y = glfw.GetCursorPos(window)
	}

	frame_count := 0
	last_frame_time := glfw.GetTime()
	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents()

		current_time := glfw.GetTime()
		dt_seconds := f32(current_time - last_frame_time)
		last_frame_time = current_time

		if !do_capture {
			cursor_x, cursor_y := glfw.GetCursorPos(window)
			cam.Apply_Look_Delta(&camera, f32(cursor_x - last_cursor_x), f32(cursor_y - last_cursor_y))
			last_cursor_x, last_cursor_y = cursor_x, cursor_y

			move_forward := key_axis(window, glfw.KEY_W, glfw.KEY_S)
			move_right := key_axis(window, glfw.KEY_D, glfw.KEY_A)
			move_up := key_axis(window, glfw.KEY_E, glfw.KEY_Q)
			sprint := glfw.GetKey(window, glfw.KEY_LEFT_SHIFT) == glfw.PRESS || glfw.GetKey(window, glfw.KEY_RIGHT_SHIFT) == glfw.PRESS
			cam.Apply_Move(&camera, move_forward, move_right, move_up, dt_seconds, sprint)

			if projection_toggle_requested {
				cam.Toggle_Projection(&camera, SCENE_FOCUS)
				projection_toggle_requested = false
			}

			if camera.projection == .Orthographic && scroll_delta_y != 0 {
				cam.Zoom_Ortho(&camera, scroll_delta_y)
			}
			scroll_delta_y = 0
		}

		gl.ClearColor(CLEAR_COLOR.x, CLEAR_COLOR.y, CLEAR_COLOR.z, CLEAR_COLOR.w); dbg.GL_Check()
		gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT); dbg.GL_Check()

		// Re-read the framebuffer size each frame (not just in the resize
		// callback) so the aspect ratio used here can never go stale between
		// a resize event and the next projection matrix build.
		current_fb_width, current_fb_height := glfw.GetFramebufferSize(window)
		aspect := f32(current_fb_width) / f32(current_fb_height)

		view := cam.View_Matrix(&camera)
		projection := cam.Projection_Matrix(&camera, aspect)

		spin_angle := math.to_radians(f32(frame_count) * f32(CUBE_SPIN_DEGREES_PER_FRAME))
		cube_model := la.matrix4_rotate(spin_angle, CUBE_SPIN_AXIS)
		grid_model := la.matrix4_translate(la.Vector3f32{0, GRID_Y_OFFSET, 0})

		// Composition order matches the column-vector convention recorded in
		// Library/Camera/Camera.odin: apply `model` first, then `view`, then
		// `projection`, to a point on the right.
		grid_mvp := la.mul(projection, la.mul(view, grid_model))
		sd.SetUniform(&shader, "u_MVP", &grid_mvp)
		rd.Draw(&grid_renderer)

		cube_mvp := la.mul(projection, la.mul(view, cube_model))
		sd.SetUniform(&shader, "u_MVP", &cube_mvp)
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

// projection_toggle_requested and scroll_delta_y are read/consumed once per
// frame in main()'s loop (see the `!do_capture` block above). GLFW's `"c"`
// callback procs can't capture Odin closures, and there's exactly one
// window/one camera in this program, so a package-level variable is the
// simplest way to hand a callback-driven event to the poll-driven main
// loop — the same reasoning key_callback below already applies to
// window-close-on-ESC, just via glfw.SetWindowShouldClose instead of a
// variable of our own.
projection_toggle_requested: bool
scroll_delta_y: f32

key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
	if key == glfw.KEY_ESCAPE && action == glfw.PRESS {
		glfw.SetWindowShouldClose(window, true)
	}
	if key == glfw.KEY_P && action == glfw.PRESS {
		projection_toggle_requested = true
	}
}

scroll_callback :: proc "c" (window: glfw.WindowHandle, x_offset, y_offset: f64) {
	// Accumulates rather than overwrites: GLFW can deliver more than one
	// scroll event between two PollEvents() calls (e.g. a fast trackpad
	// swipe), and main()'s loop only drains this once per frame.
	scroll_delta_y += f32(y_offset)
}

// key_axis reads a pair of opposing keys (e.g. W/S) and returns +1, -1, or
// 0 — the single-frame movement input Library/Camera.Apply_Move expects
// per axis. Both pressed at once cancels out to 0 rather than picking one
// arbitrarily.
key_axis :: proc(window: glfw.WindowHandle, positive_key, negative_key: i32) -> f32 {
	axis: f32 = 0
	if glfw.GetKey(window, positive_key) == glfw.PRESS do axis += 1
	if glfw.GetKey(window, negative_key) == glfw.PRESS do axis -= 1
	return axis
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

// parse_projection_flag looks for "--projection <perspective|orthographic>"
// anywhere in argv. Defaults to Perspective when absent, matching the
// camera's own Default_Camera default — a --capture run with no flag at
// all should look identical to how this project's captures have always
// looked. Exits on a malformed/unknown value for the same reason
// parse_capture_flag does: a typo here should never be silently ignored.
parse_projection_flag :: proc(args: []string) -> cam.Projection_Mode {
	for i := 0; i < len(args); i += 1 {
		if args[i] != "--projection" do continue

		if i + 1 >= len(args) {
			fmt.eprintln("--projection requires one argument: <perspective|orthographic>")
			os.exit(1)
		}

		switch args[i + 1] {
		case "perspective":
			return .Perspective
		case "orthographic":
			return .Orthographic
		case:
			fmt.eprintfln("--projection: expected 'perspective' or 'orthographic', got '%s'", args[i + 1])
			os.exit(1)
		}
	}

	return .Perspective
}

// box_corners_and_triangles computes one box's 8 corner positions (centred
// at `center`, independent half-extents per axis so it can describe both a
// cube and a long thin "bar") and its 12 CCW-front-facing triangles (2 per
// face x 6 faces), entirely from a loop over sign/axis combinations — never
// a literal table of numbers (CLAUDE.md §2 item 5). Factored out of what
// was Session 1's generate_cube so both make_rotating_cube's cube and this
// session's generate_grid (a mesh made of many thin boxes) share ONE
// already-verified winding computation instead of two copies that could
// drift apart — a winding bug here would silently break both back-face
// culling and lighting later (CLAUDE.md §2.1's culling item), so keeping it
// in one place matters more than keeping this proc small. This is a
// *miniature* of the same technique Library/Geometry.cube() will formalize
// properly in roadmap step 3 (which will also duplicate vertices per face
// for correct flat-shading normals); this throwaway version skips that
// because there is no lighting yet to need per-face normals.
//
// Corners are indexed 0-7 by a 3-bit code (bit 0 = +X, bit 1 = +Y, bit 2 =
// +Z) — a direct loop over sign combinations, not copied-in coordinates.
// Each face's 4 corners are found the same way: fix the bit for this face's
// axis, then walk the other two axes' bits in a fixed traversal order.
// That order is reversed for the two faces of a given axis (`pos_order` vs
// `neg_order`) so every face winds CCW when viewed from outside — verified
// by checking, for every generated triangle, that (v1-v0) x (v2-v0) points
// away from the box's centre (see PROGRESS.md for that check).
box_corners_and_triangles :: proc(center: la.Vector3f32, half_extents: la.Vector3f32) -> (positions: [8]la.Vector3f32, indices: [36]u32) {
	for i in 0 ..< 8 {
		sign_x: f32 = -1 if i & 1 == 0 else 1
		sign_y: f32 = -1 if i & 2 == 0 else 1
		sign_z: f32 = -1 if i & 4 == 0 else 1
		positions[i] = center + la.Vector3f32{sign_x, sign_y, sign_z} * half_extents
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

// generate_cube is box_corners_and_triangles specialised to a cube centred
// at the origin — kept as its own proc since make_rotating_cube's callers
// only ever want that one shape.
generate_cube :: proc(half_extent: f32) -> (positions: [8]la.Vector3f32, indices: [36]u32) {
	return box_corners_and_triangles(la.Vector3f32{0, 0, 0}, la.Vector3f32{half_extent, half_extent, half_extent})
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

// generate_grid builds a square ground grid as ONE combined triangle mesh:
// each grid line is a thin box ("bar") appended via
// box_corners_and_triangles, so the whole grid draws through the same
// GL_TRIANGLES + IndexBuffer path Library/Engine/Renderer.Draw already
// supports. A real 1px-wide GL_LINES grid would need Draw to accept a
// different GL primitive type, which is exactly the kind of Renderer
// extension CLAUDE.md §13.2/PROGRESS.md defer to "whichever session
// actually needs it" — this sidesteps that entirely by staying
// triangles-only, at the cost of the bars having a small width instead of
// being 1px lines (GRID_BAR_HALF_WIDTH controls that width).
//
// half_extent is the distance from the grid's centre to its outer edge;
// line_count is how many bars run in EACH direction (so line_count - 1 grid
// cells per axis, matching the task's "10x10 ground grid" via
// GRID_LINE_COUNT = 11). Nothing here is a literal position table: every
// bar's centre comes from an even-spacing formula over line_count,
// evaluated fresh on every call — never a stored/cached list of positions
// (CLAUDE.md §2 item 5).
generate_grid :: proc(half_extent: f32, line_count: int, bar_half_width: f32) -> (positions: [dynamic]la.Vector3f32, indices: [dynamic]u32) {
	assert(line_count >= 2, "generate_grid: line_count must be at least 2 (one cell)")

	spacing := (2 * half_extent) / f32(line_count - 1)

	for i in 0 ..< line_count {
		offset := -half_extent + f32(i) * spacing

		// A bar running along Z at fixed X = offset, and one running along
		// X at fixed Z = offset — together these two are one "+" of the
		// grid at this offset; the full loop draws all of them.
		append_box(&positions, &indices, la.Vector3f32{offset, 0, 0}, la.Vector3f32{bar_half_width, bar_half_width, half_extent})
		append_box(&positions, &indices, la.Vector3f32{0, 0, offset}, la.Vector3f32{half_extent, bar_half_width, bar_half_width})
	}

	return
}

// append_box appends one box_corners_and_triangles box's vertices/indices
// onto growing mesh arrays, offsetting the new indices by the arrays'
// current vertex count so multiple boxes combine into one valid indexed
// mesh instead of each box separately indexing from 0.
append_box :: proc(positions: ^[dynamic]la.Vector3f32, indices: ^[dynamic]u32, center: la.Vector3f32, half_extents: la.Vector3f32) {
	base_index := u32(len(positions))

	box_positions, box_indices := box_corners_and_triangles(center, half_extents)
	append(positions, ..box_positions[:])
	for box_index in box_indices {
		append(indices, base_index + box_index)
	}
}

// make_grid mirrors make_rotating_cube: uploads generate_grid's output into
// Library/Engine buffer/array objects. Temporary pipeline smoke test — see
// the file header TODO to delete it once Library/Geometry exists.
make_grid :: proc(
	half_extent: f32,
	line_count: int,
	bar_half_width: f32,
) -> (
	vertex_buffer: vb.VertexBuffer,
	index_buffer: ib.IndexBuffer,
	vertex_array: va.VertexArray,
	layout: vbl.VertexBufferLayout,
) {
	positions, indices := generate_grid(half_extent, line_count, bar_half_width)
	defer delete(positions)
	defer delete(indices)

	vertex_buffer = vb.New(positions[:])
	index_buffer = ib.New(indices[:])

	layout = vbl.New()
	vbl.Push(&layout, f32, 3, false) // a_Position: vec3

	vertex_array = va.New()
	va.AddBuffer(&vertex_array, &vertex_buffer, &layout)

	return
}
