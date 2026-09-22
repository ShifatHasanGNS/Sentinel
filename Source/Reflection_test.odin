// Reflection_test.odin — confirms Build_Proxies re-derives a proxy's world
// position from the OWNING node's CURRENT transform every call, not a
// value captured once, matching every other per-frame recompute in this
// project (CLAUDE.md §2 item 10). This is the piece of this session's task
// ("the reflection must update when the instructor moves the reflected
// objects") that has a clean analytic answer, so it gets a real test
// instead of an eyeballed screenshot comparison — same reasoning Source/
// Inspection_test.odin's own header comment gives for picking math.
//
// Deliberately builds its own minimal Hierarchy with `scenepkg.Add_Node`
// (Library/Scene/Transform_test.odin's own pattern) rather than calling
// Library/Scene/Objects.Build_Scene: that proc uploads every mesh to the
// GPU (Geometry.Upload), which needs a real OpenGL context and segfaults
// under a headless `odin test` runner with none bound. Build_Proxy_Defs's
// own node-name resolution against the REAL scene is exercised for free
// every time the program actually starts (it panics loudly on any drift,
// Source/Reflection.odin's own comment) — what's missing a check is only
// Build_Proxies' per-frame math, which doesn't need real geometry at all.
package main

import la "core:math/linalg"
import "core:testing"

import geo "../Library/Geometry"
import scenepkg "../Library/Scene"

// empty_test_mesh is a zero-value, never-uploaded Mesh — fine here since
// this test never draws anything, only reads world-matrix math, the same
// "no GPU needed for hierarchy math" reasoning Library/Scene/Transform_
// test.odin's own geo_empty_mesh() helper already relies on.
empty_test_mesh :: proc() -> geo.Mesh {
	return geo.Mesh{}
}

@(test)
test_build_proxies_tracks_a_moved_node :: proc(t: ^testing.T) {
	scene := scenepkg.Hierarchy{}
	defer scenepkg.Destroy(&scene)

	local := scenepkg.Identity_Transform()
	local.Position = {1, 2, 3}
	node_index := scenepkg.Add_Node(&scene, "Test Node", scenepkg.NO_PARENT, local, empty_test_mesh(), scenepkg.Default_Material(la.Vector3f32{1, 1, 1}))

	defs := []Proxy_Def{
		{node_name = "Test Node", node_index = node_index, type = .Box, local_offset = {0, 0, 0}, half_extents = {1, 1, 1}, color = {1, 1, 1}},
	}

	before_matrices := scenepkg.Compute_World_Matrices(&scene)
	before_proxies := Build_Proxies(defs[:], before_matrices[:])
	before_center := before_proxies[0].Center
	delete(before_matrices)
	delete(before_proxies)

	move := la.Vector3f32{5, 0, -3}
	scene.Nodes[node_index].Local.Position += move

	after_matrices := scenepkg.Compute_World_Matrices(&scene)
	after_proxies := Build_Proxies(defs[:], after_matrices[:])
	after_center := after_proxies[0].Center
	delete(after_matrices)
	delete(after_proxies)

	actual_shift := after_center - before_center
	testing.expectf(
		t,
		la.length(actual_shift-move) <= 1e-4,
		"expected the proxy's Center to shift by exactly the node's own translation %v, got a shift of %v",
		move,
		actual_shift,
	)
}
