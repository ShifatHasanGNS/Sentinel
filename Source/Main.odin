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
// lives here rather than in the Camera package. Interactive input is
// skipped entirely during a --capture run so captures stay reproducible
// regardless of the real system cursor/keyboard state; --projection lets a
// capture run choose its starting projection instead.
//
// Session 3 status (roadmap step 3, Library/Geometry): Session 1/2's
// temporary smoke-test generators (generate_cube, box_corners_and_
// triangles, generate_grid, and their make_* upload helpers) are DELETED —
// Library/Geometry.Mesh now owns generation AND GL upload, so this file no
// longer builds vertex/index arrays or Engine buffers by hand at all. In
// their place, build_gallery below is this session's OWN temporary scene
// (also slated for deletion, once the real 9 objects exist): the three base
// primitives shown standalone plus two shapes composed at runtime from Cube
// instances via Geometry.Append_Mesh (a box-ring "cylinder" and a
// tapering-stack "cone") — see build_gallery's own comment. Back-face
// culling is turned on for the first time in this project
// (gl.Enable(gl.CULL_FACE)) purely as a self-verification aid: a winding
// bug in any generator shows up immediately as missing faces in a capture.
// This is NOT yet roadmap step 8's toggleable culling feature — no debug
// key exists to turn it off, and step 8 will likely add a manual
// normal-based culling test to compare against this GL-native one; see
// PROGRESS.md.
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
import geo "../Library/Geometry"

import dbg "../Library/Engine/Debugger"
import sd "../Library/Engine/Shader"
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
// Camera (Library/Camera.Camera_Looking_At) — chosen so the whole gallery
// row below (GALLERY_OBJECT_COUNT objects, GALLERY_SPACING apart) is
// comfortably in frame at startup. Lens parameters (FOV/near/far) now live
// on the Camera itself (Library/Camera.Default_Camera), not here.
CAMERA_START_EYE :: la.Vector3f32{0.0, 5.0, 16.0}

// Also passed to Toggle_Projection each time (CLAUDE.md §7: the
// orthographic volume is sized from the camera's distance to this point),
// so the framing stays sensible across a projection toggle regardless of
// where free-fly movement has since taken the camera.
SCENE_FOCUS :: la.Vector3f32{0, 0, 0}

// Gallery parameters (Session 3 self-verification scene — see
// build_gallery's own comment). Object slot positions come from a formula
// over the index/spacing below, never a literal position table (CLAUDE.md
// §2 item 5).
GALLERY_OBJECT_COUNT :: 5
GALLERY_SPACING :: 4.0

// Box-ring "cylinder" composition parameters (CLAUDE.md §2 item 6's own
// example: "a low-poly cylinder is really N box... instances arranged in a
// ring by a runtime loop computing a rotation matrix per segment").
// Segment RADIAL thickness/height are free choices, but the TANGENTIAL
// width is NOT — it's derived in build_ring from RING_RADIUS/
// RING_SEGMENT_COUNT (the chord length between adjacent segment centres),
// not a separate hand-picked constant. A first version picked an
// independent tangential-width constant that didn't actually match this
// count/radius, leaving visible gaps between segments in
// Debug/Captures/session3_gallery.bmp — see build_ring's own comment.
RING_SEGMENT_COUNT :: 10
RING_RADIUS :: 0.8
RING_SEGMENT_RADIAL_THICKNESS :: 0.5
RING_SEGMENT_HEIGHT :: 1.2
// >1 so neighbouring segments overlap slightly rather than just barely
// touching edge-to-edge, where floating-point rounding could reopen a
// hairline gap.
SEGMENT_OVERLAP_FACTOR :: 1.3

// Tapering-stack "cone" composition parameters: several ring LEVELS
// stacked upward with shrinking radius, built via the exact same
// runtime-transformed-Cube technique as the ring above, not a dedicated
// cone() generator (CLAUDE.md §2 item 6). Segments are sized for the BASE
// level (its widest, sparsest ring) and reused at every level — smaller
// levels end up with MORE overlap, not gaps, which is the safe direction
// to be wrong in.
CONE_LEVEL_COUNT :: 6
CONE_SEGMENTS_PER_LEVEL :: 8
CONE_BASE_RADIUS :: 1.0
CONE_LEVEL_HEIGHT :: 0.35
CONE_SEGMENT_RADIAL_THICKNESS :: 0.35

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

	// Self-verification aid for this session (see the file header's
	// "Session 3 status" for why this isn't yet roadmap step 8's
	// toggleable culling feature): CCW-wound front faces, back faces
	// culled — a winding bug in any Geometry generator shows up as a
	// missing face in a capture rather than silently going unnoticed.
	gl.Enable(gl.CULL_FACE); dbg.GL_Check()
	gl.CullFace(gl.BACK); dbg.GL_Check()
	gl.FrontFace(gl.CCW); dbg.GL_Check()

	gallery := build_gallery()
	defer for &mesh in gallery {
		geo.Destroy(&mesh)
	}

	shader := sd.New(COMBINED_SHADER_PATH)
	if shader.RendererID == 0 {
		// sd.New already logged why (bad path, or a compile/link panic would
		// have already aborted the process before returning at all).
		fmt.eprintln("Failed to build the shader program; see the log above")
		os.exit(1)
	}
	fmt.printfln("Shader program linked: id=%d", shader.RendererID)
	defer sd.Delete(&shader)

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

		// The gallery is static this session (no rotation) — it exists to
		// visually verify winding/normals via culling, not to demo
		// animation. Composition order matches the column-vector
		// convention recorded in Library/Camera/Camera.odin: apply `model`
		// first, then `view`, then `projection`, to a point on the right.
		for &mesh, i in gallery {
			model := la.matrix4_translate(gallery_slot_position(i))
			mvp := la.mul(projection, la.mul(view, model))
			sd.SetUniform(&shader, "u_MVP", &mvp)
			geo.Draw(&mesh, &shader)
		}

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

// build_gallery constructs this session's temporary self-verification
// scene (slated for deletion once the real 9 objects exist, same as the
// rotating cube/grid it replaces): the three base primitives (Cube,
// Tetrahedron, Plane) shown standalone, plus two shapes composed at
// runtime from many Cube instances via Geometry.Append_Mesh (a box-ring
// "cylinder" and a tapering-stack "cone") — CLAUDE.md §2 item 6's "no
// cylinder()/cone() generator" constraint made concrete: build_ring/
// build_cone below are NOT new Geometry generators, just runtime loops
// over Cube + Append_Mesh calls, living here in SENTINEL-specific code
// where composite objects belong. Every returned Mesh is already
// Upload()ed, ready to Draw immediately. Gallery slot positions come from
// gallery_slot_position's formula over GALLERY_OBJECT_COUNT, never a
// literal position table (CLAUDE.md §2 item 5).
build_gallery :: proc() -> [GALLERY_OBJECT_COUNT]geo.Mesh {
	gallery: [GALLERY_OBJECT_COUNT]geo.Mesh

	gallery[0] = geo.Cube(1.4, 1.4, 1.4)
	gallery[1] = geo.Tetrahedron(1.6)
	gallery[2] = geo.Plane(1.6, 1.6)
	gallery[3] = build_ring()
	gallery[4] = build_cone()

	for &mesh in gallery {
		geo.Upload(&mesh)
	}

	return gallery
}

// gallery_slot_position spaces GALLERY_OBJECT_COUNT objects GALLERY_SPACING
// apart along X, centred on the origin — a formula over `index`, not a
// literal table (CLAUDE.md §2 item 5).
gallery_slot_position :: proc(index: int) -> la.Vector3f32 {
	center_index := f32(GALLERY_OBJECT_COUNT - 1) * 0.5
	return la.Vector3f32{(f32(index) - center_index) * GALLERY_SPACING, 0, 0}
}

// build_ring composes a "cylinder" from RING_SEGMENT_COUNT small Cube
// instances placed around a circle, each by its own runtime-computed
// rotation+translation matrix (CLAUDE.md §2 item 6). `segment` is built
// once and reused as the Append_Mesh SOURCE for every instance — it is
// never itself uploaded/drawn, so it's destroyed right after the loop
// that reads it, rather than returned.
//
// Composition order matters here: each instance's transform is
// rotate_y(angle) * translate(RADIUS, 0, 0), i.e. offset the segment out
// along local +X FIRST, then rotate that whole (segment + offset) rigid
// body about Y — this sweeps each segment to its point on the circle
// while ALSO carrying its own orientation around with it, so every
// segment's local +X face ends up pointing radially outward, the same way
// relative to the ring at every angle. The reversed order (rotate the
// segment's own shape by `angle`, then translate by a separately-computed
// (cos, sin) point on the circle) looks similar but is NOT the same
// transform — it decouples the segment's orientation from its position on
// the circle, so segments no longer face a consistent direction relative
// to their neighbours. This was tried first and produced a visibly
// gap-riddled ring in Debug/Captures/session3_gallery.bmp before being
// caught and fixed here — see PROGRESS.md.
//
// tangential_width is the OTHER thing that turned out load-bearing: it's
// the chord length between two adjacent segment centres at RING_RADIUS
// (2 * R * sin(pi / count), standard regular-polygon chord formula),
// scaled up slightly by SEGMENT_OVERLAP_FACTOR. A first version used a
// fixed width unrelated to this count/radius and left visible gaps
// between segments — computed here instead so changing RING_SEGMENT_COUNT
// or RING_RADIUS later can't silently reintroduce that mismatch.
build_ring :: proc() -> geo.Mesh {
	tangential_width := 2 * RING_RADIUS * math.sin(math.PI / f32(RING_SEGMENT_COUNT)) * SEGMENT_OVERLAP_FACTOR
	segment := geo.Cube(RING_SEGMENT_RADIAL_THICKNESS, RING_SEGMENT_HEIGHT, tangential_width)
	defer geo.Destroy(&segment)

	ring := geo.Empty_Mesh()
	for i in 0 ..< RING_SEGMENT_COUNT {
		angle := f32(i) * (2 * math.PI / f32(RING_SEGMENT_COUNT))
		transform := la.mul(la.matrix4_rotate(angle, la.Vector3f32{0, 1, 0}), la.matrix4_translate(la.Vector3f32{RING_RADIUS, 0, 0}))
		geo.Append_Mesh(&ring, segment, transform)
	}

	return ring
}

// build_cone stacks CONE_LEVEL_COUNT ring LEVELS (same rotate-after-
// translate composition as build_ring, see its comment for why order
// matters here), each level's radius shrinking linearly toward the top —
// a tapering stack, not a dedicated cone() generator (CLAUDE.md §2 item
// 6). The per-level Y offset rides along inside the SAME local translate
// as the radius (rotating about Y never changes a point's Y coordinate,
// so `level_y` survives the rotation unchanged) rather than needing a
// second transform. tangential_width is sized from the BASE level (see
// this file's constants block) using the same chord-length formula as
// build_ring, for the same reason.
build_cone :: proc() -> geo.Mesh {
	tangential_width := 2 * CONE_BASE_RADIUS * math.sin(math.PI / f32(CONE_SEGMENTS_PER_LEVEL)) * SEGMENT_OVERLAP_FACTOR
	segment := geo.Cube(CONE_SEGMENT_RADIAL_THICKNESS, CONE_LEVEL_HEIGHT, tangential_width)
	defer geo.Destroy(&segment)

	cone := geo.Empty_Mesh()
	for level in 0 ..< CONE_LEVEL_COUNT {
		level_radius := CONE_BASE_RADIUS * (1 - f32(level) / f32(CONE_LEVEL_COUNT))
		level_y := f32(level) * CONE_LEVEL_HEIGHT

		for i in 0 ..< CONE_SEGMENTS_PER_LEVEL {
			angle := f32(i) * (2 * math.PI / f32(CONE_SEGMENTS_PER_LEVEL))
			transform := la.mul(la.matrix4_rotate(angle, la.Vector3f32{0, 1, 0}), la.matrix4_translate(la.Vector3f32{level_radius, level_y, 0}))
			geo.Append_Mesh(&cone, segment, transform)
		}
	}

	return cone
}
