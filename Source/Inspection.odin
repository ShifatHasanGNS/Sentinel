// Inspection Mode: selection, mouse picking, translate/rotate editing.
package main

import "core:fmt"
import "core:math"
import la "core:math/linalg"
import "core:os"

import "vendor:glfw"
import gl "vendor:OpenGL"

import cam "../Library/Camera"
import geo "../Library/Geometry"
import scenepkg "../Library/Scene"
import dbg "../Library/Engine/Debugger"
import sd "../Library/Engine/Shader"
import capture "../Debug"

SELECTABLE_SUB_NODE_NAMES :: [3]string{"Tank Turret", "Watchtower Floodlight Head", "Radar Dish"}

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

INSPECTION_HIGHLIGHT_COLOR :: la.Vector3f32{0.7, 1.0, 1.0}
INSPECTION_HIGHLIGHT_PULSE_RATE :: 3.0 // rad/s, argument to sin()

Inspection_Highlight_Pulse :: proc(t: f32) -> f32 {
	return 0.5 + 0.5*math.sin(t*INSPECTION_HIGHLIGHT_PULSE_RATE)
}

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

// Translate/rotate/reset act on the node's LOCAL transform, so children and attached lights follow automatically.

BASE_TRANSLATE_STEP :: 0.25 // world units per key press, before edit_step_scale
BASE_ROTATE_STEP_DEGREES :: 5.0 // degrees per key press, before edit_step_scale

EDIT_STEP_MIN_SCALE :: 0.2
EDIT_STEP_MAX_SCALE :: 5.0
// 1.5x, not 1.25x: against a 0.25-unit/5-degree base step, a 25% change per
// press was too subtle to feel in a single translate/rotate press (reported
// after the Step:%.2fx title readout was already confirmed working) — 1.5x
// still reaches both EDIT_STEP_MIN/MAX_SCALE (same range as before), just in
// 4 presses each way instead of 8, with each press actually moving the needle.
EDIT_STEP_FACTOR :: 1.5 // multiplicative per press

Apply_Translate :: proc(scene: ^scenepkg.Hierarchy, node_index: int, local_delta: la.Vector3f32) {
	scene.Nodes[node_index].Local.Position += local_delta
}

Apply_Rotate :: proc(scene: ^scenepkg.Hierarchy, node_index: int, local_delta_radians: la.Vector3f32) {
	scene.Nodes[node_index].Local.Rotation += local_delta_radians
}

Reset_Node :: proc(scene: ^scenepkg.Hierarchy, node_index: int, original: scenepkg.Transform) {
	scene.Nodes[node_index].Local = original
}

AABB :: struct {
	Min, Max: [3]f32,
}

// Local-space AABB, computed once per selectable node.
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

// Slab method; returns nearest non-negative hit t.
Ray_Intersects_AABB :: proc(ray_origin, ray_direction: la.Vector3f32, box: AABB) -> (t: f32, hit: bool) {
	origin := [3]f32{ray_origin.x, ray_origin.y, ray_origin.z}
	dir := [3]f32{ray_direction.x, ray_direction.y, ray_direction.z}

	t_min := f32(-1e30)
	t_max := f32(1e30)
	for axis in 0 ..< 3 {
		if abs(dir[axis]) < 1e-8 {
			// parallel to axis: inside range, or no hit
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

	if t_max < 0 do return 0, false // box is behind the ray
	return t_min if t_min >= 0 else t_max, true
}

// Unprojects NDC (near/far) through the inverse of view*projection. Uses the viewport CENTRE, not the
// live cursor: Inspection's free-fly camera runs with CURSOR_DISABLED, whose reported position is a
// virtual accumulator, not a real pixel — so a centre-crosshair pick is used instead.
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

// Nearest AABB hit among `selectable`, or -1.
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
	fmt.println("  Shift+C      (Inspection) Pick the object at the screen centre")
	fmt.println("  I / K        (Inspection) Translate selected object: local Z-/Z+")
	fmt.println("  J / L        (Inspection) Translate selected object: local X-/X+")
	fmt.println("  U / O        (Inspection) Translate selected object: local Y-/Y+")
	fmt.println("  4 / 5        (Inspection) Rotate selected object: yaw-/yaw+")
	fmt.println("  6 / 7        (Inspection) Rotate selected object: pitch-/pitch+")
	fmt.println("  8 / 9        (Inspection) Rotate selected object: roll-/roll+")
	fmt.println("  ; / '        (Inspection) Decrease / increase translate+rotate step size")
	fmt.println("  0            (Inspection) Reset selected object to its original transform")
	fmt.println("  Shift+0      (Inspection) Reset ALL objects to their original transforms")
	// [PROGRESS-DEMO] Branch-only: light-gizmo/area-light/shading-mode/
	// culling/depth-test/depth-visualisation/back-face-debug/polish-pass
	// control lines removed — see Source/Main.odin's key_callback for why
	// (every one was either about a "planned, not yet done" syllabus
	// topic, or already a silent no-op under u_ObjectsOnlyMode).
	fmt.println("  F            Toggle wireframe")
	fmt.println("  H            Print this list again")
	fmt.println("  Esc          Quit")
}

// [PROGRESS-DEMO] Branch-only (progress_objects), not on main: the
// headless "--test-inspection" turret/searchlight test that used to live
// here (inspection_test_render_and_capture, Run_Inspection_Test) is
// removed on this branch along with Library/Lights, since its entire
// premise is verifying that a LIGHT tracks the turret through the
// hierarchy — out of scope for a progress check that precedes the
// illumination-model section. Restore by switching to main or deleting
// this branch; the real implementation is untouched there.
