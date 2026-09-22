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
// GRAVE_ACCENT) drawing a marker at every light. `u_Color`/per-node colour
// uniforms are unchanged from Session 5 — only the shader's LIGHTING got real, not the
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
//   - Light gizmos (Library/Lights.Draw_Gizmos), toggled live by
//     GRAVE_ACCENT or forced on for a --capture run via --gizmos.
//
// Session 8 status (roadmap step 5, Library/Lights + Library/Scene/
// Transform.odin): `Build_Temporary_Rig` is GONE, replaced by `Build_Rig`
// (called once, against the real `scene`), and every light's world
// Position/Direction is now recomputed each frame by `Update_From_Scene`
// (called here, right after `Compute_World_Matrices`, before `Upload`) —
// see Library/Lights/Lights.odin's own header for the full node list this
// attaches to. This file also gained a small TEMPORARY demo animation
// (the DEMO_* constants/block below) purely to make that attachment
// visible in a still capture: nothing moved in Session 7's temporary rig,
// so there was nothing yet to prove a light actually tracks a moving
// parent. NOT roadmap step 9's real Patrol Mode — deliberately isolated so
// that step can replace it outright.
//
// Session 9 status (roadmap step 6, Shaders/Scene.glsl +
// Library/Lights.Build_Rig): the 3 barracks windows are now AREA lights
// (LIGHT_TYPE_AREA), sampled N times per fragment inside the shader itself
// (area_light_contribution) — this file's own job is just uploading two
// new runtime controls (u_AreaLightSampleCount, u_AreaLightJitter) each
// frame from the DEFAULT_AREA_LIGHT_SAMPLE_COUNT/area_light_jitter package
// vars below, driven by `+`/`-`/`J` (or --area-samples/--area-jitter for a
// --capture run) so an N=1-vs-N=8 comparison is a live keypress away.
//
// Session 10 status (roadmap step 7, Shaders/Scene.glsl +
// Library/Geometry.Smooth_Cylinder_Normals): flat/Gouraud/Phong shading,
// switchable live with keys `1`/`2`/`3` (or --shading for a --capture
// run) — uploaded as `u_ShadingMode` each frame, shown in the window
// title (updated on each keypress, see key_callback). The ground plane
// (previously ONE giant Plane) is now a runtime-generated GRID of small
// Plane cells stitched together via Append_Mesh — `G` toggles between a
// LOW (1x1, i.e. the old single-quad behaviour) and HIGH resolution, so
// Gouraud's "misses a spotlight highlight that falls inside a large
// triangle" failure mode is directly demonstrable: LOW resolution's giant
// triangles can only evaluate lighting at 4 far-apart corners, HIGH
// resolution's many small triangles approximate the highlight far better
// (still an approximation vs. Phong's per-fragment result, just a visibly
// closer one). See Library/Geometry/Geometry.odin's Smooth_Cylinder_
// Normals for why a few curved parts (radar dish, jeep/tank wheels) were
// given actual smooth normals this session — without that, Gouraud/Phong
// can't look any different from Flat on this project's otherwise-faceted
// geometry, since every vertex of one face already shares one normal.
//
// Session 11 status (roadmap step 8, Shaders/Scene.glsl +
// Source/Main.odin): back-face culling and hidden-surface removal are now
// demonstrable, not just "on since Session 3 with no way to compare."
// `C` cycles cull_mode through OFF -> MANUAL (a per-fragment dot(normal,
// direction-to-eye) test in the shader, see u_CullMode's own comment in
// Scene.glsl for why it reaches the same image as hardware culling without
// its performance saving) -> GL (gl.Enable(gl.CULL_FACE), this project's
// behaviour every session before this one). `Z` toggles the depth test;
// `X` toggles a grayscale linearised-depth visualisation (hand-derived in
// the fragment shader, not sampled from a second depth-texture pass); `F`
// toggles wireframe (gl.PolygonMode); `B` toggles a magenta tint on
// back-facing fragments specifically so culling OFF + depth test OFF (the
// "visibly wrong in a teachable way" state this session's task asks for)
// has a way to show WHICH geometry culling would normally have hidden.
// All five states are re-applied to GL every frame (apply_render_state,
// called from the main loop, not from key_callback — same "callback flips
// a package var, the main loop does the actual work" separation this file
// already uses for shading_mode/gizmos_visible) and shown together in the
// window title (build_window_title), the only on-screen readout this
// project has (no text-rendering pipeline exists — same reasoning Session
// 10's shading-mode title already established). A one-time startup print
// logs the whole scene's submitted triangle count against one object's
// (the watchtower's) CPU-estimated back-facing count from the starting
// camera pose, to put a concrete number on "culling saves roughly half."
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
import "base:runtime"

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

// Roadmap step 9 (Patrol Mode, Prompts.md Session 12): Session 8's
// TEMPORARY demo animation (DEMO_TANK_HULL_SPIN_RATE and friends, driven by
// a synthetic frame-count clock with no Mode gating) is DELETED — that
// session's own PROGRESS.md entry said exactly this would happen. Real
// Patrol Mode replaces it below: an app-level Mode enum + the shared
// animation clock (Source/Patrol.odin), the camera PATH itself in
// Library/Camera/Camera.odin (Patrol_Camera_Pose), and Tab/Space/`,`/`.`
// controls (mode switch, pause, speed) alongside the projection/shading/
// etc. toggles already here. See this file's own "Session 12 status"
// header note above for the full design.
DEFAULT_MODE :: Mode.Patrol

// The shared animation clock's own speed multiplier (this session's task:
// "speed keys"), starting value — 1.0 unless overridden by --patrol-speed.
DEFAULT_ANIMATION_SPEED_SCALE :: f32(1.0)

// Roadmap step 6 (CLAUDE.md §6.3) starting sample count for the barracks
// windows' area-light averaging (Shaders/Scene.glsl's
// area_light_contribution) — N=4 is mid-range between the N=1 (hard,
// point-like) and N=8 (soft) comparison this session's task specifically
// asks to be able to show live via the +/- keys below.
DEFAULT_AREA_LIGHT_SAMPLE_COUNT :: 4

// Shading mode (roadmap step 7, CLAUDE.md §6.1) — values match Shaders/
// Scene.glsl's own SHADING_FLAT/SHADING_GOURAUD/SHADING_PHONG #defines
// exactly (kept in sync by hand, same cross-language situation as
// MAX_LIGHTS/MAX_AREA_SAMPLES). Phong is the default: identical to every
// prior session's behaviour, so a plain `./Sentinel` with no flags looks
// the same as it always has.
SHADING_FLAT :: i32(0)
SHADING_GOURAUD :: i32(1)
SHADING_PHONG :: i32(2)
DEFAULT_SHADING_MODE :: SHADING_PHONG

// Display name per shading mode, read by build_window_title below — the
// task's own "show the current mode on screen or in the window title" ask,
// done via the title since this project has no text-rendering
// infrastructure to draw an on-screen label with. (Session 11 replaced the
// old SHADING_MODE_TITLE array of whole title strings with this array of
// just the mode name, now that the title has more than one toggle to show —
// see build_window_title.)
SHADING_MODE_NAME := [3]string{"Flat", "Gouraud", "Phong"}

// Roadmap step 8 (CLAUDE.md §4/§9, Prompts.md Session 11) cull-mode values
// — match Shaders/Scene.glsl's CULL_OFF/CULL_MANUAL/CULL_GL #defines
// exactly (kept in sync by hand, same cross-language situation as
// SHADING_FLAT/GOURAUD/PHONG above and Scene.glsl's own MAX_LIGHTS note).
// GL matches every prior session's behaviour (back-face culling has been
// unconditionally on since Session 3), so a plain `./Sentinel` with no
// flags looks exactly the same as it always has.
CULL_OFF :: i32(0)
CULL_MANUAL :: i32(1)
CULL_GL :: i32(2)
DEFAULT_CULL_MODE :: CULL_GL
CULL_MODE_NAME := [3]string{"Off", "Manual", "GL"}

// The watchtower is this session's demo object for the CPU-side back-facing
// triangle estimate (task item 6) — a single, mostly-convex root object
// (legs + platform + roof), not one of the thin/open-ring "cylinder"
// composites (fence lamps' posts, the radar dish) where "back-facing from
// this one view" is a less intuitive concept to show in a startup log line.
TRIANGLE_COUNT_DEMO_OBJECT :: "Watchtower"

// Ground grid resolution (roadmap step 7's own task text: "subdivide the
// ground into a grid mesh... with a resolution toggle"). LOW matches the
// single quad every prior session used; HIGH is dense enough that a
// spotlight's cone (a few units across, Library/Lights.FLOODLIGHT_RANGE/
// SEARCHLIGHT_RANGE-scale) spans many cells rather than sitting entirely
// inside one giant triangle — see build_ground_mesh's own comment for the
// cell-size reasoning.
GROUND_GRID_LOW_RESOLUTION :: 1
GROUND_GRID_HIGH_RESOLUTION :: 24

// Roadmap step 10 (CLAUDE.md §7/§9, Prompts.md Session 13): Inspection
// Mode's starting translate/rotate step-size multiplier — see Source/
// Inspection.odin's BASE_TRANSLATE_STEP/BASE_ROTATE_STEP_DEGREES for the
// base amounts this scales.
DEFAULT_EDIT_STEP_SCALE :: f32(1.0)

// Roadmap step 11 (CLAUDE.md §6.2, Prompts.md Session 14) — the ray-traced
// reflection starts ON, matching every other "the new interesting
// behaviour is visible by default" toggle in this project (e.g.
// DEFAULT_CULL_MODE is GL, not OFF).
DEFAULT_RAY_TRACED_REFLECTION_ENABLED :: true

// Polish pass (Prompts.md, post-Session-14 "polish" session): every new
// toggle here defaults ON, matching this project's existing convention for
// a purely-additive visual improvement (DEFAULT_CULL_MODE is GL, not OFF;
// DEFAULT_RAY_TRACED_REFLECTION_ENABLED, above, is true) — turning any of
// them OFF reproduces this project's exact PRE-polish look pixel-for-pixel
// (see each uniform's own comment in Shaders/Scene.glsl), so nothing
// already required (shading modes, culling, depth test, projection,
// reflection) is affected either way, satisfying this session's own rule
// that every item stay toggleable without obstructing verification.
DEFAULT_TONEMAPPING_ENABLED :: true
DEFAULT_VIGNETTE_ENABLED :: true
DEFAULT_FOG_ENABLED :: true
DEFAULT_GROUND_DETAIL_ENABLED :: true
DEFAULT_SKY_ENABLED :: true

// Sky dome full size (Geometry.Cube takes full width/height/depth, not a
// half-size). Must stay well inside the Camera's own far plane (Library/
// Camera.DEFAULT_FAR = 100) even measured from a CUBE CORNER — the
// furthest point on the dome from a camera re-centred at its middle every
// frame: 40 * sqrt(3) ~= 69.3, comfortable margin under 100 for camera
// movement anywhere inside the fence (Library/Scene/Objects.odin's
// FENCE_HALF_WIDTH/DEPTH = 14).
SKY_CUBE_SIZE :: f32(80.0)

// How often the live window title's FPS readout refreshes — every frame
// would be both noisy (a single frame's dt is a poor FPS estimate) and
// wasteful (glfw.SetWindowTitle every frame for no reason); twice a second
// is frequent enough to read live, rare enough to be a stable number.
FPS_DISPLAY_UPDATE_INTERVAL :: f32(0.5)

// --benchmark's own warm-up window — see its accumulator variables' own
// comment, right before the main loop, for why these frames are measured
// but excluded from the reported average.
BENCHMARK_WARMUP_FRAMES :: 10

main :: proc() {
	capture_frames, capture_path, do_capture := parse_capture_flag(os.args[1:])
	start_projection := parse_projection_flag(os.args[1:])
	gizmos_visible = parse_gizmos_flag(os.args[1:])
	area_light_sample_count = parse_area_samples_flag(os.args[1:])
	area_light_jitter = parse_area_jitter_flag(os.args[1:])
	shading_mode = parse_shading_flag(os.args[1:])
	ground_resolution = parse_ground_resolution_flag(os.args[1:])
	cull_mode = parse_cull_flag(os.args[1:])
	depth_test_enabled = parse_depth_test_flag(os.args[1:])
	wireframe_enabled = parse_wireframe_flag(os.args[1:])
	backface_debug_enabled = parse_backface_debug_flag(os.args[1:])
	depth_visualization_enabled = parse_depth_visualization_flag(os.args[1:])
	current_mode = parse_mode_flag(os.args[1:])
	animation_speed_scale = parse_patrol_speed_flag(os.args[1:])
	test_inspection_prefix, run_inspection_test := parse_test_inspection_flag(os.args[1:])
	edit_step_scale = DEFAULT_EDIT_STEP_SCALE
	ray_traced_reflection_enabled = parse_reflection_flag(os.args[1:])
	tonemapping_enabled = parse_tonemapping_flag(os.args[1:])
	vignette_enabled = parse_vignette_flag(os.args[1:])
	fog_enabled = parse_fog_flag(os.args[1:])
	ground_detail_enabled = parse_ground_detail_flag(os.args[1:])
	sky_enabled = parse_sky_flag(os.args[1:])
	benchmark_frames, do_benchmark := parse_benchmark_flag(os.args[1:])
	msaa_samples := parse_msaa_flag(os.args[1:])

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
	// MSAA sample count is a WINDOW HINT (fixed GL context state), not a
	// live uniform/GL.Enable toggle like every other polish item this
	// session — the sample count is baked into the default framebuffer at
	// context creation and OpenGL has no call to change it afterward
	// without recreating the window, so unlike M/V/Y/T/`/` above, this is a
	// START-ONLY choice (--msaa), not a live key. 0 (the default) asks for
	// no multisampling at all, matching this project's behaviour before
	// this session.
	if msaa_samples > 0 {
		glfw.WindowHint(glfw.SAMPLES, msaa_samples)
	}
	// A capture or benchmark run (or the headless Inspection test, Source/
	// Inspection.odin's Run_Inspection_Test) has no one watching the
	// window; hiding it avoids an on-screen flash for a run that closes
	// itself after N frames.
	glfw.WindowHint(glfw.VISIBLE, !do_capture && !run_inspection_test && !do_benchmark)

	// All 6 toggles build_window_title reads are already parsed above, so
	// the FIRST title the window ever shows already reflects any --cull/
	// --depth-test/--wireframe/etc. flags, rather than starting generic and
	// waiting for the first keypress to correct it.
	window := glfw.CreateWindow(DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT, build_window_title(), nil, nil)
	if window == nil {
		fmt.eprintln("Failed to create GLFW window")
		os.exit(1)
	}
	defer glfw.DestroyWindow(window)

	glfw.MakeContextCurrent(window)
	// A benchmark run wants the GPU's true unthrottled per-frame cost (this
	// session's own task: "check that we hold 60 FPS... profile if not"),
	// not whatever the display's own refresh rate happens to cap it at —
	// vsync (SwapInterval(1), every other run) would otherwise hide a
	// scene that's actually well under or over budget behind a flat
	// "always ~60/~120/whatever Hz" reading.
	glfw.SwapInterval(0 if do_benchmark else 1)
	glfw.SetFramebufferSizeCallback(window, framebuffer_size_callback)
	glfw.SetKeyCallback(window, key_callback)
	glfw.SetMouseButtonCallback(window, mouse_button_callback)
	glfw.SetScrollCallback(window, scroll_callback)

	gl.load_up_to(GL_VERSION_MAJOR, GL_VERSION_MINOR, glfw.gl_set_proc_address)

	if msaa_samples > 0 {
		// The SAMPLES window hint above only REQUESTS a multisampled
		// default framebuffer; GL_MULTISAMPLE still needs enabling like any
		// other fixed-function raster stage, same as CULL_FACE/DEPTH_TEST
		// below.
		gl.Enable(gl.MULTISAMPLE); dbg.GL_Check()
		fmt.printfln("MSAA: %dx (--msaa)", msaa_samples)
	}

	fmt.printfln("GPU vendor:   %s", gl.GetString(gl.VENDOR))
	fmt.printfln("GPU renderer: %s", gl.GetString(gl.RENDERER))
	fmt.printfln("OpenGL:       %s", gl.GetString(gl.VERSION))
	fmt.printfln("GLSL:         %s", gl.GetString(gl.SHADING_LANGUAGE_VERSION))

	fb_width, fb_height := glfw.GetFramebufferSize(window)
	gl.Viewport(0, 0, fb_width, fb_height); dbg.GL_Check()

	// Depth test / culling / wireframe are now all toggleable (roadmap step
	// 8, Session 11) — apply_render_state pushes the current cull_mode/
	// depth_test_enabled/wireframe_enabled package vars to GL every frame
	// in the main loop below, so nothing needs to be set once here anymore.
	// Their startup values already come from the --cull/--depth-test/
	// --wireframe flags parsed above (or DEFAULT_CULL_MODE/true/false),
	// matching every prior session's always-on culling/depth-test
	// behaviour by default.

	scene := scenepkg.Build_Scene()
	defer scenepkg.Destroy(&scene)

	// Roadmap step 10 (reset keys, this session's task: "Reset-node and
	// reset-all keys"): every node's LOCAL transform exactly as Build_Scene
	// left it, captured ONCE before anything (Patrol or Inspection) ever
	// edits it — this is the build-time rest pose reset restores, not
	// "whatever it happened to be a moment ago".
	original_transforms := make([]scenepkg.Transform, len(scene.Nodes))
	defer delete(original_transforms)
	for node, i in scene.Nodes {
		original_transforms[i] = node.Local
	}

	object_count, node_count := 0, len(scene.Nodes)
	for node in scene.Nodes {
		if node.Parent == scenepkg.NO_PARENT do object_count += 1
	}
	fmt.printfln("Scene: %d objects, %d nodes total", object_count, node_count)

	ground_mesh := build_ground_mesh(ground_resolution)
	defer geo.Destroy(&ground_mesh)
	fmt.printfln("Ground grid: %dx%d cells (G to toggle), shading mode: %s", ground_resolution, ground_resolution, SHADING_MODE_NAME[shading_mode])
	ground_material := scenepkg.Default_Material(la.Vector3f32{0.05, 0.05, 0.06})
	// Fixed once, not recomputed per frame: unlike the 9 real objects and
	// every light (both required to recompute every frame — CLAUDE.md §2
	// item 10, §5.3 — since Inspection Mode can reposition either), the
	// ground plane never moves for the lifetime of this program, so a
	// static model matrix is not a "cached as if static" violation of that
	// rule, the same way CAMERA_START_EYE being a compile-time constant
	// isn't either.
	ground_model := la.mul(la.matrix4_translate(la.Vector3f32{0, GROUND_Y, 0}), la.matrix4_rotate(-math.PI * 0.5, la.Vector3f32{1, 0, 0}))

	// Polish pass sky dome (`/` key, --sky): one giant Cube — still one of
	// CLAUDE.md §2 item 6's three base primitives, not a bespoke skybox
	// mesh type — built once here; ITS TRANSFORM (not its geometry) is
	// re-centred on the camera fresh every frame below, the same "static
	// mesh, live transform" split the ground plane above already uses.
	// sky_material only exists because Draw_Node always wants one; the
	// fragment shader takes a completely different, material-ignoring path
	// for any u_IsSky fragment (Shaders/Scene.glsl's own comment).
	sky_mesh := geo.Cube(SKY_CUBE_SIZE, SKY_CUBE_SIZE, SKY_CUBE_SIZE)
	geo.Upload(&sky_mesh)
	defer geo.Destroy(&sky_mesh)
	sky_material := scenepkg.Default_Material(la.Vector3f32{0, 0, 0})

	light_rig := lightspkg.Build_Rig(&scene)
	defer delete(light_rig)
	active_light_count := lightspkg.Active_Count(light_rig[:])
	fmt.printfln(
		"Lights: %d active, %d objects (lights > objects: %v)",
		active_light_count,
		object_count,
		active_light_count > object_count,
	)
	fmt.printfln("Area light samples: %d (+/- to change, J to toggle jitter, currently %v)", area_light_sample_count, area_light_jitter)

	fmt.printfln(
		"Render toggles: Cull=%s (C), Depth test=%v (Z), Depth visualization=%v (X), Wireframe=%v (F), Backface debug=%v (B)",
		CULL_MODE_NAME[cull_mode], depth_test_enabled, depth_visualization_enabled, wireframe_enabled, backface_debug_enabled,
	)

	// Task item 6: log total submitted triangles against ONE object's
	// CPU-estimated back-facing count from the starting camera pose, to put
	// a concrete number on "culling saves roughly half" rather than just
	// asserting it. A one-time startup diagnostic (like the object/light
	// counts above), not a per-frame log — the estimate is only ever as
	// fresh as the camera pose it was computed from, which is fine for a
	// demo number, not fine for anything the renderer actually depends on.
	total_triangle_count := count_total_triangles(&scene, &ground_mesh)
	demo_node_index := scenepkg.Find_Node(&scene, TRIANGLE_COUNT_DEMO_OBJECT)
	if demo_node_index != scenepkg.NO_PARENT {
		startup_world_matrices := scenepkg.Compute_World_Matrices(&scene)
		demo_world_matrix := startup_world_matrices[demo_node_index]
		demo_normal_matrix := scenepkg.Normal_Matrix(demo_world_matrix)
		// One constant view direction for the whole object (its own world
		// position to the starting eye), not a per-triangle one — the same
		// simplification the ORTHOGRAPHIC branch of Scene.glsl's manual
		// culling test always uses exactly, and a reasonable one here too
		// since the watchtower is small relative to its distance from
		// CAMERA_START_EYE. This is exactly why the log below calls it an
		// ESTIMATE, not an exact count.
		demo_view_direction := la.normalize(CAMERA_START_EYE - scenepkg.World_Position(demo_world_matrix))
		delete(startup_world_matrices)

		demo_mesh := &scene.Nodes[demo_node_index].Mesh
		demo_triangle_count := len(demo_mesh.Indices) / 3
		demo_back_facing_count := count_back_facing_triangles(demo_mesh, demo_normal_matrix, demo_view_direction)
		fmt.printfln(
			"Triangles: %d submitted across the whole scene; %s alone has %d, ~%d (%.0f%%) estimated back-facing from the starting view (roughly the saving GL cull mode would give on it)",
			total_triangle_count,
			TRIANGLE_COUNT_DEMO_OBJECT,
			demo_triangle_count,
			demo_back_facing_count,
			100.0 * f32(demo_back_facing_count) / f32(demo_triangle_count),
		)
	}

	// Roadmap step 9 (Patrol Mode) node/light lookups, looked up ONCE
	// (indices never change after Build_Scene/Build_Rig) — see Source/
	// Patrol.odin for the formulas that drive these, and the main loop
	// below for where they're applied. The tank HULL and the jeep ROOT are
	// deliberately NOT looked up here — this session's task explicitly
	// keeps them static in Patrol, unlike Session 8's temporary demo (now
	// deleted) which spun the hull too.
	floodlight_head_node := scenepkg.Find_Node(&scene, "Watchtower Floodlight Head")
	radar_dish_node := scenepkg.Find_Node(&scene, "Radar Dish")
	tank_turret_node := scenepkg.Find_Node(&scene, "Tank Turret")
	jeep_headlight_left_node := scenepkg.Find_Node(&scene, "Jeep Headlight Left")
	jeep_headlight_right_node := scenepkg.Find_Node(&scene, "Jeep Headlight Right")

	// Locate the two lights Patrol Mode animates the INTENSITY of, by which
	// SCENE NODE they're parented to (find_light_by_parent, below) rather
	// than a hardcoded index into Library/Lights.Build_Rig's internal
	// append order — that order is Build_Rig's own implementation detail,
	// not something this file should have to know or keep in sync by hand.
	radar_beacon_node := scenepkg.Find_Node(&scene, "Radar Beacon")
	beacon_light_index := find_light_by_parent(light_rig[:], radar_beacon_node)
	fence_node := scenepkg.Find_Node(&scene, "Perimeter Fence")
	fence_flicker_light_index := find_light_by_parent(light_rig[:], fence_node)

	// Roadmap step 10 (this session's task): every selectable node ([/]
	// cycles through this list — see Source/Inspection.odin's Build_
	// Selectable_Nodes for exactly which nodes and why), plus its own
	// LOCAL-space bounding box for mouse picking (computed once here, not
	// per pick — a mesh's local geometry never changes after Build_Scene,
	// only its world TRANSFORM does).
	selectable_nodes := Build_Selectable_Nodes(&scene)
	defer delete(selectable_nodes)
	selectable_aabbs := make([]AABB, len(selectable_nodes))
	defer delete(selectable_aabbs)
	for node_index, i in selectable_nodes {
		selectable_aabbs[i] = Compute_Local_AABB(&scene.Nodes[node_index].Mesh)
	}
	selected_node_name = scene.Nodes[selectable_nodes[selected_index]].Name
	fmt.printfln("Inspection: %d selectable objects, starting selection %q ([/] to cycle, H for full controls)", len(selectable_nodes), selected_node_name)
	Print_Controls()

	// Roadmap step 11 (CLAUDE.md §6.2, Prompts.md Session 14): mark every
	// glass surface's already-built Material as reflective — see Scene.
	// Material.Reflective's own comment for why this is set here, by name,
	// rather than in Library/Scene/Objects.odin at build time. Then resolve
	// the proxy shape list's node names ONCE — Build_Proxies (main loop,
	// below) re-derives every proxy's actual transform from this list
	// EVERY frame, never caching a proxy's position/orientation itself.
	reflective_count := 0
	for name in REFLECTIVE_NODE_NAMES {
		index := scenepkg.Find_Node(&scene, name)
		if index == scenepkg.NO_PARENT {
			panic(fmt.tprintf("Source/Main.odin: no Scene node named %q for the ray-traced reflection — Objects.odin and REFLECTIVE_NODE_NAMES have drifted out of sync", name))
		}
		scene.Nodes[index].Material.Reflective = true
		reflective_count += 1
	}
	proxy_defs := Build_Proxy_Defs(&scene)
	fmt.printfln("Reflection: %d reflective surfaces, %d proxy shapes (R to toggle)", reflective_count, len(proxy_defs))

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

	// Roadmap step 10 (this session's task: "script a headless sequence...
	// that selects the tank turret, rotates it, and asserts the
	// searchlight's world position changed as expected"). Runs INSTEAD of
	// the interactive loop below (Run_Inspection_Test calls os.exit itself
	// once it has a verdict, so this never falls through) — everything it
	// needs (scene, light_rig, shader, a real GL context) already exists at
	// this point, and nothing after it (camera/cursor setup, the render
	// loop) is relevant to a scripted, single-pass test.
	if run_inspection_test {
		Run_Inspection_Test(window, &scene, light_rig[:], &shader, test_inspection_prefix, int(fb_width), int(fb_height))
	}

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

	// Benchmark accumulators (--benchmark <frames> only). The first
	// BENCHMARK_WARMUP_FRAMES are excluded from the average: shader
	// compilation, first-frame GL state setup, and driver "getting warm"
	// costs are real but one-time, and would otherwise skew a steady-state
	// throughput number this session's own task asks for ("check that we
	// hold 60 FPS... profile if not").
	benchmark_frame_time_sum: f32
	benchmark_frame_time_min := f32(1e9)
	benchmark_frame_time_max := f32(0)
	benchmark_measured_frames := 0
	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents()

		current_time := glfw.GetTime()
		dt_seconds := f32(current_time - last_frame_time)
		last_frame_time = current_time

		if !do_capture {
			// Cursor delta is READ every frame regardless of mode, so
			// last_cursor_x/y never go stale — staling it while in Patrol
			// would otherwise cause one big mouse-look jump the instant the
			// user switches back to Inspection. It's only APPLIED to the
			// camera while actually in Inspection: Patrol's own camera is
			// fully formula-driven below (Library/Camera.Patrol_Camera_Pose)
			// and would just have any WASD/mouse-look input overwritten
			// next frame anyway, so polling it in Patrol would only make
			// the controls feel broken, not do anything useful.
			cursor_x, cursor_y := glfw.GetCursorPos(window)
			if current_mode == .Inspection {
				cam.Apply_Look_Delta(&camera, f32(cursor_x - last_cursor_x), f32(cursor_y - last_cursor_y))

				move_forward := key_axis(window, glfw.KEY_W, glfw.KEY_S)
				move_right := key_axis(window, glfw.KEY_D, glfw.KEY_A)
				move_up := key_axis(window, glfw.KEY_E, glfw.KEY_Q)
				sprint := glfw.GetKey(window, glfw.KEY_LEFT_SHIFT) == glfw.PRESS || glfw.GetKey(window, glfw.KEY_RIGHT_SHIFT) == glfw.PRESS
				cam.Apply_Move(&camera, move_forward, move_right, move_up, dt_seconds, sprint)
			}
			last_cursor_x, last_cursor_y = cursor_x, cursor_y

			// Polish pass: live frame-time overlay (this session's own
			// task: "ms/FPS in the window title"). Averaged over
			// FPS_DISPLAY_UPDATE_INTERVAL rather than shown per-frame — a
			// single frame's dt is too noisy to read, and retitling the
			// window every frame would be wasteful for no benefit. Gated to
			// !do_capture as this whole block already is: a capture run's
			// own frame timing isn't real interactive playback (frame_dt is
			// a fixed nominal step there, see its own comment below), and
			// nobody is watching a hidden window's title bar anyway.
			fps_display_accum_time += dt_seconds
			fps_display_accum_frames += 1
			if fps_display_accum_time >= FPS_DISPLAY_UPDATE_INTERVAL {
				fps_display_value = f32(fps_display_accum_frames) / fps_display_accum_time
				fps_display_accum_time = 0
				fps_display_accum_frames = 0
				glfw.SetWindowTitle(window, build_window_title())
			}

			// P (projection) and scroll-zoom stay available in BOTH modes —
			// neither fights against Patrol's own position/yaw/pitch
			// formula the way WASD/mouse-look would, so there's no reason
			// to gate them to Inspection only.
			if projection_toggle_requested {
				cam.Toggle_Projection(&camera, SCENE_FOCUS)
				projection_toggle_requested = false
			}

			if camera.projection == .Orthographic && scroll_delta_y != 0 {
				cam.Zoom_Ortho(&camera, scroll_delta_y)
			}
			scroll_delta_y = 0

			// Roadmap step 9 (Tab, this session's task): "switching Patrol
			// -> Inspection keeps the current camera pose" is NOT a special
			// case below — `camera` already holds whatever pose Patrol's
			// own per-frame update (further down this loop) last computed
			// it to, so Inspection's free-fly simply continues from there
			// once current_mode flips, with nothing to copy. "Inspection ->
			// Patrol resumes... from the nearest path point" DOES need real
			// work: patrol_time_offset is solved here so that
			// Patrol_Camera_Pose's very next call lands exactly on the path
			// point nearest wherever the free camera currently is (see
			// Library/Camera.Patrol_Nearest_Angle's own comment for why
			// this is exact, not approximate, for this project's circular
			// path).
			if mode_switch_requested {
				if current_mode == .Inspection {
					desired_angle := cam.Patrol_Nearest_Angle(camera.position)
					base_angle := animation_time * cam.PATROL_ANGULAR_SPEED
					patrol_time_offset = (desired_angle - base_angle) / cam.PATROL_ANGULAR_SPEED
					current_mode = .Patrol
				} else {
					current_mode = .Inspection
				}
				glfw.SetWindowTitle(window, build_window_title())
				mode_switch_requested = false
			}

			// Roadmap step 10 (this session's task): select/translate/
			// rotate/reset only ever apply in Inspection Mode — Patrol's
			// own animation drivers own these same nodes while Patrol is
			// running (CLAUDE.md §2 item 9's "only the drivers... differ"),
			// so letting an edit key ALSO write here would fight them every
			// frame. The `else` branch discards any request that arrived
			// while NOT in Inspection, rather than leaving it queued — a
			// `[` pressed mid-Patrol, then a mode switch to Inspection a
			// minute later, should not suddenly replay a stale cycle.
			if current_mode == .Inspection {
				// Both flags MUST reset after use, same as every other
				// "_requested" flag below (reset_selected_requested,
				// reset_all_requested) — leaving either one true after
				// applying it meant a single `[`/`]` press re-cycled the
				// selection every subsequent frame forever (dozens of
				// times a second) for as long as Inspection Mode stayed
				// active, racing through every selectable object with no
				// way to land on one. The `else` branch below already
				// reset these, but only ever ran once Inspection Mode was
				// LEFT — it never helped while still inside it, which is
				// exactly where the bug bit.
				if select_prev_requested {
					selected_index = (selected_index - 1 + len(selectable_nodes)) % len(selectable_nodes)
					selected_node_name = scene.Nodes[selectable_nodes[selected_index]].Name
					glfw.SetWindowTitle(window, build_window_title())
					select_prev_requested = false
				}
				if select_next_requested {
					selected_index = (selected_index + 1) % len(selectable_nodes)
					selected_node_name = scene.Nodes[selectable_nodes[selected_index]].Name
					glfw.SetWindowTitle(window, build_window_title())
					select_next_requested = false
				}

				selected_scene_node := selectable_nodes[selected_index]
				if pending_translate_delta != (la.Vector3f32{0, 0, 0}) {
					Apply_Translate(&scene, selected_scene_node, pending_translate_delta)
					pending_translate_delta = {0, 0, 0}
				}
				if pending_rotate_delta != (la.Vector3f32{0, 0, 0}) {
					Apply_Rotate(&scene, selected_scene_node, pending_rotate_delta)
					pending_rotate_delta = {0, 0, 0}
				}
				if reset_selected_requested {
					Reset_Node(&scene, selected_scene_node, original_transforms[selected_scene_node])
					reset_selected_requested = false
				}
				if reset_all_requested {
					for i in 0 ..< len(scene.Nodes) {
						Reset_Node(&scene, i, original_transforms[i])
					}
					reset_all_requested = false
				}
			} else {
				select_prev_requested = false
				select_next_requested = false
				pending_translate_delta = {0, 0, 0}
				pending_rotate_delta = {0, 0, 0}
				reset_selected_requested = false
				reset_all_requested = false
				// A click during Patrol should NOT fire a pick the moment
				// the user later switches to Inspection, using whatever
				// view happens to exist by then — discard it here, same as
				// every other request above.
				pick_requested = false
			}
		}

		// Ground grid resolution changed (key G) — rebuild the mesh's CPU
		// data and re-upload its GPU buffers. Unlike every uniform toggle
		// in this file, this one genuinely changes the mesh's TOPOLOGY
		// (how many cells/vertices), not just a value read at draw time,
		// so it can't be a plain per-frame uniform upload — the old
		// GPU-side buffers have to be destroyed and new ones built. Only
		// happens on the frame right after a G press, not every frame.
		if ground_resolution_toggle_requested {
			geo.Destroy(&ground_mesh)
			ground_resolution = GROUND_GRID_HIGH_RESOLUTION if ground_resolution == GROUND_GRID_LOW_RESOLUTION else GROUND_GRID_LOW_RESOLUTION
			ground_mesh = build_ground_mesh(ground_resolution)
			fmt.printfln("Ground grid: %dx%d cells", ground_resolution, ground_resolution)
			ground_resolution_toggle_requested = false
		}

		// Roadmap step 9's shared animation clock ("All animation uses a
		// shared time source", this session's task) — advanced once here,
		// read by the Patrol camera pose AND every Patrol node/light
		// formula below, so they're all guaranteed to agree on "now". A
		// FIXED nominal step during --capture (matching Session 8's
		// deleted demo_time's own reproducibility reasoning: --capture's
		// CLAUDE.md §1.2 promise depends on frame N always landing at the
		// same pose, which real elapsed wall-clock time can't guarantee),
		// vs. real dt_seconds during an interactive run so playback speed
		// feels natural. Space (animation_paused) freezes it; `,`/`.`
		// (animation_speed_scale) rescale it — both work in EITHER mode,
		// a general "pause/speed the world" control, not Patrol-specific.
		frame_dt := dt_seconds
		if do_capture {
			frame_dt = 1.0 / 60.0
		}
		if !animation_paused {
			animation_time += frame_dt * animation_speed_scale
		}

		// Roadmap step 9: "only the drivers of the camera and node
		// transforms differ" between modes (this session's task, verbatim)
		// — so every Patrol-specific driver below, camera included, is
		// gated to current_mode == .Patrol. Switching to Inspection simply
		// STOPS writing these (not resets them), the same "freeze at the
		// last value, don't reset to a rest pose" choice, since nothing
		// asked for a rest-pose reset and roadmap step 10 (next session)
		// will give Inspection its own real node-manipulation drivers.
		if current_mode == .Patrol {
			camera_path_time := animation_time + patrol_time_offset
			camera.position, camera.yaw, camera.pitch = cam.Patrol_Camera_Pose(camera_path_time)

			if floodlight_head_node != scenepkg.NO_PARENT {
				scene.Nodes[floodlight_head_node].Local.Rotation.y = Patrol_Floodlight_Sweep_Angle(animation_time)
			}
			if radar_dish_node != scenepkg.NO_PARENT {
				scene.Nodes[radar_dish_node].Local.Rotation.y = Patrol_Radar_Spin_Angle(animation_time)
			}
			if beacon_light_index >= 0 {
				light_rig[beacon_light_index].Intensity = lightspkg.BEACON_INTENSITY * Patrol_Beacon_Intensity_Factor(animation_time)
			}

			// Optional life touches (this session's task marks these
			// optional and explicitly keeps the tank hull/jeep root
			// static — only the turret and the headlight NODES move).
			if tank_turret_node != scenepkg.NO_PARENT {
				scene.Nodes[tank_turret_node].Local.Rotation.y = Patrol_Turret_Scan_Angle(animation_time)
			}
			if jeep_headlight_left_node != scenepkg.NO_PARENT {
				scene.Nodes[jeep_headlight_left_node].Local.Rotation.x = Patrol_Jeep_Dip_Angle(animation_time)
			}
			if jeep_headlight_right_node != scenepkg.NO_PARENT {
				scene.Nodes[jeep_headlight_right_node].Local.Rotation.x = Patrol_Jeep_Dip_Angle(animation_time)
			}
			if fence_flicker_light_index >= 0 {
				light_rig[fence_flicker_light_index].Intensity = lightspkg.FENCE_LAMP_INTENSITY * Patrol_Fence_Flicker_Factor(animation_time)
			}
		}

		// Push this frame's cull/depth-test/wireframe toggles to GL — see
		// apply_render_state's own comment for why this runs every frame
		// rather than only right after a C/Z/F keypress.
		apply_render_state()

		gl.ClearColor(CLEAR_COLOR.x, CLEAR_COLOR.y, CLEAR_COLOR.z, CLEAR_COLOR.w); dbg.GL_Check()
		gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT); dbg.GL_Check()

		// Re-read the framebuffer size each frame (not just in the resize
		// callback) so the aspect ratio used here can never go stale between
		// a resize event and the next projection matrix build.
		current_fb_width, current_fb_height := glfw.GetFramebufferSize(window)
		aspect := f32(current_fb_width) / f32(current_fb_height)

		view := cam.View_Matrix(&camera)
		projection := cam.Projection_Matrix(&camera, aspect)

		// Roadmap step 10 (this session's task: mouse picking) — needs
		// `view`/`projection`, so it's handled here rather than in the
		// earlier input block above. A pick reads THIS frame's world
		// matrices (computed fresh right below) rather than a stale set,
		// so a pick immediately after a Patrol->Inspection switch (whose
		// camera pose changes this same frame) still ray-casts against
		// where objects actually are right now.
		if !do_capture && current_mode == .Inspection && pick_requested {
			ray_origin, ray_direction := Screen_Point_To_Ray(view, projection, 0, 0)
			pick_world_matrices := scenepkg.Compute_World_Matrices(&scene)
			picked := Pick_Node(pick_world_matrices[:], selectable_nodes[:], selectable_aabbs, ray_origin, ray_direction)
			delete(pick_world_matrices)
			if picked >= 0 {
				selected_index = picked
				selected_node_name = scene.Nodes[selectable_nodes[selected_index]].Name
				glfw.SetWindowTitle(window, build_window_title())
			}
		}
		pick_requested = false

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
		// Every light's world Position/Direction is re-derived fresh every
		// frame from its parent's CURRENT world matrix, never computed once
		// and reused as though fixed (CLAUDE.md §2 item 10) — this is what
		// makes the demo animation above (and, later, real Patrol/
		// Inspection Mode movement) actually visible on attached lights.
		lightspkg.Update_From_Scene(light_rig[:], world_matrices[:])
		lightspkg.Upload(&shader, light_rig[:])
		sd.SetUniform(&shader, "u_AreaLightSampleCount", i32(area_light_sample_count))
		jitter_value: i32 = 0
		if area_light_jitter do jitter_value = 1
		sd.SetUniform(&shader, "u_AreaLightJitter", jitter_value)
		sd.SetUniform(&shader, "u_ShadingMode", shading_mode)

		// Roadmap step 8 (CLAUDE.md §4/§9): culling/depth-visualization
		// uniforms Shaders/Scene.glsl's fragment stage reads — see
		// u_CullMode/u_ViewDirection/u_IsOrthographic's own comments there
		// for what each does and why direction-to-eye needs a different
		// formula per projection. Forward(cam) and camera.projection are
		// read fresh every frame, never cached, so this stays correct
		// across a live projection toggle (key P) or free-fly movement.
		sd.SetUniform(&shader, "u_CullMode", cull_mode)
		view_direction := cam.Forward(&camera)
		sd.SetUniform(&shader, "u_ViewDirection", view_direction.x, view_direction.y, view_direction.z)
		is_orthographic_value: i32 = 0
		if camera.projection == .Orthographic do is_orthographic_value = 1
		sd.SetUniform(&shader, "u_IsOrthographic", is_orthographic_value)
		backface_debug_value: i32 = 0
		if backface_debug_enabled do backface_debug_value = 1
		sd.SetUniform(&shader, "u_BackfaceDebug", backface_debug_value)
		depth_visualization_value: i32 = 0
		if depth_visualization_enabled do depth_visualization_value = 1
		sd.SetUniform(&shader, "u_DepthVisualization", depth_visualization_value)
		sd.SetUniform(&shader, "u_Near", camera.near)
		sd.SetUniform(&shader, "u_Far", camera.far)

		// Roadmap step 11 (CLAUDE.md §6.2, Prompts.md Session 14): the
		// proxy array is rebuilt from THIS frame's `world_matrices` —
		// already computed above, never cached — so a reflection updates
		// the instant an object moves, whether that's Patrol's own
		// animation or a live Inspection-Mode edit (this session's task:
		// "the reflection must update when the instructor moves the
		// reflected objects").
		frame_proxies := Build_Proxies(proxy_defs[:], world_matrices[:])
		Upload_Proxies(&shader, frame_proxies[:])
		delete(frame_proxies)
		reflection_enabled_value: i32 = 0
		if ray_traced_reflection_enabled do reflection_enabled_value = 1
		sd.SetUniform(&shader, "u_RayTracedReflectionEnabled", reflection_enabled_value)
		sd.SetUniform(&shader, "u_SkyColor", CLEAR_COLOR.x, CLEAR_COLOR.y, CLEAR_COLOR.z)

		// Polish pass (Prompts.md, post-Session-14): uniforms every fragment
		// reads regardless of what it's shading — see each one's own
		// comment in Shaders/Scene.glsl for what it does.
		tonemapping_value: i32 = 0
		if tonemapping_enabled do tonemapping_value = 1
		sd.SetUniform(&shader, "u_TonemappingEnabled", tonemapping_value)
		vignette_value: i32 = 0
		if vignette_enabled do vignette_value = 1
		sd.SetUniform(&shader, "u_VignetteEnabled", vignette_value)
		sd.SetUniform(&shader, "u_Resolution", f32(current_fb_width), f32(current_fb_height))
		fog_value: i32 = 0
		if fog_enabled do fog_value = 1
		sd.SetUniform(&shader, "u_FogEnabled", fog_value)
		sd.SetUniform(&shader, "u_Time", animation_time)

		// Sky dome — drawn FIRST (before the ground and every scene node),
		// with culling and depth-writing both off, so it paints only
		// whatever pixels nothing else draws over: the standard skybox
		// technique. u_IsSky reset to false immediately after so every
		// subsequent Draw_Node call (ground, scene nodes, gizmos) isn't
		// accidentally left in "sky mode" — GL program uniforms persist
		// across draw calls until explicitly overwritten.
		if sky_enabled {
			sky_model := la.matrix4_translate(camera.position)
			gl.Disable(gl.CULL_FACE); dbg.GL_Check()
			gl.DepthMask(false); dbg.GL_Check()
			sd.SetUniform(&shader, "u_IsSky", i32(1))
			scenepkg.Draw_Node(&shader, view, projection, sky_model, &sky_mesh, sky_material)
			sd.SetUniform(&shader, "u_IsSky", i32(0))
			gl.DepthMask(true); dbg.GL_Check()
			// Restores THIS frame's real cull_mode (C key) — apply_render_
			// state is idempotent (it was already called once above, before
			// gl.Clear), so calling it again here is just "undo the sky's
			// own temporary gl.Disable(CULL_FACE)", nothing more.
			apply_render_state()
		}

		// u_IsGround true for ONLY this one draw call (the ground plane
		// isn't part of the Scene hierarchy's node loop at all — see
		// u_IsGround's own comment in Shaders/Scene.glsl for why a
		// Material.Reflective-style per-node flag isn't needed here), reset
		// immediately after for the same "don't leak into the next draw
		// call" reason as u_IsSky above.
		ground_detail_value: i32 = 0
		if ground_detail_enabled do ground_detail_value = 1
		sd.SetUniform(&shader, "u_IsGround", ground_detail_value)
		scenepkg.Draw_Node(&shader, view, projection, ground_model, &ground_mesh, ground_material)
		sd.SetUniform(&shader, "u_IsGround", i32(0))

		// Roadmap step 10 (this session's task: "highlighted (tint...drawn
		// by the same render path)") — highlighted_node is -1 (never
		// matches any real node index) outside Inspection Mode, so Patrol
		// draws with no highlight at all, same as before this session.
		highlighted_node := selectable_nodes[selected_index] if current_mode == .Inspection else -1
		draw_scene_nodes(&shader, view, projection, &scene, world_matrices[:], highlighted_node, Inspection_Highlight_Pulse(animation_time))
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

		if do_benchmark {
			if frame_count > BENCHMARK_WARMUP_FRAMES {
				benchmark_frame_time_sum += dt_seconds
				benchmark_frame_time_min = min(benchmark_frame_time_min, dt_seconds)
				benchmark_frame_time_max = max(benchmark_frame_time_max, dt_seconds)
				benchmark_measured_frames += 1
			}
			if frame_count == benchmark_frames {
				if benchmark_measured_frames == 0 {
					fmt.eprintfln("Benchmark: --benchmark %d must exceed the %d warm-up frames", benchmark_frames, BENCHMARK_WARMUP_FRAMES)
					os.exit(1)
				}
				avg_ms := (benchmark_frame_time_sum / f32(benchmark_measured_frames)) * 1000.0
				avg_fps := 1000.0 / avg_ms
				target_ms := f32(1000.0 / 60.0)
				fmt.printfln(
					"Benchmark: %d frames measured (after %d warm-up, vsync off) at %dx%d — avg %.3fms (%.1f FPS), min %.3fms, max %.3fms",
					benchmark_measured_frames, BENCHMARK_WARMUP_FRAMES, fb_width, fb_height,
					avg_ms, avg_fps, benchmark_frame_time_min*1000.0, benchmark_frame_time_max*1000.0,
				)
				if avg_ms > target_ms {
					fmt.printfln("Benchmark: average frame time EXCEEDS the 60 FPS budget (%.3fms) by %.3fms", target_ms, avg_ms-target_ms)
				} else {
					fmt.printfln("Benchmark: holds 60 FPS with %.3fms of budget to spare", target_ms-avg_ms)
				}
				glfw.SetWindowShouldClose(window, true)
			}
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

// gizmos_visible toggles Library/Lights.Draw_Gizmos (key GRAVE_ACCENT).
// Starts from parse_gizmos_flag's result (set once in main() before the
// loop begins), then flips on each press exactly like
// projection_toggle_requested flips the projection above.
gizmos_visible: bool

// area_light_sample_count/area_light_jitter (roadmap step 6, CLAUDE.md
// §6.3) drive Shaders/Scene.glsl's u_AreaLightSampleCount/u_AreaLightJitter
// — +/- and N below, or --area-samples/--area-jitter for a --capture run.
// Both start from their parse_*_flag result in main(), same pattern as
// gizmos_visible above.
area_light_sample_count: int
area_light_jitter: bool

// shading_mode drives Shaders/Scene.glsl's u_ShadingMode (keys 1/2/3,
// roadmap step 7). ground_resolution/ground_resolution_toggle_requested
// drive the ground grid's cell count (key G) — the toggle is a REQUEST
// flag rather than flipping ground_resolution directly, same "callback
// sets a flag, the main loop does the actual work" pattern
// projection_toggle_requested already uses, since rebuilding the grid
// touches GPU/Engine state a "c" callback shouldn't reach into directly.
shading_mode: i32
ground_resolution: int
ground_resolution_toggle_requested: bool

// Roadmap step 8 (CLAUDE.md §4/§9, Prompts.md Session 11) toggle state —
// same "callback sets the var directly, the main loop applies/uploads it"
// pattern shading_mode/gizmos_visible/area_light_jitter already use above.
// No separate "_requested" flag is needed here the way ground_resolution's
// mesh rebuild needed one: applying these is just a handful of gl.Enable/
// Disable/PolygonMode calls (apply_render_state, called from the main
// loop), not a GPU buffer rebuild.
cull_mode: i32
depth_test_enabled: bool
depth_visualization_enabled: bool
wireframe_enabled: bool
backface_debug_enabled: bool

// Roadmap step 9 (CLAUDE.md §7/§9, Prompts.md Session 12) Patrol Mode
// state. current_mode/animation_paused are flipped directly in
// key_callback (Tab/Space), same simple-bool pattern as gizmos_visible;
// mode_switch_requested is a deferred flag (like projection_toggle_
// requested) because handling a mode switch needs read/write access to
// `camera`/`animation_time` — real work the main loop does, not a "c"
// callback. patrol_time_offset is written ONCE per Inspection->Patrol
// switch (see the main loop) and read every Patrol frame afterward.
current_mode: Mode
mode_switch_requested: bool
animation_time: f32
animation_paused: bool
animation_speed_scale: f32
patrol_time_offset: f32

// Roadmap step 10 (CLAUDE.md §7/§9, Prompts.md Session 13) Inspection Mode
// selection/editing state. selected_index indexes INTO selectable_nodes
// (a main()-local list — see Source/Inspection.odin's Build_Selectable_
// Nodes), not directly into scene.Nodes; selected_node_name is a display-
// only cache kept in sync whenever selection changes, read by
// build_window_title (same reason MODE_NAME/SHADING_MODE_NAME etc. are
// plain package vars: build_window_title is called from key_callback,
// which has no access to main()'s local `scene`). Every *_requested/
// pending_* below follows the SAME "callback sets it, main loop consumes
// and clears it" pattern this file already uses for projection_toggle_
// requested and friends.
selected_index: int
selected_node_name: string
select_next_requested: bool
select_prev_requested: bool
pick_requested: bool
pending_translate_delta: la.Vector3f32
pending_rotate_delta: la.Vector3f32
edit_step_scale: f32
reset_selected_requested: bool
reset_all_requested: bool

// Roadmap step 11 (CLAUDE.md §6.2, Prompts.md Session 14) — R toggles the
// ray-traced reflection, same "callback sets the var directly" pattern as
// every other simple toggle above.
ray_traced_reflection_enabled: bool

// Polish pass (Prompts.md, post-Session-14) toggle state — same "callback
// sets the var directly, the main loop applies/uploads it" pattern every
// toggle above already uses. See each DEFAULT_*_ENABLED constant's own
// comment for the on-by-default reasoning.
tonemapping_enabled: bool
vignette_enabled: bool
fog_enabled: bool
ground_detail_enabled: bool
sky_enabled: bool

// fps_display_value is the last computed rolling-average FPS (updated at
// most every FPS_DISPLAY_UPDATE_INTERVAL, main loop); fps_display_accum_*
// are that average's own in-progress accumulators, reset every time it
// fires. build_window_title reads fps_display_value the same way it reads
// every other toggle state below.
fps_display_value: f32
fps_display_accum_time: f32
fps_display_accum_frames: int

key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
	// "c" calling convention procs get no implicit Odin context (unlike an
	// ordinary proc) — build_window_title below needs one (it calls
	// fmt.ctprintf, which allocates from context.temp_allocator), so every
	// other GLFW "c" callback in this file that only touches plain package
	// vars never needed this, but this one does the moment it also builds a
	// title string.
	context = runtime.default_context()

	if key == glfw.KEY_ESCAPE && action == glfw.PRESS {
		glfw.SetWindowShouldClose(window, true)
	}
	if key == glfw.KEY_P && action == glfw.PRESS {
		projection_toggle_requested = true
	}
	// GRAVE_ACCENT, not L: L was already claimed by Inspection Mode's IJKL
	// translate cluster below (local X+), so both bindings fired on every L
	// press regardless of mode — an unwanted gizmo-visibility side effect
	// every time an object was translated along local X+ in Inspection
	// Mode. Moved to the conventional "toggle debug overlay" key instead of
	// reassigning the IJKL cluster, since IJKL's own layout is the
	// documented, muscle-memory-relevant control (README/Print_Controls).
	if key == glfw.KEY_GRAVE_ACCENT && action == glfw.PRESS {
		gizmos_visible = !gizmos_visible
	}
	// EQUAL/KP_ADD share the same "+/-" pairing on most keyboards ('+' is
	// shift-EQUAL, not its own key on a US layout); both are wired so the
	// comparison this session's task asks for (N=1 vs N=8) is one keypress
	// away regardless of numpad availability.
	if (key == glfw.KEY_EQUAL || key == glfw.KEY_KP_ADD) && action == glfw.PRESS {
		area_light_sample_count = min(area_light_sample_count + 1, lightspkg.MAX_AREA_LIGHT_SAMPLES)
	}
	if (key == glfw.KEY_MINUS || key == glfw.KEY_KP_SUBTRACT) && action == glfw.PRESS {
		area_light_sample_count = max(area_light_sample_count - 1, 1)
	}
	// N, not J (roadmap step 10, Prompts.md Session 13): J is now claimed by
	// Inspection Mode's IJKL translate cluster below (this session's task
	// names IJKL specifically), so area-light jitter moved here — a
	// deliberate reassignment, documented in README/PROGRESS.md, not a
	// silent break of a Session 9 control.
	if key == glfw.KEY_N && action == glfw.PRESS {
		area_light_jitter = !area_light_jitter
	}
	if key == glfw.KEY_1 && action == glfw.PRESS {
		shading_mode = SHADING_FLAT
		glfw.SetWindowTitle(window, build_window_title())
	}
	if key == glfw.KEY_2 && action == glfw.PRESS {
		shading_mode = SHADING_GOURAUD
		glfw.SetWindowTitle(window, build_window_title())
	}
	if key == glfw.KEY_3 && action == glfw.PRESS {
		shading_mode = SHADING_PHONG
		glfw.SetWindowTitle(window, build_window_title())
	}
	if key == glfw.KEY_G && action == glfw.PRESS {
		ground_resolution_toggle_requested = true
	}
	// Roadmap step 8 (CLAUDE.md §4/§9, Prompts.md Session 11): C cycles
	// OFF -> MANUAL -> GL (the exact order the task asks for), Z/X/F/B each
	// flip one independent bool. Every branch also refreshes the window
	// title (item 5's "show current toggle states" ask) the same way the
	// 1/2/3 branches above already do for shading_mode.
	if key == glfw.KEY_C && action == glfw.PRESS {
		cull_mode = (cull_mode + 1) % 3
		glfw.SetWindowTitle(window, build_window_title())
	}
	if key == glfw.KEY_Z && action == glfw.PRESS {
		depth_test_enabled = !depth_test_enabled
		glfw.SetWindowTitle(window, build_window_title())
	}
	if key == glfw.KEY_X && action == glfw.PRESS {
		depth_visualization_enabled = !depth_visualization_enabled
		glfw.SetWindowTitle(window, build_window_title())
	}
	if key == glfw.KEY_F && action == glfw.PRESS {
		wireframe_enabled = !wireframe_enabled
		glfw.SetWindowTitle(window, build_window_title())
	}
	if key == glfw.KEY_B && action == glfw.PRESS {
		backface_debug_enabled = !backface_debug_enabled
		glfw.SetWindowTitle(window, build_window_title())
	}
	// Roadmap step 9 (CLAUDE.md §7/§9, Prompts.md Session 12): Tab is a
	// deferred request (see mode_switch_requested's own comment for why —
	// unlike Space/`,`/`.` below, handling it needs `camera`/
	// `animation_time`, not just a bool flip). Space pauses the SHARED
	// animation clock (works in either mode, a general "pause the world"
	// control, not Patrol-specific — this session's task: "a pause key
	// (Space) and speed keys"). `,`/`.` rescale it multiplicatively
	// (PATROL_SPEED_STEP_FACTOR per press), clamped to [PATROL_MIN_SPEED_
	// SCALE, PATROL_MAX_SPEED_SCALE].
	if key == glfw.KEY_TAB && action == glfw.PRESS {
		mode_switch_requested = true
	}
	if key == glfw.KEY_SPACE && action == glfw.PRESS {
		animation_paused = !animation_paused
		glfw.SetWindowTitle(window, build_window_title())
	}
	if key == glfw.KEY_PERIOD && action == glfw.PRESS {
		animation_speed_scale = min(animation_speed_scale*PATROL_SPEED_STEP_FACTOR, f32(PATROL_MAX_SPEED_SCALE))
		glfw.SetWindowTitle(window, build_window_title())
	}
	if key == glfw.KEY_COMMA && action == glfw.PRESS {
		animation_speed_scale = max(animation_speed_scale/PATROL_SPEED_STEP_FACTOR, f32(PATROL_MIN_SPEED_SCALE))
		glfw.SetWindowTitle(window, build_window_title())
	}

	// Roadmap step 10 (CLAUDE.md §7/§9, Prompts.md Session 13): Inspection
	// Mode selection/editing. All of these only ever take effect while the
	// main loop is actually in Inspection Mode (it discards them otherwise,
	// see the main loop's own comment on why) — set unconditionally here so
	// key_callback stays the simple "just flip/accumulate a var" shape
	// every other key above already uses, with the mode check centralized
	// in the one place that applies them (craft: push ifs up).
	if key == glfw.KEY_LEFT_BRACKET && action == glfw.PRESS {
		select_prev_requested = true
	}
	if key == glfw.KEY_RIGHT_BRACKET && action == glfw.PRESS {
		select_next_requested = true
	}
	// PRESS or REPEAT (a key held down long enough fires REPEAT at the OS's
	// own key-repeat rate) — this session's task asks for discrete "step
	// size" stepping, not continuous WASD-style held movement, but holding
	// a step key down to step repeatedly is still the expected feel, not a
	// held-key CONTINUOUS drag.
	if key == glfw.KEY_J && (action == glfw.PRESS || action == glfw.REPEAT) {
		pending_translate_delta.x -= BASE_TRANSLATE_STEP * edit_step_scale
	}
	if key == glfw.KEY_L && (action == glfw.PRESS || action == glfw.REPEAT) {
		pending_translate_delta.x += BASE_TRANSLATE_STEP * edit_step_scale
	}
	if key == glfw.KEY_I && (action == glfw.PRESS || action == glfw.REPEAT) {
		pending_translate_delta.z -= BASE_TRANSLATE_STEP * edit_step_scale
	}
	if key == glfw.KEY_K && (action == glfw.PRESS || action == glfw.REPEAT) {
		pending_translate_delta.z += BASE_TRANSLATE_STEP * edit_step_scale
	}
	if key == glfw.KEY_U && (action == glfw.PRESS || action == glfw.REPEAT) {
		pending_translate_delta.y += BASE_TRANSLATE_STEP * edit_step_scale
	}
	if key == glfw.KEY_O && (action == glfw.PRESS || action == glfw.REPEAT) {
		pending_translate_delta.y -= BASE_TRANSLATE_STEP * edit_step_scale
	}
	// Yaw/pitch/roll around the node's own LOCAL axes (Transform.Rotation's
	// existing X=pitch/Y=yaw/Z=roll convention, Library/Scene/Transform.
	// odin) — numbers rather than more letters specifically to avoid a
	// second IJKL-style collision hunt; 1/2/3 are already shading, so 4-9
	// were the next clean, unclaimed block.
	rotate_step := math.to_radians(f32(BASE_ROTATE_STEP_DEGREES)) * edit_step_scale
	if key == glfw.KEY_4 && (action == glfw.PRESS || action == glfw.REPEAT) {
		pending_rotate_delta.y -= rotate_step
	}
	if key == glfw.KEY_5 && (action == glfw.PRESS || action == glfw.REPEAT) {
		pending_rotate_delta.y += rotate_step
	}
	if key == glfw.KEY_6 && (action == glfw.PRESS || action == glfw.REPEAT) {
		pending_rotate_delta.x -= rotate_step
	}
	if key == glfw.KEY_7 && (action == glfw.PRESS || action == glfw.REPEAT) {
		pending_rotate_delta.x += rotate_step
	}
	if key == glfw.KEY_8 && (action == glfw.PRESS || action == glfw.REPEAT) {
		pending_rotate_delta.z -= rotate_step
	}
	if key == glfw.KEY_9 && (action == glfw.PRESS || action == glfw.REPEAT) {
		pending_rotate_delta.z += rotate_step
	}
	if key == glfw.KEY_APOSTROPHE && action == glfw.PRESS {
		edit_step_scale = min(edit_step_scale*EDIT_STEP_FACTOR, f32(EDIT_STEP_MAX_SCALE))
		fmt.printfln("Edit step scale: %.2fx", edit_step_scale)
		glfw.SetWindowTitle(window, build_window_title())
	}
	if key == glfw.KEY_SEMICOLON && action == glfw.PRESS {
		edit_step_scale = max(edit_step_scale/EDIT_STEP_FACTOR, f32(EDIT_STEP_MIN_SCALE))
		fmt.printfln("Edit step scale: %.2fx", edit_step_scale)
		glfw.SetWindowTitle(window, build_window_title())
	}
	// 0 resets the SELECTED node; Shift+0 resets ALL nodes — one key, mods
	// distinguishes them, rather than needing a second dedicated key.
	if key == glfw.KEY_0 && action == glfw.PRESS {
		if mods & glfw.MOD_SHIFT != 0 {
			reset_all_requested = true
		} else {
			reset_selected_requested = true
		}
	}
	if key == glfw.KEY_H && action == glfw.PRESS {
		Print_Controls()
	}
	// Roadmap step 11 (CLAUDE.md §6.2, Prompts.md Session 14): R toggles
	// the ray-traced reflection — works in either mode, same as every
	// other debug/comparison toggle (C/Z/X/F/B) above.
	if key == glfw.KEY_R && action == glfw.PRESS {
		ray_traced_reflection_enabled = !ray_traced_reflection_enabled
		glfw.SetWindowTitle(window, build_window_title())
	}
	// Polish pass (Prompts.md, post-Session-14): M/V/Y/T/`/` — the 5
	// unclaimed letter keys left in this project by this point (every
	// other single letter is either a movement key, WASD/QE, or already
	// bound above) plus one punctuation key for the 5th. Each just flips
	// its own bool and retitles, same pattern as every toggle above.
	if key == glfw.KEY_M && action == glfw.PRESS {
		tonemapping_enabled = !tonemapping_enabled
		glfw.SetWindowTitle(window, build_window_title())
	}
	if key == glfw.KEY_V && action == glfw.PRESS {
		vignette_enabled = !vignette_enabled
		glfw.SetWindowTitle(window, build_window_title())
	}
	if key == glfw.KEY_Y && action == glfw.PRESS {
		fog_enabled = !fog_enabled
		glfw.SetWindowTitle(window, build_window_title())
	}
	if key == glfw.KEY_T && action == glfw.PRESS {
		ground_detail_enabled = !ground_detail_enabled
		glfw.SetWindowTitle(window, build_window_title())
	}
	if key == glfw.KEY_SLASH && action == glfw.PRESS {
		sky_enabled = !sky_enabled
		glfw.SetWindowTitle(window, build_window_title())
	}
}

// mouse_button_callback only ever handles the LEFT button — see Screen_
// Point_To_Ray's own comment (Source/Inspection.odin) for why picking uses
// the viewport centre rather than this event's own (button, mods) aren't
// even needed beyond identifying which button. Deferred (pick_requested)
// like every other main-loop-applied request, since picking needs `scene`/
// `camera`/`view`/`projection`, none of which a "c" callback can reach.
mouse_button_callback :: proc "c" (window: glfw.WindowHandle, button, action, mods: i32) {
	if button == glfw.MOUSE_BUTTON_LEFT && action == glfw.PRESS {
		pick_requested = true
	}
}

// build_window_title reads every render-toggle package var (shading_mode,
// cull_mode, depth_test_enabled, wireframe_enabled, backface_debug_enabled,
// depth_visualization_enabled) and formats them into one title string —
// task item 5's "show current toggle states in the window title" ask, now
// covering 6 toggles instead of Session 10's original 1 (shading mode
// alone). Called both to build the INITIAL window title (before the window
// even exists — glfw.CreateWindow just wants a cstring, no window handle
// needed to build one) and again after every keypress above that changes
// one of these vars.
build_window_title :: proc() -> cstring {
	depth_state := "On" if depth_test_enabled else "Off"
	wireframe_state := "On" if wireframe_enabled else "Off"
	backface_debug_state := "On" if backface_debug_enabled else "Off"
	depth_visualization_state := "On" if depth_visualization_enabled else "Off"
	reflection_state := "On" if ray_traced_reflection_enabled else "Off"
	// Polish pass (Prompts.md, post-Session-14) — same "Name:State" style as
	// every toggle above, abbreviated (Tone/Vig/Grnd) so 5 more toggles
	// don't make an already-long title unreadable.
	tonemapping_state := "On" if tonemapping_enabled else "Off"
	vignette_state := "On" if vignette_enabled else "Off"
	fog_state := "On" if fog_enabled else "Off"
	ground_detail_state := "On" if ground_detail_enabled else "Off"
	sky_state := "On" if sky_enabled else "Off"
	// Roadmap step 9: shown as a bracketed suffix only while actually
	// paused, rather than an always-on "Paused:Off" chunk — the title is
	// already six toggles long, and Off is the overwhelmingly common case.
	paused_suffix := " [Paused]" if animation_paused else ""
	// Roadmap step 10 (this session's task: "shown in the window
	// title/overlay"): the selected node's name only while actually in
	// Inspection Mode — a selection persists across a mode switch (nothing
	// asked for it to reset), but showing "Sel:X" while hands-off Patrol is
	// running would read as if the instructor could edit something they
	// currently can't.
	// Step: rides along with Sel: for the same reason — edit_step_scale
	// (`;`/`'`) had a real effect (console-only, via fmt.printfln) but no
	// on-screen confirmation at all, which reads as "the key does
	// nothing" the same way an un-retitled toggle would.
	selection_suffix := fmt.tprintf(" Sel:%s Step:%.2fx", selected_node_name, edit_step_scale) if current_mode == .Inspection else ""

	return fmt.ctprintf(
		"SENTINEL - %s - %s%s | Speed:%.2fx Cull:%s Depth:%s Wire:%s BFDbg:%s DepthVis:%s Refl:%s Tone:%s Vig:%s Fog:%s Grnd:%s Sky:%s FPS:%.0f%s",
		MODE_NAME[current_mode],
		SHADING_MODE_NAME[shading_mode],
		paused_suffix,
		animation_speed_scale,
		CULL_MODE_NAME[cull_mode],
		depth_state,
		wireframe_state,
		backface_debug_state,
		depth_visualization_state,
		reflection_state,
		tonemapping_state,
		vignette_state,
		fog_state,
		ground_detail_state,
		sky_state,
		fps_display_value,
		selection_suffix,
	)
}

// apply_render_state pushes this frame's cull_mode/depth_test_enabled/
// wireframe_enabled package vars to actual GL state — called every frame
// from the main loop (not from key_callback) rather than only right after a
// C/Z/F keypress, the same "state mutation centralized in the main loop,
// not scattered into a callback" choice this file already makes for every
// other per-frame GL/uniform update (e.g. gl.ClearColor is re-issued every
// frame too, not just when CLEAR_COLOR "changes" — it never does, but the
// pattern is the same: read state, push it, every frame, exactly once).
apply_render_state :: proc() {
	switch cull_mode {
	case CULL_OFF:
		gl.Disable(gl.CULL_FACE)
	case CULL_MANUAL:
		// The rasterizer still draws every triangle; Shaders/Scene.glsl's
		// manual back-face test in the fragment stage does the discarding
		// instead — see that shader's u_CullMode comment for why this
		// reaches the SAME image as CULL_GL but without CULL_GL's actual
		// performance saving.
		gl.Disable(gl.CULL_FACE)
	case CULL_GL:
		// Hardware culling: a winding-order test in the rasterizer, before
		// any fragment shader invocation — where the real saving over
		// MANUAL comes from (see the triangle-count log printed at
		// startup). CCW front faces, matching every Geometry generator's
		// documented winding convention (Library/Geometry/Geometry.odin's
		// header).
		gl.Enable(gl.CULL_FACE)
		gl.CullFace(gl.BACK)
		gl.FrontFace(gl.CCW)
	}
	dbg.GL_Check()

	if depth_test_enabled {
		gl.Enable(gl.DEPTH_TEST)
	} else {
		gl.Disable(gl.DEPTH_TEST)
	}
	dbg.GL_Check()

	if wireframe_enabled {
		gl.PolygonMode(gl.FRONT_AND_BACK, gl.LINE)
	} else {
		gl.PolygonMode(gl.FRONT_AND_BACK, gl.FILL)
	}
	dbg.GL_Check()
}

// count_total_triangles sums len(Indices)/3 across every drawn mesh in the
// scene (the 9 objects' own hierarchy plus the ground plane, which — like
// Source/Main.odin's other ground-plane handling — sits outside the
// Hierarchy and so isn't counted by Scene.Build_Scene's own object count).
// Task item 6's "total submitted" half of the triangle-count log.
count_total_triangles :: proc(scene: ^scenepkg.Hierarchy, ground_mesh: ^geo.Mesh) -> int {
	total := len(ground_mesh.Indices) / 3
	for node in scene.Nodes {
		total += len(node.Mesh.Indices) / 3
	}
	return total
}

// count_back_facing_triangles is a CPU-side ESTIMATE, for ONE mesh, of how
// many of its triangles face away from a given (constant, per-object, not
// per-triangle) view direction — task item 6's own wording: "estimated
// back-facing (optional counter computed CPU-side for one object as a
// demo)". Reuses each triangle's first vertex's own stored Normal rather
// than recomputing cross(edge1, edge2): every Geometry generator already
// duplicates vertices per face (Geometry.odin's own header), so a
// triangle's 3 indices already share one Normal — the local-space face
// normal, already sitting right there in Mesh.Vertices.
count_back_facing_triangles :: proc(mesh: ^geo.Mesh, normal_matrix: la.Matrix3f32, view_direction: la.Vector3f32) -> int {
	count := 0
	for i := 0; i < len(mesh.Indices); i += 3 {
		local_normal := mesh.Vertices[mesh.Indices[i]].Normal
		world_normal := la.normalize(la.mul(normal_matrix, local_normal))
		if la.dot(world_normal, view_direction) < 0 do count += 1
	}
	return count
}

// find_light_by_parent returns the index of the FIRST light in `lights`
// whose ParentNode matches `node`, or -1 if none does. Used once at
// startup (not per-frame) to locate the specific lights Patrol Mode
// animates (the radar beacon, one fence lamp) by the SCENE NODE they're
// attached to, rather than a hardcoded array index into Library/Lights.
// Build_Rig's internal append order — that order is Build_Rig's own
// implementation detail, not something this file should have to know or
// keep in sync by hand.
find_light_by_parent :: proc(lights: []lightspkg.Light, node: int) -> int {
	for light, i in lights {
		if light.ParentNode == node do return i
	}
	return -1
}

// build_ground_mesh builds and uploads the ground plane's LOCAL-space mesh
// as a `resolution` x `resolution` grid of small geo.Plane cells, stitched
// together via Append_Mesh — CLAUDE.md §2 item 6's only allowed way to
// build anything beyond a single Cube/Tetrahedron/Plane instance, so this
// is a composition loop over Plane, not a new dedicated grid generator.
// geo.Plane lies in the local XY plane facing +Z (Library/Geometry/
// Geometry.odin's own comment); each cell is placed at its own (x, y)
// offset within that same local plane, and the WHOLE grid still gets
// ground_model's single -90-degree rotation about X at draw time to lay
// it flat facing +Y — unchanged from before this session, and why cell
// placement below only ever touches x/y, never z.
//
// Why resolution matters (roadmap step 7's own task text): GOURAUD
// evaluates lighting at each triangle's 3 corners and interpolates the
// RESULT — a spotlight's hot centre landing inside one giant triangle (the
// old single-quad ground, resolution=1) can never show up, since none of
// the 4 corners of that one quad were anywhere near the light. More, smaller
// cells (a higher resolution) means more vertices actually sampling
// lighting near where the light actually is, so Gouraud's approximation
// gets visibly closer to Phong's per-fragment result — never perfect, but
// closer. Source/Main.odin's `G` key toggles between GROUND_GRID_LOW_
// RESOLUTION and _HIGH_RESOLUTION specifically to make that comparison a
// live keypress away.
build_ground_mesh :: proc(resolution: int) -> geo.Mesh {
	mesh := geo.Empty_Mesh()

	cell_size := GROUND_SIZE / f32(resolution)
	cell := geo.Plane(cell_size, cell_size)
	defer geo.Destroy(&cell)

	for row in 0 ..< resolution {
		for col in 0 ..< resolution {
			x := -GROUND_SIZE*0.5 + cell_size*(f32(col) + 0.5)
			y := -GROUND_SIZE*0.5 + cell_size*(f32(row) + 0.5)
			geo.Append_Mesh(&mesh, cell, la.matrix4_translate(la.Vector3f32{x, y, 0}))
		}
	}

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

// parse_area_samples_flag looks for "--area-samples <N>" anywhere in argv
// — the non-interactive way to pick a starting area-light sample count for
// a --capture run (the +/- keys are skipped during --capture, same as
// every other live input), specifically so an N=1-vs-N=8 comparison
// capture pair doesn't depend on live key-hold timing. Defaults to
// DEFAULT_AREA_LIGHT_SAMPLE_COUNT; clamps (not errors) an out-of-range
// value to [1, MAX_AREA_LIGHT_SAMPLES] — same range the live +/- keys are
// already clamped to, so a --capture run can't silently ask for something
// the shader's fixed-size MAX_AREA_SAMPLES array couldn't hold anyway.
parse_area_samples_flag :: proc(args: []string) -> int {
	for i := 0; i < len(args); i += 1 {
		if args[i] != "--area-samples" do continue

		if i + 1 >= len(args) {
			fmt.eprintln("--area-samples requires one argument: <N>")
			os.exit(1)
		}

		parsed, ok := strconv.parse_int(args[i + 1])
		if !ok {
			fmt.eprintfln("--area-samples: expected an integer, got '%s'", args[i + 1])
			os.exit(1)
		}

		return clamp(parsed, 1, lightspkg.MAX_AREA_LIGHT_SAMPLES)
	}

	return DEFAULT_AREA_LIGHT_SAMPLE_COUNT
}

// parse_area_jitter_flag looks for a bare "--area-jitter" flag anywhere in
// argv, the non-interactive way to force jitter on for a --capture run —
// same reasoning as parse_gizmos_flag above.
parse_area_jitter_flag :: proc(args: []string) -> bool {
	for arg in args {
		if arg == "--area-jitter" do return true
	}
	return false
}

// parse_shading_flag looks for "--shading <flat|gouraud|phong>" anywhere in
// argv — the non-interactive way to pick a starting shading mode for a
// --capture run (keys 1/2/3 are skipped during --capture, same as every
// other live input), specifically so the same-view flat/Gouraud/Phong
// comparison this session's task asks for doesn't depend on live
// key-press timing. Defaults to DEFAULT_SHADING_MODE (Phong).
parse_shading_flag :: proc(args: []string) -> i32 {
	for i := 0; i < len(args); i += 1 {
		if args[i] != "--shading" do continue

		if i + 1 >= len(args) {
			fmt.eprintln("--shading requires one argument: <flat|gouraud|phong>")
			os.exit(1)
		}

		switch args[i + 1] {
		case "flat":
			return SHADING_FLAT
		case "gouraud":
			return SHADING_GOURAUD
		case "phong":
			return SHADING_PHONG
		case:
			fmt.eprintfln("--shading: expected 'flat', 'gouraud', or 'phong', got '%s'", args[i + 1])
			os.exit(1)
		}
	}

	return DEFAULT_SHADING_MODE
}

// parse_ground_resolution_flag looks for "--ground-resolution <low|high>"
// anywhere in argv — the non-interactive way to pick a starting ground
// grid density for a --capture run (the G key is skipped during
// --capture), same reasoning as parse_shading_flag above. Defaults to
// GROUND_GRID_LOW_RESOLUTION, matching every prior session's single-quad
// ground.
parse_ground_resolution_flag :: proc(args: []string) -> int {
	for i := 0; i < len(args); i += 1 {
		if args[i] != "--ground-resolution" do continue

		if i + 1 >= len(args) {
			fmt.eprintln("--ground-resolution requires one argument: <low|high>")
			os.exit(1)
		}

		switch args[i + 1] {
		case "low":
			return GROUND_GRID_LOW_RESOLUTION
		case "high":
			return GROUND_GRID_HIGH_RESOLUTION
		case:
			fmt.eprintfln("--ground-resolution: expected 'low' or 'high', got '%s'", args[i + 1])
			os.exit(1)
		}
	}

	return GROUND_GRID_LOW_RESOLUTION
}

// parse_cull_flag looks for "--cull <off|manual|gl>" anywhere in argv — the
// non-interactive way to pick a starting cull mode for a --capture run (the
// C key is skipped during --capture, same as every other live input),
// specifically so the OFF-vs-MANUAL-vs-GL comparison this session's task
// asks to "verify... give the same image" doesn't depend on live key-press
// timing. Defaults to DEFAULT_CULL_MODE (GL), matching every prior
// session's always-on culling behaviour.
parse_cull_flag :: proc(args: []string) -> i32 {
	for i := 0; i < len(args); i += 1 {
		if args[i] != "--cull" do continue

		if i + 1 >= len(args) {
			fmt.eprintln("--cull requires one argument: <off|manual|gl>")
			os.exit(1)
		}

		switch args[i + 1] {
		case "off":
			return CULL_OFF
		case "manual":
			return CULL_MANUAL
		case "gl":
			return CULL_GL
		case:
			fmt.eprintfln("--cull: expected 'off', 'manual', or 'gl', got '%s'", args[i + 1])
			os.exit(1)
		}
	}

	return DEFAULT_CULL_MODE
}

// parse_depth_test_flag looks for "--depth-test <on|off>" anywhere in argv
// — the non-interactive way to pick a starting depth-test state for a
// --capture run (the Z key is skipped during --capture). A value-taking
// flag rather than a bare one (unlike --wireframe/--gizmos/etc. below)
// because the DEFAULT is "on", so a bare "--depth-test" flag would be
// ambiguous about which state it's requesting.
parse_depth_test_flag :: proc(args: []string) -> bool {
	for i := 0; i < len(args); i += 1 {
		if args[i] != "--depth-test" do continue

		if i + 1 >= len(args) {
			fmt.eprintln("--depth-test requires one argument: <on|off>")
			os.exit(1)
		}

		switch args[i + 1] {
		case "on":
			return true
		case "off":
			return false
		case:
			fmt.eprintfln("--depth-test: expected 'on' or 'off', got '%s'", args[i + 1])
			os.exit(1)
		}
	}

	return true
}

// parse_wireframe_flag looks for a bare "--wireframe" flag anywhere in
// argv, the non-interactive way to force wireframe mode on for a --capture
// run (the F key is skipped during --capture) — same reasoning as
// parse_gizmos_flag above. Defaults to off, matching wireframe_enabled's
// zero value for a normal interactive run before the first F press.
parse_wireframe_flag :: proc(args: []string) -> bool {
	for arg in args {
		if arg == "--wireframe" do return true
	}
	return false
}

// parse_backface_debug_flag looks for a bare "--backface-debug" flag
// anywhere in argv, the non-interactive way to force the magenta back-face
// tint on for a --capture run (the B key is skipped during --capture) —
// same reasoning as parse_gizmos_flag above.
parse_backface_debug_flag :: proc(args: []string) -> bool {
	for arg in args {
		if arg == "--backface-debug" do return true
	}
	return false
}

// parse_depth_visualization_flag looks for a bare "--depth-visualization"
// flag anywhere in argv, the non-interactive way to force the grayscale
// linearised-depth view on for a --capture run (the X key is skipped during
// --capture) — same reasoning as parse_gizmos_flag above.
parse_depth_visualization_flag :: proc(args: []string) -> bool {
	for arg in args {
		if arg == "--depth-visualization" do return true
	}
	return false
}

// parse_mode_flag looks for "--mode <patrol|inspection>" anywhere in argv —
// the non-interactive way to pick a starting Mode for a --capture run (Tab
// is skipped during --capture, same as every other live input). Defaults
// to Patrol — CLAUDE.md §7's own framing ("Zero input required... intended
// as a hands-off showcase"), so a plain `./Sentinel` with no flags now
// shows the automatic patrol immediately instead of a static free camera.
parse_mode_flag :: proc(args: []string) -> Mode {
	for i := 0; i < len(args); i += 1 {
		if args[i] != "--mode" do continue

		if i + 1 >= len(args) {
			fmt.eprintln("--mode requires one argument: <patrol|inspection>")
			os.exit(1)
		}

		switch args[i + 1] {
		case "patrol":
			return .Patrol
		case "inspection":
			return .Inspection
		case:
			fmt.eprintfln("--mode: expected 'patrol' or 'inspection', got '%s'", args[i + 1])
			os.exit(1)
		}
	}

	return DEFAULT_MODE
}

// parse_patrol_speed_flag looks for "--patrol-speed <scale>" anywhere in
// argv — the non-interactive way to pick a starting animation_speed_scale
// for a --capture run (the `,`/`.` keys are skipped during --capture).
// Defaults to DEFAULT_ANIMATION_SPEED_SCALE. Exits on a non-positive value
// (a zero or negative scale would either silently freeze animation or run
// it backwards, neither of which this flag is meant to express — omit it,
// or use --mode inspection, for "nothing moving").
parse_patrol_speed_flag :: proc(args: []string) -> f32 {
	for i := 0; i < len(args); i += 1 {
		if args[i] != "--patrol-speed" do continue

		if i + 1 >= len(args) {
			fmt.eprintln("--patrol-speed requires one argument: <scale>")
			os.exit(1)
		}

		parsed, ok := strconv.parse_f32(args[i + 1])
		if !ok || parsed <= 0 {
			fmt.eprintfln("--patrol-speed: expected a positive number, got '%s'", args[i + 1])
			os.exit(1)
		}

		return parsed
	}

	return DEFAULT_ANIMATION_SPEED_SCALE
}

// parse_reflection_flag looks for "--reflection <on|off>" anywhere in argv
// — the non-interactive way to pick a starting ray-traced-reflection state
// for a --capture run (the R key is skipped during --capture, same as
// every other live input). Defaults to DEFAULT_RAY_TRACED_REFLECTION_
// ENABLED (on).
parse_reflection_flag :: proc(args: []string) -> bool {
	for i := 0; i < len(args); i += 1 {
		if args[i] != "--reflection" do continue

		if i + 1 >= len(args) {
			fmt.eprintln("--reflection requires one argument: <on|off>")
			os.exit(1)
		}

		switch args[i + 1] {
		case "on":
			return true
		case "off":
			return false
		case:
			fmt.eprintfln("--reflection: expected 'on' or 'off', got '%s'", args[i + 1])
			os.exit(1)
		}
	}

	return DEFAULT_RAY_TRACED_REFLECTION_ENABLED
}

// parse_tonemapping_flag looks for "--tonemapping <on|off>" anywhere in
// argv — the non-interactive way to pick a starting tonemapping state for a
// --capture/--benchmark run (the M key is skipped during either), same
// pattern as parse_reflection_flag above.
parse_tonemapping_flag :: proc(args: []string) -> bool {
	for i := 0; i < len(args); i += 1 {
		if args[i] != "--tonemapping" do continue

		if i + 1 >= len(args) {
			fmt.eprintln("--tonemapping requires one argument: <on|off>")
			os.exit(1)
		}

		switch args[i + 1] {
		case "on":
			return true
		case "off":
			return false
		case:
			fmt.eprintfln("--tonemapping: expected 'on' or 'off', got '%s'", args[i + 1])
			os.exit(1)
		}
	}

	return DEFAULT_TONEMAPPING_ENABLED
}

// parse_vignette_flag looks for "--vignette <on|off>" anywhere in argv —
// same pattern as parse_tonemapping_flag above.
parse_vignette_flag :: proc(args: []string) -> bool {
	for i := 0; i < len(args); i += 1 {
		if args[i] != "--vignette" do continue

		if i + 1 >= len(args) {
			fmt.eprintln("--vignette requires one argument: <on|off>")
			os.exit(1)
		}

		switch args[i + 1] {
		case "on":
			return true
		case "off":
			return false
		case:
			fmt.eprintfln("--vignette: expected 'on' or 'off', got '%s'", args[i + 1])
			os.exit(1)
		}
	}

	return DEFAULT_VIGNETTE_ENABLED
}

// parse_fog_flag looks for "--fog <on|off>" anywhere in argv — same pattern
// as parse_tonemapping_flag above.
parse_fog_flag :: proc(args: []string) -> bool {
	for i := 0; i < len(args); i += 1 {
		if args[i] != "--fog" do continue

		if i + 1 >= len(args) {
			fmt.eprintln("--fog requires one argument: <on|off>")
			os.exit(1)
		}

		switch args[i + 1] {
		case "on":
			return true
		case "off":
			return false
		case:
			fmt.eprintfln("--fog: expected 'on' or 'off', got '%s'", args[i + 1])
			os.exit(1)
		}
	}

	return DEFAULT_FOG_ENABLED
}

// parse_ground_detail_flag looks for "--ground-detail <on|off>" anywhere in
// argv — same pattern as parse_tonemapping_flag above.
parse_ground_detail_flag :: proc(args: []string) -> bool {
	for i := 0; i < len(args); i += 1 {
		if args[i] != "--ground-detail" do continue

		if i + 1 >= len(args) {
			fmt.eprintln("--ground-detail requires one argument: <on|off>")
			os.exit(1)
		}

		switch args[i + 1] {
		case "on":
			return true
		case "off":
			return false
		case:
			fmt.eprintfln("--ground-detail: expected 'on' or 'off', got '%s'", args[i + 1])
			os.exit(1)
		}
	}

	return DEFAULT_GROUND_DETAIL_ENABLED
}

// parse_sky_flag looks for "--sky <on|off>" anywhere in argv — same pattern
// as parse_tonemapping_flag above.
parse_sky_flag :: proc(args: []string) -> bool {
	for i := 0; i < len(args); i += 1 {
		if args[i] != "--sky" do continue

		if i + 1 >= len(args) {
			fmt.eprintln("--sky requires one argument: <on|off>")
			os.exit(1)
		}

		switch args[i + 1] {
		case "on":
			return true
		case "off":
			return false
		case:
			fmt.eprintfln("--sky: expected 'on' or 'off', got '%s'", args[i + 1])
			os.exit(1)
		}
	}

	return DEFAULT_SKY_ENABLED
}

// parse_benchmark_flag looks for "--benchmark <frames>" anywhere in argv —
// this session's required "check that we hold 60 FPS" tooling: unlike
// --capture, a benchmark run disables vsync (see glfw.SwapInterval's own
// comment above) and prints a real avg/min/max frame-time report instead of
// saving a screenshot. Mirrors parse_capture_flag's own argument-parsing
// shape.
parse_benchmark_flag :: proc(args: []string) -> (frames: int, requested: bool) {
	for i := 0; i < len(args); i += 1 {
		if args[i] != "--benchmark" do continue

		if i + 1 >= len(args) {
			fmt.eprintln("--benchmark requires one argument: <frames>")
			os.exit(1)
		}

		parsed_frames, ok := strconv.parse_int(args[i + 1])
		if !ok || parsed_frames <= BENCHMARK_WARMUP_FRAMES {
			fmt.eprintfln("--benchmark: expected an integer frame count > %d, got '%s'", BENCHMARK_WARMUP_FRAMES, args[i + 1])
			os.exit(1)
		}

		return parsed_frames, true
	}

	return 0, false
}

// parse_msaa_flag looks for "--msaa <N>" anywhere in argv — N is a sample
// count (2, 4, 8...), passed straight through to glfw.WindowHint(SAMPLES,
// N) before window creation (see that call site's own comment for why this
// can't be a live key like every other polish toggle). Omitted entirely
// (returns 0) means "don't request multisampling", this project's exact
// pre-polish behaviour.
parse_msaa_flag :: proc(args: []string) -> i32 {
	for i := 0; i < len(args); i += 1 {
		if args[i] != "--msaa" do continue

		if i + 1 >= len(args) {
			fmt.eprintln("--msaa requires one argument: <sample count>")
			os.exit(1)
		}

		parsed_samples, ok := strconv.parse_int(args[i + 1])
		if !ok || parsed_samples <= 0 {
			fmt.eprintfln("--msaa: expected a positive integer sample count, got '%s'", args[i + 1])
			os.exit(1)
		}

		return i32(parsed_samples)
	}

	return 0
}

// parse_test_inspection_flag looks for "--test-inspection <path-prefix>"
// anywhere in argv — this session's required "debug CLI option" for the
// headless rotate-the-turret-and-verify-the-searchlight-moved sequence
// (Source/Inspection.odin's Run_Inspection_Test). `<path-prefix>_before.bmp`
// and `<path-prefix>_after.bmp` are where the two screenshots land.
parse_test_inspection_flag :: proc(args: []string) -> (prefix: string, requested: bool) {
	for i := 0; i < len(args); i += 1 {
		if args[i] != "--test-inspection" do continue

		if i + 1 >= len(args) {
			fmt.eprintln("--test-inspection requires one argument: <path-prefix>")
			os.exit(1)
		}

		return args[i + 1], true
	}

	return "", false
}
