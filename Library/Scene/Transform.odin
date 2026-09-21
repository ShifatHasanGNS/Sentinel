// Transform.odin — the hand-rolled hierarchy system (CLAUDE.md §5.3, §9
// roadmap step 3 part 2 / groundwork for step 5; Prompts.md Session 4). No
// scene-graph library (CLAUDE.md §2 item 4) — a `Hierarchy` here is just a
// flat, growable array of `Node`s plus integer parent indices, not a
// third-party dependency.
//
// Design: FLAT ARRAY + INTEGER PARENT INDEX, not a tree of pointers/child
// lists. Odin's `[dynamic]Node` can reallocate on `append`, which would
// invalidate any pointer a node held to its parent or children; an index
// into the same array stays valid across reallocation. This also removes
// any need for each node to store a child list at all: `Compute_World_
// Matrices` below fills one array in a SINGLE top-down pass (CLAUDE.md
// §5.3's "world matrix = parent world x local, computed top-down once per
// frame, cache per frame" requirement), relying on the invariant that a
// parent is always added (and so always has a lower index) before its
// children — true by construction, since `Add_Node` returns the new
// node's index for the caller to use as a `parent` argument in later
// calls, and asserted defensively in `Compute_World_Matrices` in case that
// invariant is ever violated.
//
// Rotation representation: `Transform.Rotation` is Euler angles in radians
// (X = pitch, Y = yaw, Z = roll), composed as yaw (outermost) * pitch *
// roll (innermost) in `Local_Matrix` — the same yaw-outer/pitch-inner
// convention `Library/Camera/Camera.odin`'s `Forward` already uses, so a
// node's forward-facing rotation behaves the same way the camera's does.
// Chosen over axis-angle/quaternions because every rotation this project
// actually needs (a floodlight head sweeping, a turret spinning, a radar
// dish turning, a wedge roof's fixed tilt) is single- or two-axis and
// reads naturally as Euler angles; a full quaternion slerp system isn't
// needed anywhere in SENTINEL's design (Plan.md §4/§7) and would be
// solving a problem this project doesn't have.
package Scene

import la "core:math/linalg"

import geo "../Geometry"

// NO_PARENT marks a root node (no parent) in `Node.Parent`, and doubles as
// `Find_Node`'s "not found" return value — both mean the same thing, "no
// valid node index."
NO_PARENT :: -1

Transform :: struct {
	Position: la.Vector3f32,
	Rotation: la.Vector3f32, // radians: X = pitch, Y = yaw, Z = roll
	Scale:    la.Vector3f32,
}

Identity_Transform :: proc() -> Transform {
	return Transform{Position = {0, 0, 0}, Rotation = {0, 0, 0}, Scale = {1, 1, 1}}
}

// Local_Matrix builds this Transform's local matrix as translate * rotate *
// scale (CLAUDE.md §5.3), freshly every call — never cached as if it were
// static (CLAUDE.md §2 item 10's "recomputed as needed" spirit applies to
// the hierarchy just as much as to lights).
Local_Matrix :: proc(t: Transform) -> la.Matrix4f32 {
	translate := la.matrix4_translate(t.Position)

	yaw := la.matrix4_rotate(t.Rotation.y, la.Vector3f32{0, 1, 0})
	pitch := la.matrix4_rotate(t.Rotation.x, la.Vector3f32{1, 0, 0})
	roll := la.matrix4_rotate(t.Rotation.z, la.Vector3f32{0, 0, 1})
	rotate := la.mul(yaw, la.mul(pitch, roll))

	scale := la.matrix4_scale(t.Scale)

	return la.mul(translate, la.mul(rotate, scale))
}

// Node is one entry in a Hierarchy: a name (stable, so Find_Node and later
// sessions' Light-parenting/Inspection-Mode-selection can address it),
// a parent index, a local Transform, and what it draws — a Mesh (may be
// empty/undrawn, see Draw_Nodes' own check) plus a flat unlit Color
// (roadmap step 3 is explicitly "static; unlit," CLAUDE.md §9 — real
// material/lighting arrives at roadmap step 4).
Node :: struct {
	Name:   string,
	Parent: int,
	Local:  Transform,
	Mesh:   geo.Mesh,
	Color:  la.Vector3f32,
}

Hierarchy :: struct {
	Nodes: [dynamic]Node,
}

Destroy :: proc(h: ^Hierarchy) {
	for &node in h.Nodes {
		geo.Destroy(&node.Mesh)
	}
	delete(h.Nodes)
}

// Add_Node appends a new Node and returns its index, so the caller can use
// that index as `parent` for later children — this return value is what
// makes the "parent always added before its children" invariant natural
// to maintain rather than something a caller has to track separately.
Add_Node :: proc(h: ^Hierarchy, name: string, parent: int, local: Transform, mesh: geo.Mesh, color: la.Vector3f32) -> int {
	assert(parent == NO_PARENT || (parent >= 0 && parent < len(h.Nodes)), "Add_Node: parent index out of range")
	append(&h.Nodes, Node{Name = name, Parent = parent, Local = local, Mesh = mesh, Color = color})
	return len(h.Nodes) - 1
}

// Compute_World_Matrices computes every node's world matrix in ONE
// top-down pass (parent world x local, CLAUDE.md §5.3), returning them
// indexed the same as `h.Nodes`. Callers should compute this once per
// frame and reuse it for every draw call / light-position derivation that
// frame (CLAUDE.md §5.3's caching requirement) rather than recomputing a
// node's world matrix redundantly — but still every frame, never once at
// load time (CLAUDE.md §2 item 10). Caller owns the returned array
// (`delete` it when done).
Compute_World_Matrices :: proc(h: ^Hierarchy) -> [dynamic]la.Matrix4f32 {
	world := make([dynamic]la.Matrix4f32, 0, len(h.Nodes))

	for node, i in h.Nodes {
		local := Local_Matrix(node.Local)
		if node.Parent == NO_PARENT {
			append(&world, local)
		} else {
			assert(node.Parent < i, "Compute_World_Matrices: a parent must be added before its children")
			append(&world, la.mul(world[node.Parent], local))
		}
	}

	return world
}

// World_Position extracts a world-space POINT (the node's own local
// origin, transformed to world space) from a world matrix — transforming
// (0,0,0,1) rather than reading a matrix column directly, so this doesn't
// depend on knowing linalg's exact column-major element layout.
World_Position :: proc(world_matrix: la.Matrix4f32) -> la.Vector3f32 {
	p := la.mul(world_matrix, la.Vector4f32{0, 0, 0, 1})
	return la.Vector3f32{p.x, p.y, p.z}
}

// World_Direction transforms a LOCAL direction (e.g. a light's local aim
// vector) into world space, ignoring translation (w = 0) — the "transform
// a local direction vector with the correct matrix, ignoring translation"
// helper CLAUDE.md §5.3/Prompts.md Session 4 calls for, needed once
// Lights.odin (roadmap step 5) derives a spot/directional light's current
// world-space direction from its parent node's world matrix.
World_Direction :: proc(world_matrix: la.Matrix4f32, local_direction: la.Vector3f32) -> la.Vector3f32 {
	d := la.mul(world_matrix, la.Vector4f32{local_direction.x, local_direction.y, local_direction.z, 0})
	return la.Vector3f32{d.x, d.y, d.z}
}

// Normal_Matrix is the inverse-transpose of a world matrix's upper-left 3x3
// (CLAUDE.md §5.3's "normals must be transformed with the inverse-
// transpose... so lighting stays right under non-uniform scale"), the same
// technique `Library/Geometry.Append_Mesh` already uses for combining
// meshes — needed here too once real per-fragment lighting (roadmap step
// 4) uploads a per-object normal matrix uniform.
Normal_Matrix :: proc(world_matrix: la.Matrix4f32) -> la.Matrix3f32 {
	return la.matrix3_from_matrix4(la.matrix4_inverse_transpose(world_matrix))
}

// Find_Node looks up a node by its stable Name (see Node's own comment for
// why names matter), returning NO_PARENT (-1) if none matches — reused as
// the "not found" sentinel since it already means "no valid node index."
// Linear scan: fine at this project's node count (well under 100), not
// worth a map for.
Find_Node :: proc(h: ^Hierarchy, name: string) -> int {
	for node, i in h.Nodes {
		if node.Name == name do return i
	}
	return NO_PARENT
}
