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
// Session 3 status (roadmap step 3 part 1, Library/Geometry): Session 1/2's
// temporary smoke-test generators (generate_cube, box_corners_and_
// triangles, generate_grid, and their make_* upload helpers) are DELETED —
// Library/Geometry.Mesh now owns generation AND GL upload, so this file no
// longer builds vertex/index arrays or Engine buffers by hand at all. Back-
// face culling is turned on for the first time in this project
// (gl.Enable(gl.CULL_FACE)) purely as a self-verification aid: a winding
// bug in any generator shows up immediately as missing faces in a capture.
// This is NOT yet roadmap step 8's toggleable culling feature — no debug
// key exists to turn it off, and step 8 will likely add a manual
// normal-based culling test to compare against this GL-native one; see
// PROGRESS.md.
//
// Session 4 status (roadmap step 3 parts 2-4, Library/Scene): Session 3's
// temporary gallery (build_gallery/build_ring/build_cone, generic shapes
// with no SENTINEL identity) is DELETED and replaced by the real thing —
// Library/Scene.Build_Scene() builds all 9 named SENTINEL objects as a
// Scene.Hierarchy (Library/Scene/Transform.odin's parent-indexed node
// system, Library/Scene/Objects.odin's actual object composition), and
// this file draws every node in it each frame via one shared
// Compute_World_Matrices pass. The gallery's build_ring/build_cone
// technique (and the transform-order/segment-sizing lessons Session 3's
// PROGRESS.md recorded) is reused directly inside Library/Scene/
// Objects.odin's append_ring_y/append_ring_x helpers, not reinvented.
// Shaders/Scene.glsl gained a `u_Color` uniform (still unlit — a colour
// PARAMETER per draw call, not a lighting calculation) purely so 9
// overlapping objects are visually distinguishable in a capture.
//
// Session 5 status (Prompts.md, first 5 objects + material/shading):
// `u_Color` above is GONE, replaced by a real (if deliberately temporary)
// material/shading pass. `Scene.Node.Color` became `Scene.Node.Material`
// (base colour + specular strength/shininess + emission colour, per that
// session's explicit ask), and `Shaders/Scene.glsl` gained a single
// hardcoded directional light (ambient + diffuse + Blinn-Phong specular +
// emission) so shapes read with real shading instead of flat silhouettes —
// still NOT roadmap step 4's real multi-light array, deliberately isolated
// in its own GLSL function so replacing it later is mechanical. This file
// now uploads `u_Model`/`u_NormalMatrix` per node (Scene.Normal_Matrix,
// recomputed from the live world matrix every frame) and `u_ViewPosition`
// once per frame, alongside the existing `u_MVP`.
//
// Session 7 status (roadmap step 4, Library/Lights + Shaders/Scene.glsl):
// Session 5's single hardcoded directional light is GONE, replaced by a
// real multi-light array — Library/Lights.Light (directional/point/spot),
// a TEMPORARY formula-placed rig (Library/Lights.Build_Temporary_Rig; real
// hierarchical attachment is roadmap step 5), and a debug gizmo overlay (key
// L) drawing a marker at every light. `u_Color`/per-node colour uniforms are
// unchanged from Session 5 — only the shader's LIGHTING got real, not the
// material system. Two new things this file now draws through
// Scene.Draw_Node (factored out of this file's old per-node loop body, now
// shared by real scene nodes, the ground plane below, and light gizmos):
//   - A ground plane (`build_ground_mesh`) — NOT one of Scene.Build_Scene's
//     9 counted objects (kept out of the Hierarchy entirely, on purpose, so
//     the printed object count stays exactly 9), added because this
//     session's task explicitly asks for a capture "showing a spotlight
//     cone hitting the ground," and no ground existed before this session
//     (Session 2's ground GRID was deleted at roadmap step 3 along with the
//     rest of that session's temporary smoke-test scene).
//   - Light gizmos (Library/Lights.Draw_Gizmos), toggled live by `L` or
//     forced on for a --capture run via --gizmos.
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
import lightspkg "../Library/Lights"
import scenepkg "../Library/Scene"

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
// Camera (Library/Camera.Camera_Looking_At) — chosen so the whole base
// (the perimeter fence's ~28x28 footprint, Library/Scene/Objects.odin's
// FENCE_HALF_WIDTH/DEPTH) is comfortably in frame at startup. Lens
// parameters (FOV/near/far) live on the Camera itself
// (Library/Camera.Default_Camera), not here.
CAMERA_START_EYE :: la.Vector3f32{0.0, 22.0, 34.0}

// Also passed to Toggle_Projection each time (CLAUDE.md §7: the
// orthographic volume is sized from the camera's distance to this point),
// so the framing stays sensible across a projection toggle regardless of
// where free-fly movement has since taken the camera.
SCENE_FOCUS :: la.Vector3f32{0, 0, 0}

// Global ambient term (Shaders/Scene.glsl's u_AmbientColor/u_AmbientStrength
// — see that file's comment on why ambient is one scene-wide term, not
// summed per light). Same cool tint Session 5's single hardcoded light used
// for its own ambient term, so this session's real light array doesn't
// shift the scene's baseline "night" colour on its own.
AMBIENT_COLOR :: la.Vector3f32{0.55, 0.6, 0.75}
AMBIENT_STRENGTH :: 0.18

// Ground plane (see this file's "Session 7 status" header note for why it
// exists). Sized to comfortably cover the fence footprint
// (Library/Scene/Objects.odin's FENCE_HALF_WIDTH/DEPTH = 14, i.e. a 28x28
// area) with margin, at Y = 0 — the same ground level every one of the 9
// objects is already positioned at (each *_POSITION constant in
// Objects.odin has Y = 0).
GROUND_SIZE :: 60.0
GROUND_Y :: 0.0

main :: proc() {
	capture_frames, capture_path, do_capture := parse_capture_flag(os.args[1:])
	start_projection := parse_projection_flag(os.args[1:])
	gizmos_visible = parse_gizmos_flag(os.args[1:])

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

	scene := scenepkg.Build_Scene()
	defer scenepkg.Destroy(&scene)

	object_count, node_count := 0, len(scene.Nodes)
	for node in scene.Nodes {
		if node.Parent == scenepkg.NO_PARENT do object_count += 1
	}
	fmt.printfln("Scene: %d objects, %d nodes total", object_count, node_count)

	ground_mesh := build_ground_mesh()
	defer geo.Destroy(&ground_mesh)
	ground_material := scenepkg.Default_Material(la.Vector3f32{0.05, 0.05, 0.06})
	// Fixed once, not recomputed per frame: unlike the 9 real objects and
	// every light (both required to recompute every frame — CLAUDE.md §2
	// item 10, §5.3 — since Inspection Mode can reposition either), the
	// ground plane never moves for the lifetime of this program, so a
	// static model matrix is not a "cached as if static" violation of that
	// rule, the same way CAMERA_START_EYE being a compile-time constant
	// isn't either.
	ground_model := la.mul(la.matrix4_translate(la.Vector3f32{0, GROUND_Y, 0}), la.matrix4_rotate(-math.PI * 0.5, la.Vector3f32{1, 0, 0}))

	light_rig := lightspkg.Build_Temporary_Rig()
	defer delete(light_rig)
	active_light_count := lightspkg.Active_Count(light_rig[:])
	fmt.printfln(
		"Lights: %d active, %d objects (lights > objects: %v)",
		active_light_count,
		object_count,
		active_light_count > object_count,
	)

	gizmo_meshes := lightspkg.Build_Gizmo_Meshes()
	defer lightspkg.Destroy_Gizmo_Meshes(&gizmo_meshes)

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

		// One world-matrix pass per frame, shared by every node's draw
		// call below (Scene.Compute_World_Matrices' own comment — CLAUDE.md
		// §5.3's "computed top-down once per frame, cache per frame"). The
		// scene is static this session (no rotation) — roadmap step 3 is
		// explicitly "static; unlit," CLAUDE.md §9; animation arrives with
		// Patrol Mode (step 9). Composition order matches the column-vector
		// convention recorded in Library/Camera/Camera.odin: apply `model`
		// (here, a node's world matrix) first, then `view`, then
		// `projection`, to a point on the right.
		world_matrices := scenepkg.Compute_World_Matrices(&scene)
		sd.SetUniform(&shader, "u_ViewPosition", camera.position.x, camera.position.y, camera.position.z)
		sd.SetUniform(&shader, "u_AmbientColor", AMBIENT_COLOR.r, AMBIENT_COLOR.g, AMBIENT_COLOR.b)
		sd.SetUniform(&shader, "u_AmbientStrength", f32(AMBIENT_STRENGTH))
		// Light positions/directions/attenuation are re-uploaded fresh every
		// frame from `light_rig`, never computed once and reused as though
		// fixed (CLAUDE.md §2 item 10) — true even though this session's
		// TEMPORARY rig doesn't animate yet, so the same call already does
		// the right thing once roadmap step 5/9 makes lights move.
		lightspkg.Upload(&shader, light_rig[:])

		scenepkg.Draw_Node(&shader, view, projection, ground_model, &ground_mesh, ground_material)

		for &node, i in scene.Nodes {
			model := world_matrices[i]
			scenepkg.Draw_Node(&shader, view, projection, model, &node.Mesh, node.Material)
		}
		delete(world_matrices)

		if gizmos_visible {
			lightspkg.Draw_Gizmos(&shader, view, projection, light_rig[:], &gizmo_meshes)
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

// gizmos_visible toggles Library/Lights.Draw_Gizmos (key L). Starts from
// parse_gizmos_flag's result (set once in main() before the loop begins),
// then flips on each L press exactly like projection_toggle_requested
// flips the projection above.
gizmos_visible: bool

key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
	if key == glfw.KEY_ESCAPE && action == glfw.PRESS {
		glfw.SetWindowShouldClose(window, true)
	}
	if key == glfw.KEY_P && action == glfw.PRESS {
		projection_toggle_requested = true
	}
	if key == glfw.KEY_L && action == glfw.PRESS {
		gizmos_visible = !gizmos_visible
	}
}

// build_ground_mesh builds and uploads the ground plane's LOCAL-space mesh
// once (see GROUND_SIZE/GROUND_Y and ground_model above for how it's
// positioned). geo.Plane lies in the local XY plane facing +Z
// (Library/Geometry/Geometry.odin's own comment); ground_model's -90°
// rotation about X is what lays it flat facing +Y, done once at draw time
// rather than baked into the mesh's own vertices, so this stays consistent
// with every other mesh in this project (local-space geometry + a separate
// world transform).
build_ground_mesh :: proc() -> geo.Mesh {
	mesh := geo.Plane(GROUND_SIZE, GROUND_SIZE)
	geo.Upload(&mesh)
	return mesh
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

// parse_gizmos_flag looks for a bare "--gizmos" flag anywhere in argv, the
// non-interactive way to force Library/Lights.Draw_Gizmos on for a
// --capture run (the L key itself is skipped during --capture, same as
// every other live input — see the do_capture guard in main()'s loop).
// Defaults to off, matching gizmos_visible's zero value for a normal
// interactive run before the first L press.
parse_gizmos_flag :: proc(args: []string) -> bool {
	for arg in args {
		if arg == "--gizmos" do return true
	}
	return false
}
