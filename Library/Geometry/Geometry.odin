// Package Geometry — theme-agnostic procedural primitive/mesh generation.
//
// Must know nothing about the military-base theme (no "watchtower", "jeep",
// etc. in this package) — CLAUDE.md §13.1, Requirements.md §7. Consumed by
// SENTINEL-specific scene code, but importable and testable independently.
// It DOES depend on `Library/Engine` (for the GL buffer/array wrappers a
// Mesh uploads itself into) — that's still "theme-agnostic," since Engine
// itself has no scene-specific knowledge either; CLAUDE.md §13.1's
// agnosticism requirement is about the military-base theme, not about
// layering on top of Engine.
//
// Hard constraints that apply directly to this package (CLAUDE.md §2 items
// 5-8; instructor constraints, some added/updated):
//   - No precomputed/literal vertex tables, and nothing formed at compile
//     time. Every generator builds its vertices at runtime from parameters
//     using loops/formulas — never a hardcoded array of numbers.
//   - ONLY THREE direct mesh generators are allowed in this whole project:
//     Cube, Tetrahedron, and Plane (CLAUDE.md §2 item 6, instructor hard
//     constraint). There is no cylinder()/cone()/wedge() generator that
//     emits its own bespoke vertex data — every other shape (a "cylinder"
//     tower leg, a "cone" roof, a wedge ramp, a whole composite object) is
//     assembled at runtime by combining multiple Cube/Tetrahedron/Plane
//     instances via matrix transforms, using Append_Mesh below.
//   - No imported models or assets — everything is procedural, and only
//     from the three primitives above.
//   - Low-poly / faceted look: flat faces. Every generator DUPLICATES
//     vertices per face (never shares a corner vertex between two
//     differently-oriented faces) so each face gets its own constant
//     normal — required for the flat/Gouraud/Phong comparison in roadmap
//     step 7, and checked directly by Geometry_test.odin below.
//   - ONE triangle winding convention, obeyed by every generator: **CCW
//     (counter-clockwise) when viewed from outside/in front of a face =
//     front-facing**, matching the convention already established (and
//     visually verified) by the Session 1/2 smoke-test generators this
//     package replaces. A winding bug here would silently break back-face
//     culling and lighting later (CLAUDE.md §4's culling item) — see the
//     "How winding is guaranteed correct" note on append_triangle below
//     (append_quad, used by Cube, applies the same logic to a whole planar
//     face at once) for how every generator satisfies this without
//     hand-verifying each shape separately.
//
// Session 3 (roadmap step 3) design notes:
//   - Vertex holds Position + Normal only — no colour/material index yet.
//     CLAUDE.md's task explicitly left that optional ("if you think it's
//     cleaner"); added speculatively now it would just be an unused field,
//     since no material/lighting system exists until roadmap step 4. Add
//     it then, once it's clear what shape that data actually needs to be,
//     rather than guessing here.
//   - Mesh owns BOTH its CPU-side vertex/index arrays (needed so
//     Append_Mesh can read a source mesh's data to combine it into another)
//     and, once Upload is called, its GL buffer/array handles — matching
//     the task's "Mesh type holding vertices..., indices..., and GL buffer
//     handles, plus upload/draw/destroy procs" ask directly.
//   - Destroy is safe to call whether or not Upload ever ran: it tracks
//     whether Upload happened (Mesh.uploaded) and only touches GL if so.
//     This is NOT just "harmless either way" — `odin test` runs this
//     package's tests with no GLFW window and so no GL context ever
//     loaded, meaning vendor:OpenGL's function pointers are nil; an
//     unconditional gl.DeleteBuffers/DeleteVertexArrays call on an
//     un-uploaded Mesh's zero-valued handles segfaults through those nil
//     pointers rather than harmlessly no-op'ing on id 0 as GL's own spec
//     would suggest if a context WERE current. Caught by this package's
//     own tests (Geometry_test.odin never calls Upload, only Destroy) —
//     worth remembering for any future Engine-backed type that needs to be
//     usable from a plain `odin test` binary.
//   - Draw does NOT keep a persistent Engine Renderer inside Mesh, and
//     Destroy never touches a Shader. A shared Shader is normally owned
//     and deleted once by the caller (Source/Main.odin), outside any
//     Mesh — Session 2's PROGRESS.md documents a real double-free bug from
//     two Engine Renderers both owning cleanup of one shared Shader; Mesh
//     sidesteps that class of bug entirely by never owning a Shader at all.
package Geometry

import la "core:math/linalg"

import ib "../Engine/IndexBuffer"
import rd "../Engine/Renderer"
import sd "../Engine/Shader"
import va "../Engine/VertexArray"
import vb "../Engine/VertexBuffer"
import vbl "../Engine/VertexBufferLayout"

Vertex :: struct {
	Position: la.Vector3f32,
	Normal:   la.Vector3f32,
}

Mesh :: struct {
	Vertices: [dynamic]Vertex,
	Indices:  [dynamic]u32,

	vertex_buffer: vb.VertexBuffer,
	index_buffer:  ib.IndexBuffer,
	vertex_array:  va.VertexArray,
	layout:        vbl.VertexBufferLayout,
	uploaded:      bool,
}

// Empty_Mesh returns a Mesh with no vertices/indices yet — the starting
// accumulator for Append_Mesh when building a composite shape (a "cylinder"
// ring, a "cone" stack, a whole composite object). Named distinctly from
// Cube/Tetrahedron/Plane below (which are also, in a sense, "new mesh"
// constructors) to keep "start empty and build up via Append_Mesh" visually
// distinct from "generate one of the three base primitives."
Empty_Mesh :: proc() -> Mesh {
	return Mesh{}
}

// ---------------------------------------------------------------------------
// The three allowed direct generators (CLAUDE.md §2 item 6). Every other
// shape in SENTINEL is built by calling Append_Mesh in a runtime loop over
// instances of these three — see this file's header and Append_Mesh's own
// comment.
// ---------------------------------------------------------------------------

// Cube generates a box of the given full width/height/depth (not
// half-extents), centred on its own local origin. Built from a runtime loop
// over the 3 axes x the 2 signs (6 faces), each face appended as one quad
// via append_quad — never a literal corner/vertex table (CLAUDE.md §2 item
// 5). 24 vertices (4 duplicated per face, for flat per-face normals — see
// append_quad's own comment for why this uses a dedicated quad helper
// rather than two append_triangle calls per face), 12 triangles.
Cube :: proc(width, height, depth: f32) -> Mesh {
	mesh := Empty_Mesh()
	half := la.Vector3f32{width, height, depth} * 0.5

	// The 4 corners of a face are walked in this fixed (u, v) sign pattern
	// for every face — it does NOT need to already be "the right" winding
	// per face, since append_quad below auto-corrects orientation to point
	// away from the cube's own centre (its local origin). Only used as a
	// traversal order, not as literal geometry data.
	corner_signs := [4][2]f32{{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}

	for axis in 0 ..< 3 {
		u := (axis + 1) % 3
		v := (axis + 2) % 3

		for sign_bit in 0 ..< 2 {
			sign: f32 = -1 if sign_bit == 0 else 1

			corner: [4]la.Vector3f32
			for k in 0 ..< 4 {
				p: la.Vector3f32
				p[axis] = sign * half[axis]
				p[u] = corner_signs[k][0] * half[u]
				p[v] = corner_signs[k][1] * half[v]
				corner[k] = p
			}

			append_quad(&mesh, corner[0], corner[1], corner[2], corner[3], la.Vector3f32{0, 0, 0})
		}
	}

	return mesh
}

// Tetrahedron generates a regular tetrahedron of the given `size` (its 4
// corners fit within a `size`-side cube, same "full extent, not half"
// convention as Cube), centred on its own local origin. The 4 corners are a
// standard tetrahedron parametrization — 4 alternating corners of a cube —
// computed from `size` at call time, not copied-in coordinates (CLAUDE.md
// §2 item 5). Each of the 4 triangular faces omits exactly one corner; the
// 3 remaining corners are handed to append_triangle in an arbitrary order,
// which auto-corrects their winding (see append_triangle's comment) rather
// than needing that order hand-derived and hardcoded per face — deriving 4
// non-axis-aligned faces' correct winding by hand is exactly the kind of
// thing this auto-orientation exists to avoid getting silently wrong.
// 12 vertices (4 faces x 3, all duplicated — a tetrahedron shares no two
// faces' vertices under flat shading), 4 triangles.
Tetrahedron :: proc(size: f32) -> Mesh {
	mesh := Empty_Mesh()
	s := size * 0.5

	corner := [4]la.Vector3f32 {
		la.Vector3f32{1, 1, 1} * s,
		la.Vector3f32{1, -1, -1} * s,
		la.Vector3f32{-1, 1, -1} * s,
		la.Vector3f32{-1, -1, 1} * s,
	}

	// Each row lists the 3 corners OTHER than the one it's "opposite" to —
	// i.e. row i is the face not touching corner[i]. Order within a row is
	// arbitrary; see the proc comment above for why.
	face := [4][3]int{{1, 2, 3}, {0, 2, 3}, {0, 1, 3}, {0, 1, 2}}

	for f in face {
		append_triangle(&mesh, corner[f[0]], corner[f[1]], corner[f[2]], la.Vector3f32{0, 0, 0})
	}

	return mesh
}

// Plane generates a single flat width x height quad in the LOCAL XY plane
// (z = 0), facing +Z, centred on its own local origin — the "or another
// basic 2D polygon" option CLAUDE.md §2 item 6 allows alongside Cube and
// Tetrahedron. Composing code rotates/translates it via Append_Mesh to
// stand it up as a wall/fence panel, lay it flat as a floor tile, etc.
//
// UNLIKE Cube/Tetrahedron, Plane does NOT use append_triangle's
// auto-orientation: a flat, zero-volume quad's own centroid sits exactly ON
// its own plane, so "does the normal point away from local origin" is
// undefined (a dot product of exactly/nearly zero) rather than a reliable
// outward/inward test — that test only works for a convex volume whose
// local origin is strictly inside it (true for Cube and Tetrahedron, false
// for a flat Plane). The +Z-facing, CCW-from-+Z winding below is instead a
// fixed, directly-chosen convention, verified in Geometry_test.odin the
// same way every other generator's winding is checked (geometric normal
// from the triangle's own winding must match the stored normal) — just
// without needing append_triangle's orientation-fixing step to get there.
Plane :: proc(width, height: f32) -> Mesh {
	mesh := Empty_Mesh()
	half_width := width * 0.5
	half_height := height * 0.5
	normal := la.Vector3f32{0, 0, 1}

	corner := [4]la.Vector3f32 {
		{-half_width, -half_height, 0},
		{half_width, -half_height, 0},
		{half_width, half_height, 0},
		{-half_width, half_height, 0},
	}

	for c in corner {
		append(&mesh.Vertices, Vertex{Position = c, Normal = normal})
	}
	append(&mesh.Indices, u32(0), 1, 2, 0, 2, 3)

	return mesh
}

// append_triangle appends one triangle (a, b, c) to `mesh`, computing its
// face normal from (a, b, c)'s own winding via cross(b - a, c - a).
//
// How winding is guaranteed correct without hand-deriving it per shape: if
// that raw normal points TOWARD `inward_reference` instead of away from it,
// b and c are swapped (reversing the triangle's winding) and the normal is
// flipped to match — so the FINAL stored normal always points away from
// `inward_reference`, and because it's derived from whichever winding
// ended up stored, the triangle's winding and its stored normal can never
// disagree (Geometry_test.odin checks exactly this, per generator).
// `inward_reference` only needs to be ANY point known to be on the interior
// side of the face — for Cube/Tetrahedron, both centred on their own local
// origin, that's simply {0, 0, 0}. This only works for a convex shape whose
// `inward_reference` is strictly inside every face's supporting plane; see
// Plane's own comment for the one primitive here that can't use it.
@(private = "file")
append_triangle :: proc(mesh: ^Mesh, a, b, c: la.Vector3f32, inward_reference: la.Vector3f32) {
	normal := la.normalize(la.cross(b - a, c - a))
	centroid := (a + b + c) / 3

	v0, v1, v2 := a, b, c
	if la.dot(normal, centroid - inward_reference) < 0 {
		v1, v2 = c, b
		normal = -normal
	}

	base_index := u32(len(mesh.Vertices))
	append(&mesh.Vertices, Vertex{Position = v0, Normal = normal}, Vertex{Position = v1, Normal = normal}, Vertex{Position = v2, Normal = normal})
	append(&mesh.Indices, base_index + 0, base_index + 1, base_index + 2)
}

// append_quad is append_triangle's counterpart for a PLANAR 4-cornered face
// (Cube's only use of the two): computes and auto-orients ONE normal for
// the whole face (same orientation logic as append_triangle, via
// `inward_reference`), then appends exactly 4 vertices sharing that single
// normal and 2 triangles' worth of indices into them.
//
// Deliberately NOT built as two append_triangle calls on (a,b,c) and
// (a,c,d): that would append 6 vertices per face (3 + 3, no sharing)
// instead of 4, since append_triangle always appends fresh vertices with
// no notion of "this corner is shared with the other triangle of the same
// face" — doubling this shape's vertex count for no benefit (both
// triangles of a truly planar quad always agree on their orientation
// anyway, so nothing would be gained by deciding it twice). This is why
// Cube ends up with exactly 24 vertices (6 faces x 4), not 36.
@(private = "file")
append_quad :: proc(mesh: ^Mesh, a, b, c, d: la.Vector3f32, inward_reference: la.Vector3f32) {
	normal := la.normalize(la.cross(b - a, c - a))
	centroid := (a + b + c + d) * 0.25

	base_index := u32(len(mesh.Vertices))
	append(&mesh.Vertices, Vertex{Position = a, Normal = normal}, Vertex{Position = b, Normal = normal}, Vertex{Position = c, Normal = normal}, Vertex{Position = d, Normal = normal})

	if la.dot(normal, centroid - inward_reference) < 0 {
		// The computed normal pointed inward; rather than re-deriving it,
		// flip every vertex's stored normal and reverse each triangle's
		// index order to match — the vertex POSITIONS above are already
		// appended and don't need to change.
		mesh.Vertices[base_index + 0].Normal = -normal
		mesh.Vertices[base_index + 1].Normal = -normal
		mesh.Vertices[base_index + 2].Normal = -normal
		mesh.Vertices[base_index + 3].Normal = -normal
		append(&mesh.Indices, base_index + 0, base_index + 2, base_index + 1)
		append(&mesh.Indices, base_index + 0, base_index + 3, base_index + 2)
	} else {
		append(&mesh.Indices, base_index + 0, base_index + 1, base_index + 2)
		append(&mesh.Indices, base_index + 0, base_index + 2, base_index + 3)
	}
}

// Append_Mesh is the ONLY way composite or curved-looking shapes come into
// existence in this project (CLAUDE.md §2 item 6): it copies every
// vertex/triangle of `src` into `dst`, transforming each vertex's position
// by `transform` and its normal by `transform`'s normal matrix (so normals
// stay correct even under a non-uniform scale, e.g. a tapered cone
// instance — CLAUDE.md §5.3's normal-matrix requirement, needed here
// already rather than only once real scene objects exist). Callers loop at
// runtime, computing a fresh `transform` per instance (a rotation matrix
// per ring segment for a "cylinder," a taper + rotation for a "cone", etc.)
// and call this once per instance — never a stored/cached list of
// positions.
//
// `la.matrix4_inverse_transpose` (transpose(inverse(m))) is the standard
// normal-matrix formula; computing it on the full 4x4 rather than a
// separately-extracted 3x3 is equivalent for the linear (rotation/scale)
// part that normals care about, since a translation only affects the row
// and column matrix3_from_matrix4 below discards anyway.
Append_Mesh :: proc(dst: ^Mesh, src: Mesh, transform: la.Matrix4f32) {
	normal_matrix := la.matrix3_from_matrix4(la.matrix4_inverse_transpose(transform))
	base_index := u32(len(dst.Vertices))

	for vertex in src.Vertices {
		world_position4 := la.mul(transform, la.Vector4f32{vertex.Position.x, vertex.Position.y, vertex.Position.z, 1})
		world_position := la.Vector3f32{world_position4.x, world_position4.y, world_position4.z}
		world_normal := la.normalize(la.mul(normal_matrix, vertex.Normal))
		append(&dst.Vertices, Vertex{Position = world_position, Normal = world_normal})
	}

	for index in src.Indices {
		append(&dst.Indices, base_index + index)
	}
}

// Smooth_Cylinder_Normals overwrites every vertex's stored NORMAL with the
// analytically correct outward-RADIAL direction for a cylinder around the
// given axis, replacing whatever flat per-face normal that vertex had
// before (roadmap step 7, CLAUDE.md §6.1's flat/Gouraud/Phong comparison —
// Gouraud and Phong only look different from Flat where normals actually
// VARY across a face, which never happens on this project's faceted
// geometry unless something does this).
//
// This is a per-vertex FORMULA (the component of `vertex.Position -
// axis_point` perpendicular to `axis_direction`), not a neighbour-
// averaging/mesh-welding pass — CLAUDE.md §2 item 5's "no precomputed
// data" applies to a smoothing pass exactly as much as to geometry itself,
// and a formula sidesteps needing to match up duplicated vertices at
// segment seams: this project's ring segments (append_ring_x/y in
// Library/Scene/Objects.odin) deliberately OVERLAP each other slightly
// (their own tangential-width formula has a >1 overlap factor), so
// adjacent segments' "shared" edges don't actually sit at identical
// positions the way a welding pass would need.
//
// Call this on a ring/cylinder-shaped mesh's own LOCAL vertex data —
// meaning BEFORE it's Append_Mesh'd into a larger composite, while
// `axis_point`/`axis_direction` are still given in that same local space
// (append_ring_x/y's own axis: point at (x_offset,0,0) or (0,y_offset,0),
// direction (1,0,0) or (0,1,0) respectively, matching whichever axis that
// ring sweeps around).
Smooth_Cylinder_Normals :: proc(mesh: ^Mesh, axis_point: la.Vector3f32, axis_direction: la.Vector3f32) {
	axis := la.normalize(axis_direction)
	for &vertex in mesh.Vertices {
		offset := vertex.Position - axis_point
		radial := offset - la.dot(offset, axis) * axis
		// A vertex sitting exactly ON the axis has no well-defined radial
		// direction (the formula degenerates to the zero vector) — leave
		// its existing flat normal alone rather than normalizing noise.
		// None of this project's own ring segments currently have a vertex
		// there, but a future one might.
		if la.length(radial) > 1e-5 {
			vertex.Normal = la.normalize(radial)
		}
	}
}

// Upload creates this Mesh's GL vertex/index buffers and vertex array from
// its current CPU-side Vertices/Indices (via Library/Engine), ready for
// Draw. Call once, after all Append_Mesh calls that build this Mesh are
// done — Upload does not re-read the CPU arrays afterward, so further
// mutation after Upload would not be reflected on the GPU.
Upload :: proc(mesh: ^Mesh) {
	mesh.vertex_buffer = vb.New(mesh.Vertices[:])
	mesh.index_buffer = ib.New(mesh.Indices[:])

	mesh.layout = vbl.New()
	vbl.Push(&mesh.layout, f32, 3, false) // a_Position: vec3
	vbl.Push(&mesh.layout, f32, 3, false) // a_Normal:   vec3 (location 1; Shaders/Scene.glsl doesn't read it yet — see roadmap step 4)

	mesh.vertex_array = va.New()
	va.AddBuffer(&mesh.vertex_array, &mesh.vertex_buffer, &mesh.layout)

	mesh.uploaded = true
}

// Draw issues one draw call for this Mesh through the given Shader (already
// bound/uniform-uploaded by the caller for this frame). Builds a transient
// Library/Engine/Renderer rather than storing one on Mesh, and never calls
// Renderer.Delete on it — Mesh never owns or deletes a Shader (see this
// file's header for why: a shared Shader must be deleted exactly once, by
// whoever created it, not by every Mesh drawn with it).
Draw :: proc(mesh: ^Mesh, shader: ^sd.Shader) {
	renderer := rd.New(&mesh.vertex_array, &mesh.index_buffer, shader)
	rd.Draw(&renderer)
}

// Destroy frees this Mesh's CPU-side arrays and, if Upload was ever called,
// its GL buffers/array too. Safe to call on a Mesh that was only ever used
// as an Append_Mesh source and never uploaded — see this file's header for
// why that check (mesh.uploaded) is load-bearing, not defensive filler.
Destroy :: proc(mesh: ^Mesh) {
	delete(mesh.Vertices)
	delete(mesh.Indices)

	if mesh.uploaded {
		vb.Delete(&mesh.vertex_buffer)
		vbl.Delete(&mesh.layout)
		va.Delete(&mesh.vertex_array)
		ib.Delete(&mesh.index_buffer)
	}
}
