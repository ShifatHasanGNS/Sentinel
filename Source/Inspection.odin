// Inspection.odin — Inspection Mode's selection, mouse-picking, and
// translate/rotate editing (roadmap step 10, CLAUDE.md §7/§9; Prompts.md
// Session 13). Source/Main.odin's file header has anticipated a dedicated
// file for this since Session 11 ("GLFW key/mouse callbacks, object
// selection... added once Inspection Mode exists") — this is that file,
// following the same split Source/Patrol.odin established last session:
// every proc here is either a PURE function (AABB/ray math, the highlight
// colour blend) or an explicit-parameter mutator (Apply_Translate/
// Apply_Rotate/Reset_Node) — nothing reaches into package-level state
// directly except the few read-only constants below, so the SAME procs
// are usable from both the interactive main loop and the headless test
// routine at the bottom of this file without duplicating any logic.
package main

import "core:fmt"
import "core:math"
import la "core:math/linalg"
import "core:os"

import "vendor:glfw"
import gl "vendor:OpenGL"

import cam "../Library/Camera"
import geo "../Library/Geometry"
import lightspkg "../Library/Lights"
import scenepkg "../Library/Scene"
import dbg "../Library/Engine/Debugger"
import sd "../Library/Engine/Shader"
import capture "../Debug"

// The 3 independently-movable SUB-nodes this session's task explicitly
// names beyond the 9 root objects ("tank hull, tank turret, tower
// floodlight head, radar dish, jeep, etc." — tank hull/jeep are already
// root objects, so the genuinely NEW additions are these three). Not an
// open-ended "every child node is selectable" list: the other child nodes
// (jeep/tank headlights, tank barrel/periscope, barracks windows) aren't
// independently interesting to translate/rotate for a demo, and CLAUDE.md
// §5.3's required hierarchy-verification chains (tower, jeep, tank
// hull->turret) are already fully covered by root Tank Hull + this list's
// Tank Turret and Watchtower Floodlight Head.
SELECTABLE_SUB_NODE_NAMES :: [3]string{"Tank Turret", "Watchtower Floodlight Head", "Radar Dish"}

// Build_Selectable_Nodes returns every selectable Scene node index: the 9
// root objects in their Build_Scene order, then the 3 named sub-nodes
// above, in that fixed order — `[`/`]` cycle through this list, not
// scene.Nodes directly (which also includes non-selectable children like
// headlight housings and barracks windows).
Build_Selectable_Nodes :: proc(scene: ^scenepkg.Hierarchy) -> [dynamic]int {
	selectable := make([dynamic]int, 0, 12)

	for node, i in scene.Nodes {
		if node.Parent == scenepkg.NO_PARENT do append(&selectable, i)
	}
	for name in SELECTABLE_SUB_NODE_NAMES {
		index := scenepkg.Find_Node(scene, name)
		if index == scenepkg.NO_PARENT {
			panic(fmt.tprintf("Source/Inspection.odin: Scene has no node named %q — Objects.odin and this list have drifted out of sync", name))
		}
		append(&selectable, index)
	}

	return selectable
}

// ---------------------------------------------------------------------------
// Highlighting the selected node — a material EMISSION tint blended in at
// draw time, through the exact same Scene.Draw_Node path every other mesh
// already uses (this session's task: "highlighted (tint or outline drawn
// by the same render path)"). No shader change, no second pass, no
// outline mesh: draw_scene_nodes below just hands Draw_Node a temporarily
// brightened COPY of the selected node's own Material for one draw call,
// never mutating the node's stored Material itself.
// ---------------------------------------------------------------------------

INSPECTION_HIGHLIGHT_COLOR :: la.Vector3f32{0.7, 1.0, 1.0}
INSPECTION_HIGHLIGHT_PULSE_RATE :: 3.0 // rad/s, argument to sin()

// Inspection_Highlight_Pulse returns a [0, 1] pulsing factor for the
// selected-node tint — a gentle breathing highlight (CLAUDE.md §2 item 5:
// a runtime formula, not a static tint) so the selection reads clearly
// even against an already-bright material, and keeps drawing the eye back
// to it during a long editing session.
Inspection_Highlight_Pulse :: proc(t: f32) -> f32 {
	return 0.5 + 0.5*math.sin(t*INSPECTION_HIGHLIGHT_PULSE_RATE)
}

// draw_scene_nodes draws every node in `scene`, applying the highlight
// tint to exactly ONE (`highlighted_node`, or -1 for none) — factored out
// so the interactive main loop and Run_Inspection_Test below share this
// one drawing path instead of two copies of the same highlight logic
// (craft: don't duplicate logic).
draw_scene_nodes :: proc(shader: ^sd.Shader, view, projection: la.Matrix4f32, scene: ^scenepkg.Hierarchy, world_matrices: []la.Matrix4f32, highlighted_node: int, highlight_pulse: f32) {
	for &node, i in scene.Nodes {
		model := world_matrices[i]
		material := node.Material
		if i == highlighted_node {
			material.EmissionColor += INSPECTION_HIGHLIGHT_COLOR * highlight_pulse
		}
		scenepkg.Draw_Node(shader, view, projection, model, &node.Mesh, material)
	}
}

// ---------------------------------------------------------------------------
// Translate / rotate / reset — all operate on the node's LOCAL transform
// (this session's task, verbatim: "so children follow and attached lights
// follow automatically" — Scene.Compute_World_Matrices already composes
// world = parent_world * local every frame, and Library/Lights.Update_
// From_Scene already re-derives every light's world position/direction
// from its parent's CURRENT world matrix every frame, CLAUDE.md §2 item
// 10 — so editing a LOCAL transform is the entire mechanism; nothing else
// needs to know an edit happened).
// ---------------------------------------------------------------------------

BASE_TRANSLATE_STEP :: 0.25 // world units per key press, before edit_step_scale
BASE_ROTATE_STEP_DEGREES :: 5.0 // degrees per key press, before edit_step_scale

EDIT_STEP_MIN_SCALE :: 0.2
EDIT_STEP_MAX_SCALE :: 5.0
EDIT_STEP_FACTOR :: 1.25 // multiplicative per `;`/`'` press, same convention Patrol's speed keys use

Apply_Translate :: proc(scene: ^scenepkg.Hierarchy, node_index: int, local_delta: la.Vector3f32) {
	scene.Nodes[node_index].Local.Position += local_delta
}

Apply_Rotate :: proc(scene: ^scenepkg.Hierarchy, node_index: int, local_delta_radians: la.Vector3f32) {
	scene.Nodes[node_index].Local.Rotation += local_delta_radians
}

Reset_Node :: proc(scene: ^scenepkg.Hierarchy, node_index: int, original: scenepkg.Transform) {
	scene.Nodes[node_index].Local = original
}

// ---------------------------------------------------------------------------
// Mouse picking (this session's task: "ray from the cursor through the
// inverse projection/view, tested against bounding spheres/boxes" — a good
// place to show off inverse projection). Implemented for real, not
// skipped, but with one deliberate, documented adaptation: SEE
// Screen_Point_To_Ray's own comment on why the "cursor" here is the
// viewport CENTRE, not GLFW's live cursor position.
// ---------------------------------------------------------------------------

AABB :: struct {
	Min, Max: [3]f32,
}

// Compute_Local_AABB scans a mesh's own LOCAL-space vertices once (at
// startup, per selectable node — not per frame) for its axis-aligned
// bounding box. Plain [3]f32 rather than la.Vector3f32 specifically so
// Ray_Intersects_AABB below can loop over axes with `[i]` indexing, which
// this project's other code never needed to rely on la.Vector3f32
// supporting.
Compute_Local_AABB :: proc(mesh: ^geo.Mesh) -> AABB {
	box := AABB{Min = {1e30, 1e30, 1e30}, Max = {-1e30, -1e30, -1e30}}
	for v in mesh.Vertices {
		box.Min[0] = min(box.Min[0], v.Position.x)
		box.Min[1] = min(box.Min[1], v.Position.y)
		box.Min[2] = min(box.Min[2], v.Position.z)
		box.Max[0] = max(box.Max[0], v.Position.x)
		box.Max[1] = max(box.Max[1], v.Position.y)
		box.Max[2] = max(box.Max[2], v.Position.z)
	}
	return box
}

// Ray_Intersects_AABB is the standard slab method: shrink [t_min, t_max]
// against each axis's pair of planes in turn, empty means no hit. Returns
// the nearest non-negative hit distance `t` (so a ray starting INSIDE the
// box still reports a sane t=0-ish hit, not the far exit point).
Ray_Intersects_AABB :: proc(ray_origin, ray_direction: la.Vector3f32, box: AABB) -> (t: f32, hit: bool) {
	origin := [3]f32{ray_origin.x, ray_origin.y, ray_origin.z}
	dir := [3]f32{ray_direction.x, ray_direction.y, ray_direction.z}

	t_min := f32(-1e30)
	t_max := f32(1e30)
	for axis in 0 ..< 3 {
		if abs(dir[axis]) < 1e-8 {
			// Ray parallel to this axis's slab: either always inside it
			// (origin within [min, max]) or never hits the box at all.
			if origin[axis] < box.Min[axis] || origin[axis] > box.Max[axis] do return 0, false
			continue
		}

		inv_dir := 1.0 / dir[axis]
		t1 := (box.Min[axis] - origin[axis]) * inv_dir
		t2 := (box.Max[axis] - origin[axis]) * inv_dir
		if t1 > t2 do t1, t2 = t2, t1

		t_min = max(t_min, t1)
		t_max = min(t_max, t2)
		if t_min > t_max do return 0, false
	}

	if t_max < 0 do return 0, false // whole box is behind the ray
	return t_min if t_min >= 0 else t_max, true
}

// Screen_Point_To_Ray unprojects one NDC point (x, y both in [-1, 1])
// through the INVERSE of view*projection, at both the near and far planes,
// and returns the world-space ray between them — the literal "ray from the
// cursor through the inverse projection/view" this session's task asks
// for, and correct for BOTH projections without a special case: in
// perspective every ray's ORIGIN differs slightly per pixel (converging
// toward the eye, not literally AT it) and points outward; in orthographic
// every ray is parallel but each has its OWN origin on the near plane —
// unprojecting the actual near point (rather than assuming camera.position
// as a shared origin) handles both automatically.
//
// The "cursor" fed into this is the viewport CENTRE, not GLFW's live
// cursor position — a deliberate adaptation, not a shortcut: Inspection
// Mode's free-fly camera runs with the cursor in glfw.CURSOR_DISABLED mode
// (Source/Main.odin, unchanged since Session 2) so mouse movement can
// drive unbounded look deltas; GLFW's own docs state the position reported
// in that mode is a virtual accumulator, not a real on-screen pixel
// coordinate, so unprojecting it would pick whatever's under a
// meaningless, unbounded number, not whatever's visually under the cursor.
// A viewport-centre "crosshair" pick — aim the camera at the object, left-
// click to select it — sidesteps that entirely using the EXACT SAME ray
// math a true cursor-position pick would use, and is a standard, honest
// convention for exactly this kind of FPS-style captured-cursor camera.
Screen_Point_To_Ray :: proc(view, projection: la.Matrix4f32, ndc_x, ndc_y: f32) -> (origin, direction: la.Vector3f32) {
	inverse_view_projection := la.matrix4_inverse(la.mul(projection, view))

	near_clip := la.Vector4f32{ndc_x, ndc_y, -1, 1}
	far_clip := la.Vector4f32{ndc_x, ndc_y, 1, 1}

	near_world := la.mul(inverse_view_projection, near_clip)
	far_world := la.mul(inverse_view_projection, far_clip)

	near_point := la.Vector3f32{near_world.x, near_world.y, near_world.z} / near_world.w
	far_point := la.Vector3f32{far_world.x, far_world.y, far_world.z} / far_world.w

	origin = near_point
	direction = la.normalize(far_point - near_point)
	return
}

// Pick_Node casts one ray against every selectable node's world-space AABB
// (its LOCAL-space box transformed by taking the ray into LOCAL space via
// the node's own inverse world matrix, rather than transforming 8 box
// corners into world space every call) and returns the index INTO
// `selectable` of the NEAREST hit, or -1 if the ray hits nothing.
Pick_Node :: proc(world_matrices: []la.Matrix4f32, selectable: []int, local_aabbs: []AABB, ray_origin, ray_direction: la.Vector3f32) -> int {
	best_index := -1
	best_t := f32(1e30)

	for node_index, i in selectable {
		world := world_matrices[node_index]
		inverse_world := la.matrix4_inverse(world)

		local_origin4 := la.mul(inverse_world, la.Vector4f32{ray_origin.x, ray_origin.y, ray_origin.z, 1})
		local_direction4 := la.mul(inverse_world, la.Vector4f32{ray_direction.x, ray_direction.y, ray_direction.z, 0})
		local_origin := la.Vector3f32{local_origin4.x, local_origin4.y, local_origin4.z}
		local_direction := la.Vector3f32{local_direction4.x, local_direction4.y, local_direction4.z}

		t, hit := Ray_Intersects_AABB(local_origin, local_direction, local_aabbs[i])
		if hit && t < best_t {
			best_t = t
			best_index = i
		}
	}

	return best_index
}

// ---------------------------------------------------------------------------
// Printed key list (this session's task: "a help overlay OR printed key
// list (H)" — this project has no text-rendering pipeline to draw an
// overlay with, same reasoning Session 10/11's window-title toggles
// already established, so the printed-list fallback is the honest choice,
// not a shortcut). Also printed once at startup, unconditionally, so a
// fresh run always shows the controls without needing an H press first.
// ---------------------------------------------------------------------------

Print_Controls :: proc() {
	fmt.println("--- SENTINEL controls (H to reprint) ---")
	fmt.println("  Tab          Switch Patrol <-> Inspection Mode")
	fmt.println("  Space        Pause / resume the shared animation clock")
	fmt.println("  , / .        Slow down / speed up the animation clock")
	fmt.println("  W/A/S/D      (Inspection) Move forward/strafe")
	fmt.println("  Q / E        (Inspection) Move down / up")
	fmt.println("  Shift        (Inspection) Sprint")
	fmt.println("  Mouse        (Inspection) Look")
	fmt.println("  P            Toggle perspective / orthographic")
	fmt.println("  Scroll       Zoom the orthographic volume")
	fmt.println("  [ / ]        (Inspection) Select previous / next object")
	fmt.println("  Left click   (Inspection) Pick the object at the screen centre")
	fmt.println("  I / K        (Inspection) Translate selected object: local Z-/Z+")
	fmt.println("  J / L        (Inspection) Translate selected object: local X-/X+")
	fmt.println("  U / O        (Inspection) Translate selected object: local Y-/Y+")
	fmt.println("  4 / 5        (Inspection) Rotate selected object: yaw-/yaw+")
	fmt.println("  6 / 7        (Inspection) Rotate selected object: pitch-/pitch+")
	fmt.println("  8 / 9        (Inspection) Rotate selected object: roll-/roll+")
	fmt.println("  ; / '        (Inspection) Decrease / increase translate+rotate step size")
	fmt.println("  0            (Inspection) Reset selected object to its original transform")
	fmt.println("  Shift+0      (Inspection) Reset ALL objects to their original transforms")
	fmt.println("  L            Toggle light gizmos")
	fmt.println("  + / -        Increase / decrease area-light sample count")
	fmt.println("  N            Toggle area-light per-pixel jitter")
	fmt.println("  1 / 2 / 3    Shading mode: Flat / Gouraud / Phong")
	fmt.println("  G            Toggle ground-grid resolution")
	fmt.println("  C            Cycle back-face culling: Off -> Manual -> GL")
	fmt.println("  Z            Toggle the depth test")
	fmt.println("  X            Toggle depth visualisation")
	fmt.println("  F            Toggle wireframe")
	fmt.println("  B            Toggle back-face debug tint")
	fmt.println("  R            Toggle ray-traced reflection (jeep windshield, tank periscope, barracks windows)")
	fmt.println("  H            Print this list again")
	fmt.println("  Esc          Quit")
}

// ---------------------------------------------------------------------------
// Headless test (this session's task: "script a headless sequence... that
// selects the tank turret, rotates it, and asserts the searchlight's world
// position changed as expected. Capture screenshots for before/after").
// Runs entirely through REAL code paths (Compute_World_Matrices, Update_
// From_Scene, Apply_Rotate, draw_scene_nodes, Debug.Save_Screenshot) rather
// than a separate mock/simulation, so a pass here is genuine evidence the
// actual hierarchy-following behaviour works, not just that this test's
// own arithmetic is self-consistent.
// ---------------------------------------------------------------------------

INSPECTION_TEST_TURRET_ROTATION_DEGREES :: 90.0
// A moved-but-not-nothing threshold: at the turret searchlight's own
// offset from its pivot (Library/Lights.Build_Rig: roughly half the
// turret's own width away), even a few degrees of rotation moves it by
// noticeably more than this — see the run's own printed numbers for the
// ACTUAL distance, this is just the floor for "clearly not a no-op".
INSPECTION_TEST_MIN_MOVEMENT :: 0.05
// How much the searchlight's OWN distance from the turret's world position
// (its pivot) is allowed to drift — should be ~0 for a pure rotation about
// that pivot; a real translation bug (as opposed to a rotation) would move
// the light without preserving this distance.
INSPECTION_TEST_MAX_RADIUS_DRIFT :: 0.01

// inspection_test_render_and_capture draws one frame (real world-matrix
// recompute, real Update_From_Scene, real draw_scene_nodes) and saves a
// screenshot — a top-level proc (not nested in Run_Inspection_Test below)
// specifically because Odin's `name :: proc(...) {}` proc declarations do
// NOT close over an enclosing proc's locals; every value it needs
// (including the test camera's own position/near/far) is an explicit
// parameter instead.
@(private = "file")
inspection_test_render_and_capture :: proc(
	window: glfw.WindowHandle,
	shader: ^sd.Shader,
	view, projection: la.Matrix4f32,
	view_position: la.Vector3f32,
	near, far: f32,
	scene: ^scenepkg.Hierarchy,
	light_rig: []lightspkg.Light,
	highlighted_node: int,
	fb_width, fb_height: int,
	path: string,
) {
	gl.ClearColor(CLEAR_COLOR.x, CLEAR_COLOR.y, CLEAR_COLOR.z, CLEAR_COLOR.w); dbg.GL_Check()
	gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT); dbg.GL_Check()

	world_matrices := scenepkg.Compute_World_Matrices(scene)
	defer delete(world_matrices)
	lightspkg.Update_From_Scene(light_rig, world_matrices[:])
	lightspkg.Upload(shader, light_rig)

	sd.SetUniform(shader, "u_ViewPosition", view_position.x, view_position.y, view_position.z)
	sd.SetUniform(shader, "u_AmbientColor", AMBIENT_COLOR.r, AMBIENT_COLOR.g, AMBIENT_COLOR.b)
	sd.SetUniform(shader, "u_AmbientStrength", f32(AMBIENT_STRENGTH))
	sd.SetUniform(shader, "u_AreaLightSampleCount", i32(DEFAULT_AREA_LIGHT_SAMPLE_COUNT))
	sd.SetUniform(shader, "u_AreaLightJitter", i32(0))
	sd.SetUniform(shader, "u_ShadingMode", DEFAULT_SHADING_MODE)
	sd.SetUniform(shader, "u_CullMode", DEFAULT_CULL_MODE)
	sd.SetUniform(shader, "u_ViewDirection", 0.0, 0.0, -1.0)
	sd.SetUniform(shader, "u_IsOrthographic", i32(0))
	sd.SetUniform(shader, "u_BackfaceDebug", i32(0))
	sd.SetUniform(shader, "u_DepthVisualization", i32(0))
	sd.SetUniform(shader, "u_Near", near)
	sd.SetUniform(shader, "u_Far", far)

	draw_scene_nodes(shader, view, projection, scene, world_matrices[:], highlighted_node, Inspection_Highlight_Pulse(0))

	if err := capture.Save_Screenshot(path, fb_width, fb_height); err != nil {
		fmt.eprintfln("FAIL: screenshot to %s failed: %v", path, err)
		os.exit(1)
	}
	glfw.SwapBuffers(window)
}

// Run_Inspection_Test executes the scripted sequence and exits the process
// with 0 (pass) or 1 (fail) — it does not return, since there is no
// sensible "continue running normally afterward" for a test entry point.
Run_Inspection_Test :: proc(
	window: glfw.WindowHandle,
	scene: ^scenepkg.Hierarchy,
	light_rig: []lightspkg.Light,
	shader: ^sd.Shader,
	path_prefix: string,
	fb_width, fb_height: int,
) {
	fmt.println("--- Inspection Mode headless test: rotate Tank Turret, verify searchlight moves ---")

	turret_node := scenepkg.Find_Node(scene, "Tank Turret")
	if turret_node == scenepkg.NO_PARENT {
		fmt.eprintln("FAIL: no 'Tank Turret' node found")
		os.exit(1)
	}
	searchlight_index := find_light_by_parent(light_rig, turret_node)
	if searchlight_index < 0 {
		fmt.eprintln("FAIL: no light parented to 'Tank Turret' found")
		os.exit(1)
	}

	// A fixed, reproducible camera — same eye/target every run, same
	// reasoning --capture's own reproducibility promise already relies on
	// (CLAUDE.md §1.2), since this test's own pass/fail doesn't depend on
	// the view but its two screenshots should still be comparable images.
	test_camera := cam.Camera_Looking_At(CAMERA_START_EYE, SCENE_FOCUS)
	view := cam.View_Matrix(&test_camera)
	projection := cam.Projection_Matrix(&test_camera, f32(fb_width)/f32(fb_height))

	// BEFORE: render/capture, then read the searchlight's world position
	// and its distance from the turret's own world position (its pivot).
	before_path := fmt.tprintf("%s_before.bmp", path_prefix)
	inspection_test_render_and_capture(window, shader, view, projection, test_camera.position, test_camera.near, test_camera.far, scene, light_rig, turret_node, fb_width, fb_height, before_path)
	before_world_matrices := scenepkg.Compute_World_Matrices(scene)
	before_pivot := scenepkg.World_Position(before_world_matrices[turret_node])
	before_position := light_rig[searchlight_index].Position
	before_radius := la.length(before_position - before_pivot)
	delete(before_world_matrices)
	fmt.printfln("  Before: turret yaw=%.1f deg, searchlight world position=%v (radius from pivot %.4f)", math.to_degrees(scene.Nodes[turret_node].Local.Rotation.y), before_position, before_radius)

	// ACT: rotate the turret by a fixed test angle — the SAME Apply_Rotate
	// the interactive 4/5/6/7/8/9 keys call, not a separate code path.
	Apply_Rotate(scene, turret_node, la.Vector3f32{0, math.to_radians(f32(INSPECTION_TEST_TURRET_ROTATION_DEGREES)), 0})

	// AFTER: render/capture, then re-read the same two values.
	after_path := fmt.tprintf("%s_after.bmp", path_prefix)
	inspection_test_render_and_capture(window, shader, view, projection, test_camera.position, test_camera.near, test_camera.far, scene, light_rig, turret_node, fb_width, fb_height, after_path)
	after_world_matrices := scenepkg.Compute_World_Matrices(scene)
	after_pivot := scenepkg.World_Position(after_world_matrices[turret_node])
	after_position := light_rig[searchlight_index].Position
	after_radius := la.length(after_position - after_pivot)
	delete(after_world_matrices)
	fmt.printfln("  After:  turret yaw=%.1f deg, searchlight world position=%v (radius from pivot %.4f)", math.to_degrees(scene.Nodes[turret_node].Local.Rotation.y), after_position, after_radius)

	movement := la.length(after_position - before_position)
	radius_drift := abs(after_radius - before_radius)
	fmt.printfln("  Searchlight moved %.4f world units; pivot-radius drift %.4f", movement, radius_drift)

	passed := true
	if movement < INSPECTION_TEST_MIN_MOVEMENT {
		fmt.eprintfln("FAIL: searchlight moved only %.4f units (< %.4f) — rotation doesn't appear to be reaching the light", movement, f32(INSPECTION_TEST_MIN_MOVEMENT))
		passed = false
	}
	if radius_drift > INSPECTION_TEST_MAX_RADIUS_DRIFT {
		fmt.eprintfln("FAIL: distance from turret pivot drifted by %.4f (> %.4f) — moved like a translation, not a rotation about the pivot", radius_drift, f32(INSPECTION_TEST_MAX_RADIUS_DRIFT))
		passed = false
	}

	if passed {
		fmt.println("PASS: rotating Tank Turret moved the searchlight's world position as a rotation about the turret's own pivot, hierarchy-correct.")
		os.exit(0)
	}
	os.exit(1)
}
