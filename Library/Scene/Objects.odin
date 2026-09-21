// Objects.odin — builds the 9 SENTINEL scene objects (CLAUDE.md §5.1, §12,
// §14; Requirements.md §3; Plan.md §2). Roadmap step 3, parts 3-4
// (Prompts.md Sessions 5-6), built on top of Transform.odin's Hierarchy
// and `Library/Geometry`'s Cube/Tetrahedron/Plane + Append_Mesh.
//
// Every "cylinder," "wedge," "cone," or "dish" below is a runtime
// composition of Cube/Tetrahedron/Plane via matrix transforms (CLAUDE.md
// §2 item 6) — there is no dedicated generator for any of them.
//
// NODE STRUCTURE: most objects are a single root Node whose Mesh is a
// composite built (in the node's own LOCAL space) from many primitive
// instances via Append_Mesh, then positioned as one rigid unit by the
// node's own world transform. A SEPARATE child Node is only added where
// CLAUDE.md §5.3 or a later roadmap step actually needs one: independent
// articulation (the watchtower's floodlight head, the radar dish, the
// tank's turret/barrel) or per-frame world-space geometry queries a later
// session reads directly (the tank's periscope and the jeep's windshield
// for roadmap step 11's ray-traced reflection, CLAUDE.md §6.2; the
// barracks windows for roadmap step 6's area-light sampling, CLAUDE.md
// §6.3). The jeep's two headlights ALSO get their own child nodes — not
// because they'll articulate, but because Prompts.md's Session 5 spec asks
// for them by name as "child nodes" explicitly, unlike the tank's hull
// headlights and the gun emplacement's work light (their own Session 6
// spec says only "on the hull"/"beside it," no child-node requirement),
// which stay baked into their parent's composite mesh — Session 8 can give
// those a constant local-space offset from the existing parent node
// directly; inventing an empty marker node for every future light would be
// scope creep this session's actual job (geometry) doesn't need.
//
// LAYOUT: each object's root position is a small NAMED CONSTANT (one per
// object), not a runtime formula — deliberately. CLAUDE.md §2 item 5's
// "never hardcode... object positions" targets REPEATED/patterned
// placement that has an obvious underlying formula (fence posts around a
// loop, a light-sweep angle, a camera path) — exactly what every object
// below still generates procedurally internally. A one-off hand-placed
// position for a SINGLE, uniquely-named object (there is exactly one
// watchtower) is the same kind of "small parameter... that feeds generator
// code" this project already treats as allowed elsewhere (CAMERA_START_EYE
// in Source/Main.odin, RING_RADIUS, etc.) — there is no meaningful formula
// relating "where the watchtower goes" to "where the jeep goes," so
// forcing one would be contrived, not more procedural. What must NOT be a
// literal table, and isn't anywhere below, is the geometry WITHIN an
// object or any REPEATED element's placement (fence posts, crate stack,
// sandbag rows, tower legs, wheels) — those all come from runtime loops.
//
// MATERIAL: each node gets a `Scene.Material` (base colour, specular
// strength, shininess, emission colour — Prompts.md's Session 5 spec asks
// for exactly these four), shaded in `Shaders/Scene.glsl` against ONE
// hardcoded placeholder directional light (see that file's own header for
// why this is deliberately NOT roadmap step 4's real multi-light system).
// Most nodes use `Default_Material` (a plain, non-emissive colour); a few
// — window/windshield/periscope glass, the floodlight housing, the radar
// beacon — get a nonzero EmissionColor so they read as "lit" even under
// this placeholder shading, previewing their eventual role as light
// sources/light-adjacent surfaces. Not a hardcoded "data table" in the
// CLAUDE.md §2 item 5 sense; it's a handful of parameters per node, same
// category as a mesh's dimensions.
//
// Verification: Source/Main.odin prints the built object/node count at
// startup (>= 6 required, this plan targets 9 top-level objects) and
// captures the base from two camera angles to confirm no intersecting or
// floating geometry.
package Scene

import "core:math"
import la "core:math/linalg"

import geo "../Geometry"

// ---------------------------------------------------------------------------
// Layout (see header for why these are named constants, not a formula).
// ---------------------------------------------------------------------------

FENCE_HALF_WIDTH :: 14.0 // X
FENCE_HALF_DEPTH :: 14.0 // Z
FENCE_GATE_HALF_WIDTH :: 2.5 // gap left in the +Z side

WATCHTOWER_POSITION :: la.Vector3f32{-11, 0, -11}
BARRACKS_POSITION :: la.Vector3f32{-10, 0, 2}
BUNKER_POSITION :: la.Vector3f32{9, 0, -10}
GUN_EMPLACEMENT_POSITION :: la.Vector3f32{9, 0, -3}
RADAR_POSITION :: la.Vector3f32{1, 0, -10}
CRATE_STACK_POSITION :: la.Vector3f32{-9, 0, 9}
JEEP_POSITION :: la.Vector3f32{4, 0, 9}
TANK_POSITION :: la.Vector3f32{-3, 0, 10}

// ---------------------------------------------------------------------------
// Colour + material palette. Base colours stay separate named constants
// (tunable independently of the material properties built from them just
// below) — same pattern as any other small parameter feeding generator
// code in this project.
// ---------------------------------------------------------------------------

COLOR_TOWER :: la.Vector3f32{0.55, 0.58, 0.62}
COLOR_FLOODLIGHT :: la.Vector3f32{0.85, 0.85, 0.75}
COLOR_FENCE :: la.Vector3f32{0.42, 0.38, 0.28}
COLOR_GATE :: la.Vector3f32{0.35, 0.32, 0.24}
COLOR_JEEP :: la.Vector3f32{0.33, 0.40, 0.24}
COLOR_GLASS :: la.Vector3f32{0.55, 0.75, 0.80}
COLOR_SANDBAG :: la.Vector3f32{0.62, 0.55, 0.38}
COLOR_RADAR_MAST :: la.Vector3f32{0.5, 0.5, 0.5}
COLOR_RADAR_DISH :: la.Vector3f32{0.75, 0.75, 0.7}
COLOR_BEACON :: la.Vector3f32{0.85, 0.2, 0.15}
COLOR_BARRACKS :: la.Vector3f32{0.45, 0.32, 0.22}
COLOR_CRATE :: la.Vector3f32{0.55, 0.45, 0.18}
COLOR_TANK :: la.Vector3f32{0.28, 0.32, 0.22}
COLOR_GUN :: la.Vector3f32{0.2, 0.2, 0.2}

// Emissive presets for the parts that should read as "lit" even under
// Shaders/Scene.glsl's placeholder single-light shading — a preview of
// their eventual role once real lights exist (roadmap step 5), not real
// light emission itself (CLAUDE.md §9 roadmap step 3 is still "unlit" in
// the sense that nothing here casts light on anything else).
MATERIAL_GLASS :: Material{BaseColor = COLOR_GLASS, SpecularStrength = 0.85, Shininess = 64, EmissionColor = {0.12, 0.28, 0.32}}
MATERIAL_FLOODLIGHT :: Material{BaseColor = COLOR_FLOODLIGHT, SpecularStrength = 0.5, Shininess = 24, EmissionColor = {0.45, 0.45, 0.38}}
MATERIAL_BEACON :: Material{BaseColor = COLOR_BEACON, SpecularStrength = 0.4, Shininess = 20, EmissionColor = {0.7, 0.12, 0.08}}

// A separate material from MATERIAL_GLASS (not a reuse) — the jeep
// windshield/tank periscope are meant to read as cool, clear GLASS (and
// are ray-trace candidates, CLAUDE.md §6.2), while a barracks window is
// meant to read as a warm, lit INTERIOR glowing out into the night
// (roadmap step 6, CLAUDE.md §6.3) — different colour language for a
// different purpose, even though both are just an emissive Plane.
COLOR_WINDOW_GLOW :: la.Vector3f32{0.95, 0.75, 0.45}
MATERIAL_BARRACKS_WINDOW :: Material{BaseColor = COLOR_WINDOW_GLOW, SpecularStrength = 0.2, Shininess = 12, EmissionColor = {0.55, 0.4, 0.18}}

// ---------------------------------------------------------------------------
// Build_Scene is the single entry point Source/Main.odin calls: builds all
// 9 objects into one shared Hierarchy and returns it, ready for
// Compute_World_Matrices + drawing.
// ---------------------------------------------------------------------------

Build_Scene :: proc() -> Hierarchy {
	h := Hierarchy{}

	build_watchtower(&h)
	build_perimeter_fence(&h)
	build_jeep(&h)
	build_bunker(&h)
	build_radar(&h)
	build_barracks(&h)
	build_crate_stack(&h)
	build_tank(&h)
	build_gun_emplacement(&h)

	return h
}

// ---------------------------------------------------------------------------
// Shared composition helpers, reused by several objects below.
// ---------------------------------------------------------------------------

// append_ring_y appends `count` instances of `segment` swept around a
// circle of `radius` in the local XZ plane (rotation about Y) — the same
// "N box instances around a ring, per-segment rotation matrix" technique
// CLAUDE.md §2 item 6 names directly, generalized here for reuse across
// every Y-axis ring below (radar dish, sandbag rings, tower railing).
// Composition order (rotate * translate, not translate * rotate) is
// load-bearing — see PROGRESS.md's Session 3 write-up for the bug this
// order avoids repeating. `y_offset` lets a caller stack several rings at
// different heights (a tapering stack) without a second transform.
append_ring_y :: proc(dst: ^geo.Mesh, segment: geo.Mesh, count: int, radius, y_offset: f32) {
	for i in 0 ..< count {
		angle := f32(i) * (2 * math.PI / f32(count))
		transform := la.mul(la.matrix4_rotate(angle, la.Vector3f32{0, 1, 0}), la.matrix4_translate(la.Vector3f32{radius, y_offset, 0}))
		geo.Append_Mesh(dst, segment, transform)
	}
}

// append_ring_x is append_ring_y's counterpart for a ring swept about the
// X axis (a wheel's rolling axis is horizontal, so its rim lies in the
// local YZ plane) — used for the jeep's and tank's wheels.
append_ring_x :: proc(dst: ^geo.Mesh, segment: geo.Mesh, count: int, radius, x_offset: f32) {
	for i in 0 ..< count {
		angle := f32(i) * (2 * math.PI / f32(count))
		transform := la.mul(la.matrix4_rotate(angle, la.Vector3f32{1, 0, 0}), la.matrix4_translate(la.Vector3f32{x_offset, radius, 0}))
		geo.Append_Mesh(dst, segment, transform)
	}
}

// append_translated is the trivial Append_Mesh case (no rotation), pulled
// out only so the many straight "place this box here" call sites below
// read as one line instead of three.
append_translated :: proc(dst: ^geo.Mesh, segment: geo.Mesh, position: la.Vector3f32) {
	geo.Append_Mesh(dst, segment, la.matrix4_translate(position))
}

// ---------------------------------------------------------------------------
// 1. Watchtower — tower base (4 legs, platform, railing, roof) plus a
// child "floodlight head" node that will rotate independently in Patrol
// Mode (roadmap step 9) and carry 2 spot lights (roadmap step 5).
// ---------------------------------------------------------------------------

// Half-distance between opposite legs, on BOTH X and Z (each leg sits at
// (+-TOWER_LEG_SPAN, +-TOWER_LEG_SPAN)). Must stay less than
// TOWER_PLATFORM_SIZE*0.5 (below) on this same per-axis basis — the
// platform is an axis-aligned SQUARE footprint, [-half,half] on each axis
// independently, not a circle, so what matters is TOWER_LEG_SPAN vs. the
// platform's half-WIDTH, not some diagonal/radial distance. An earlier
// version of this file set this to 2.2 against a platform half-size of
// 1.5 — outside the platform's footprint on both axes, so none of the 4
// legs were actually underneath it; the platform read as floating,
// untouched by its own supports (confirmed by the user directly, and by
// the numbers: 2.2 > 1.5). 1.2 keeps every leg comfortably inside the
// platform's half-size (1.5), even counting the leg's own half-thickness
// (TOWER_LEG_THICKNESS*0.5 = 0.11, so the leg's outer face reaches 1.31),
// leaving a small natural overhang the way a real lookout tower's deck
// overhangs its corner posts.
TOWER_LEG_SPAN :: 1.2
TOWER_HEIGHT :: 5.0
TOWER_LEG_THICKNESS :: 0.22
TOWER_PLATFORM_SIZE :: 3.0
TOWER_PLATFORM_THICKNESS :: 0.3
TOWER_RAILING_POST_COUNT :: 10
TOWER_RAILING_HEIGHT :: 0.6
TOWER_ROOF_SIZE :: 3.4
TOWER_ROOF_HEIGHT :: 1.6

build_watchtower :: proc(h: ^Hierarchy) {
	root := geo.Empty_Mesh()

	leg := geo.Cube(TOWER_LEG_THICKNESS, TOWER_HEIGHT, TOWER_LEG_THICKNESS)
	defer geo.Destroy(&leg)
	// 4 legs from a runtime loop over the 2-bit sign combinations of a
	// square footprint — never a literal 4-corner table.
	for corner in 0 ..< 4 {
		sign_x: f32 = -1 if corner & 1 == 0 else 1
		sign_z: f32 = -1 if corner & 2 == 0 else 1
		append_translated(&root, leg, la.Vector3f32{sign_x * TOWER_LEG_SPAN, TOWER_HEIGHT * 0.5, sign_z * TOWER_LEG_SPAN})
	}

	platform := geo.Cube(TOWER_PLATFORM_SIZE, TOWER_PLATFORM_THICKNESS, TOWER_PLATFORM_SIZE)
	defer geo.Destroy(&platform)
	append_translated(&root, platform, la.Vector3f32{0, TOWER_HEIGHT, 0})

	railing_post := geo.Cube(0.08, TOWER_RAILING_HEIGHT, 0.08)
	defer geo.Destroy(&railing_post)
	append_ring_y(&root, railing_post, TOWER_RAILING_POST_COUNT, TOWER_PLATFORM_SIZE * 0.5, TOWER_HEIGHT+TOWER_PLATFORM_THICKNESS*0.5+TOWER_RAILING_HEIGHT*0.5)

	// Roof: 4 identical slabs, each pitched inward and swept 90 degrees
	// apart around Y — a proper 4-sided (square) pyramid cap. NOT a single
	// non-uniformly-scaled Tetrahedron (an earlier version of this file
	// used one): a regular tetrahedron's 4 corners split 2-high/2-low, so
	// flattening it on Y gives a RIDGE (two high corners joined by an
	// edge), not a single apex — viewed end-on along that hidden ridge
	// diagonal it coincidentally looked like a clean point, but from any
	// other angle (e.g. straight down one of the tower's sides) it read as
	// an open, inverted wedge with the platform visible through it. Caught
	// by a dedicated geometry-inspection pass, not the original build —
	// see PROGRESS.md. This uses the same per-side "tilt, position, then
	// sweep around Y" composition as append_ring_y (rotate-outermost,
	// CLAUDE.md/PROGRESS.md's Session 3 "rotate * translate, not
	// translate * rotate" lesson), just 4 fixed 90-degree steps instead of
	// a loop over an arbitrary count, since a square pyramid always has
	// exactly 4 sides.
	roof_half_base: f32 = TOWER_ROOF_SIZE * 0.5
	roof_pitch := math.atan2(TOWER_ROOF_HEIGHT, roof_half_base)
	roof_slant := math.sqrt(roof_half_base*roof_half_base + TOWER_ROOF_HEIGHT*TOWER_ROOF_HEIGHT)
	roof_base_y: f32 = TOWER_HEIGHT + TOWER_PLATFORM_THICKNESS*0.5

	roof_slab := geo.Cube(TOWER_ROOF_SIZE, 0.06, roof_slant)
	defer geo.Destroy(&roof_slab)
	for side in 0 ..< 4 {
		angle := f32(side) * (math.PI * 0.5)
		transform := la.mul(
			la.matrix4_rotate(angle, la.Vector3f32{0, 1, 0}),
			la.mul(
				la.matrix4_translate(la.Vector3f32{0, roof_base_y + TOWER_ROOF_HEIGHT*0.5, roof_half_base*0.5}),
				la.matrix4_rotate(roof_pitch, la.Vector3f32{1, 0, 0}),
			),
		)
		geo.Append_Mesh(&root, roof_slab, transform)
	}

	geo.Upload(&root)
	tower := Add_Node(h, "Watchtower", NO_PARENT, position_transform(WATCHTOWER_POSITION), root, Default_Material(COLOR_TOWER))

	// Floodlight head: a mounting bracket plus TWO lamp housings (not one) —
	// Prompts.md's Session 5 spec asks for "two lamp housings" by name,
	// matching Plan.md's 2 watchtower floodlight spot lights (roadmap step
	// 5). Built as its own small composite, same technique as every object
	// root above, just attached as a child node instead of NO_PARENT so it
	// can rotate independently later (Patrol Mode, roadmap step 9).
	head := geo.Empty_Mesh()
	mount := geo.Cube(0.9, 0.15, 0.35)
	defer geo.Destroy(&mount)
	append_translated(&head, mount, la.Vector3f32{0, 0, 0})

	lamp := geo.Cube(0.3, 0.3, 0.3)
	defer geo.Destroy(&lamp)
	for side in 0 ..< 2 {
		sign_x: f32 = -1 if side == 0 else 1
		append_translated(&head, lamp, la.Vector3f32{sign_x * 0.3, 0.2, 0})
	}

	geo.Upload(&head)
	head_local := Identity_Transform()
	head_local.Position = {0, TOWER_HEIGHT + TOWER_PLATFORM_THICKNESS*0.5 + TOWER_ROOF_HEIGHT + 0.3, 0}
	Add_Node(h, "Watchtower Floodlight Head", tower, head_local, head, MATERIAL_FLOODLIGHT)
}

// ---------------------------------------------------------------------------
// 2. Perimeter fence + gate — a runtime loop around a rectangle, posts +
// panels, with a gap left open on the +Z side for the gate.
// ---------------------------------------------------------------------------

FENCE_POST_SPACING :: 2.0
FENCE_POST_HEIGHT :: 1.8
FENCE_POST_THICKNESS :: 0.15
FENCE_PANEL_HEIGHT :: 1.4

build_perimeter_fence :: proc(h: ^Hierarchy) {
	root := geo.Empty_Mesh()

	post := geo.Cube(FENCE_POST_THICKNESS, FENCE_POST_HEIGHT, FENCE_POST_THICKNESS)
	defer geo.Destroy(&post)
	gate_post := geo.Cube(FENCE_POST_THICKNESS * 1.6, FENCE_POST_HEIGHT * 1.15, FENCE_POST_THICKNESS * 1.6)
	defer geo.Destroy(&gate_post)

	perimeter := 4 * 2 * (FENCE_HALF_WIDTH + FENCE_HALF_DEPTH) // walked distance around the rectangle (each side twice-counted cancels below)
	post_count := int((4 * (FENCE_HALF_WIDTH + FENCE_HALF_DEPTH)) / FENCE_POST_SPACING)
	_ = perimeter

	previous_point, previous_valid := la.Vector3f32{}, false

	for i in 0 ..= post_count {
		point := Fence_Post_Position(f32(i) / f32(post_count))
		in_gate_gap := point.z > FENCE_HALF_DEPTH-0.01 && abs(point.x) < FENCE_GATE_HALF_WIDTH

		if in_gate_gap {
			previous_valid = false
			continue
		}

		is_gate_flank := point.z > FENCE_HALF_DEPTH-0.01 && abs(point.x) < FENCE_GATE_HALF_WIDTH+FENCE_POST_SPACING*0.6
		append_translated(&root, is_gate_flank ? gate_post : post, point+la.Vector3f32{0, FENCE_POST_HEIGHT * 0.5, 0})

		if previous_valid {
			append_fence_panel(&root, previous_point, point, FENCE_PANEL_HEIGHT)
		}
		previous_point, previous_valid = point, true
	}

	geo.Upload(&root)
	fence := Add_Node(h, "Perimeter Fence", NO_PARENT, Identity_Transform(), root, Default_Material(COLOR_FENCE))

	// Gate panel: the gap left above is otherwise just an opening. Its own
	// child node (not appended into the fence's composite root, unlike a
	// regular wall panel) so it gets a visually distinct material and is
	// independently addressable later (e.g. Inspection Mode swinging it
	// open) — spans the same two points the loop above placed gate_posts
	// at, via the same fence_panel_mesh the regular wall panels use, just
	// slightly shorter so it reads as a gate leaf rather than more fence.
	gate_left := la.Vector3f32{-FENCE_GATE_HALF_WIDTH, 0, FENCE_HALF_DEPTH}
	gate_right := la.Vector3f32{FENCE_GATE_HALF_WIDTH, 0, FENCE_HALF_DEPTH}
	gate_panel := fence_panel_mesh(gate_left, gate_right, FENCE_PANEL_HEIGHT*0.8)
	geo.Upload(&gate_panel)
	Add_Node(h, "Perimeter Gate", fence, Identity_Transform(), gate_panel, Default_Material(COLOR_GATE))
}

// Fence_Post_Position walks the rectangle's boundary as t goes 0..1,
// starting at the +Z gate side's centre-right and going clockwise (viewed
// from above) — a formula over t, not a stored path. EXPORTED (unlike
// every other per-file helper in this file) specifically so a later
// session can place fence lamps by calling this SAME formula again rather
// than needing this file to have stored/exposed a list of post positions
// itself — matches this project's "recompute from a formula, don't cache
// scene data" convention (CLAUDE.md §2 item 5) better than exporting a
// position array would.
Fence_Post_Position :: proc(t: f32) -> la.Vector3f32 {
	side_length: f32 = 2 * FENCE_HALF_WIDTH
	perimeter := 4 * side_length
	distance := t * perimeter

	switch {
	case distance <= side_length: // +Z side, walking -X -> +X
		return la.Vector3f32{-FENCE_HALF_WIDTH + distance, 0, FENCE_HALF_DEPTH}
	case distance <= 2*side_length: // +X side, walking +Z -> -Z
		return la.Vector3f32{FENCE_HALF_WIDTH, 0, FENCE_HALF_DEPTH - (distance - side_length)}
	case distance <= 3*side_length: // -Z side, walking +X -> -X
		return la.Vector3f32{FENCE_HALF_WIDTH - (distance - 2*side_length), 0, -FENCE_HALF_DEPTH}
	case:
		return la.Vector3f32{-FENCE_HALF_WIDTH, 0, -FENCE_HALF_DEPTH + (distance - 3*side_length)}
	}
}

// fence_panel_mesh builds one wall panel spanning FROM a TO b at the given
// height, as its own standalone mesh already positioned/oriented (not
// appended into anything) — shared by append_fence_panel (regular wall
// panels, appended into the fence's composite root) and the gate panel
// (its own child node) below.
@(private = "file")
fence_panel_mesh :: proc(a, b: la.Vector3f32, height: f32) -> geo.Mesh {
	midpoint := (a + b) * 0.5
	span := la.length(b - a)

	direction := la.normalize(b - a)
	angle := math.atan2(-direction.x, -direction.z) // same yaw formula Library/Camera.Camera_Looking_At uses

	panel := geo.Cube(0.04, height, span*0.96)
	defer geo.Destroy(&panel)

	mesh := geo.Empty_Mesh()
	transform := la.mul(
		la.matrix4_translate(midpoint+la.Vector3f32{0, height * 0.5, 0}),
		la.matrix4_rotate(angle, la.Vector3f32{0, 1, 0}),
	)
	geo.Append_Mesh(&mesh, panel, transform)
	return mesh
}

@(private = "file")
append_fence_panel :: proc(dst: ^geo.Mesh, a, b: la.Vector3f32, height: f32) {
	if la.length(b - a) < 0.01 do return // adjacent posts across the gate gap: no panel

	panel_mesh := fence_panel_mesh(a, b, height)
	defer geo.Destroy(&panel_mesh)
	geo.Append_Mesh(dst, panel_mesh, la.MATRIX4F32_IDENTITY)
}

// ---------------------------------------------------------------------------
// 3. Armored jeep — body/cabin/hood/wheels/headlights as one composite,
// plus a child windshield node (candidate ray-traced surface, roadmap
// step 11, CLAUDE.md §6.2).
// ---------------------------------------------------------------------------

JEEP_BODY_SIZE :: la.Vector3f32{1.8, 0.6, 3.2}
JEEP_WHEEL_RADIUS :: 0.4
JEEP_WHEEL_SEGMENTS :: 6

build_jeep :: proc(h: ^Hierarchy) {
	root := geo.Empty_Mesh()

	body := geo.Cube(JEEP_BODY_SIZE.x, JEEP_BODY_SIZE.y, JEEP_BODY_SIZE.z)
	defer geo.Destroy(&body)
	append_translated(&root, body, la.Vector3f32{0, JEEP_WHEEL_RADIUS + JEEP_BODY_SIZE.y*0.5, 0})

	cabin := geo.Cube(JEEP_BODY_SIZE.x*0.9, 0.7, 1.3)
	defer geo.Destroy(&cabin)
	append_translated(&root, cabin, la.Vector3f32{0, JEEP_WHEEL_RADIUS + JEEP_BODY_SIZE.y + 0.35, -0.6})

	hood := geo.Cube(JEEP_BODY_SIZE.x*0.85, 0.35, 1.0)
	defer geo.Destroy(&hood)
	append_translated(&root, hood, la.Vector3f32{0, JEEP_WHEEL_RADIUS + JEEP_BODY_SIZE.y*0.5 + 0.15, 1.5})

	// Headlights are NOT baked into root: Prompts.md's Session 5 spec asks
	// for them as child nodes explicitly (unlike the tank's hull headlights
	// in Session 6's spec, which stay baked in — see this file's header).
	headlight_local := [2]la.Vector3f32 {
		{-JEEP_BODY_SIZE.x * 0.4, JEEP_WHEEL_RADIUS + JEEP_BODY_SIZE.y*0.5, 1.95},
		{JEEP_BODY_SIZE.x * 0.4, JEEP_WHEEL_RADIUS + JEEP_BODY_SIZE.y*0.5, 1.95},
	}

	wheel_tangential_width := 2 * JEEP_WHEEL_RADIUS * math.sin(math.PI/f32(JEEP_WHEEL_SEGMENTS)) * 1.3
	wheel_segment := geo.Cube(0.22, wheel_tangential_width, wheel_tangential_width)
	defer geo.Destroy(&wheel_segment)
	wheel := geo.Empty_Mesh()
	append_ring_x(&wheel, wheel_segment, JEEP_WHEEL_SEGMENTS, JEEP_WHEEL_RADIUS, 0)
	defer geo.Destroy(&wheel)

	for corner in 0 ..< 4 {
		sign_x: f32 = -1 if corner & 1 == 0 else 1
		sign_z: f32 = -1 if corner & 2 == 0 else 1
		wheel_x := sign_x * (JEEP_BODY_SIZE.x*0.5 + 0.1)
		wheel_z := sign_z * (JEEP_BODY_SIZE.z*0.35)
		geo.Append_Mesh(&root, wheel, la.matrix4_translate(la.Vector3f32{wheel_x, JEEP_WHEEL_RADIUS, wheel_z}))
	}

	geo.Upload(&root)
	jeep := Add_Node(h, "Jeep", NO_PARENT, position_transform(JEEP_POSITION), root, Default_Material(COLOR_JEEP))

	windshield := geo.Plane(JEEP_BODY_SIZE.x*0.85, 0.7)
	geo.Upload(&windshield)
	windshield_local := Identity_Transform()
	windshield_local.Position = {0, JEEP_WHEEL_RADIUS + JEEP_BODY_SIZE.y + 0.35 + 0.35, -1.2}
	windshield_local.Rotation.x = math.to_radians(f32(-20)) // tilted back, per pitch's "positive looks up" convention this leans it back
	Add_Node(h, "Jeep Windshield", jeep, windshield_local, windshield, MATERIAL_GLASS)

	headlight_name := [2]string{"Jeep Headlight Left", "Jeep Headlight Right"}
	for side in 0 ..< 2 {
		headlight := geo.Cube(0.18, 0.18, 0.1)
		geo.Upload(&headlight)
		Add_Node(h, headlight_name[side], jeep, position_transform(headlight_local[side]), headlight, MATERIAL_FLOODLIGHT)
	}
}

// ---------------------------------------------------------------------------
// 4. Sandbag bunker — a U-shaped wall (3 sides) of short low-segment
// "cylinder" sandbags (Prompts.md Session 5's own wording), stacked and
// staggered, 2 rows high, open on the +Z side.
// ---------------------------------------------------------------------------

BUNKER_HALF_WIDTH :: 2.2
BUNKER_HALF_DEPTH :: 1.6
BUNKER_ROW_HEIGHT :: 0.3
BUNKER_ROWS :: 2
BUNKER_BAG_LENGTH :: 0.6
BUNKER_BAG_RADIUS :: 0.17
BUNKER_BAG_SEGMENTS :: 6

build_bunker :: proc(h: ^Hierarchy) {
	root := geo.Empty_Mesh()

	// Each "sandbag" is its own tiny box-ring cylinder (CLAUDE.md §2 item
	// 6's own technique, same append_ring_y every other round shape in
	// this file uses) — round enough in plan view that, unlike the old
	// plain-box version, it needs no per-wall rotation: the same bag mesh
	// drops in identically on the left/right/back walls below.
	bag_piece_width := 2 * BUNKER_BAG_RADIUS * math.sin(math.PI/f32(BUNKER_BAG_SEGMENTS)) * 1.3
	bag_piece := geo.Cube(0.12, BUNKER_ROW_HEIGHT, bag_piece_width)
	defer geo.Destroy(&bag_piece)
	bag := geo.Empty_Mesh()
	append_ring_y(&bag, bag_piece, BUNKER_BAG_SEGMENTS, BUNKER_BAG_RADIUS, 0)

	// append_ring_y only builds the ring's SIDE wall — a tube open at both
	// ends, not a solid bag. Confirmed by a dedicated geometry-inspection
	// capture, not visible at write time: from anywhere above roughly
	// eye-level (which is most of this project's usual camera angles) you
	// can see straight through the open top into the hollow interior,
	// reading as a cluster of little pipes rather than stacked sandbags —
	// see PROGRESS.md. Capped top and bottom with a small flat Cube "lid"
	// on the SHARED bag template (added once here, so every instance below
	// gets it for free through Append_Mesh, no per-instance cost). A
	// square lid can't match the ring's hexagonal cross-section exactly;
	// sized smaller than the ring's own diameter so its corners stay
	// inside the hexagon's flats rather than poking past the silhouette.
	cap_size: f32 = BUNKER_BAG_RADIUS * 1.5
	cap := geo.Cube(cap_size, 0.06, cap_size)
	defer geo.Destroy(&cap)
	append_translated(&bag, cap, la.Vector3f32{0, BUNKER_ROW_HEIGHT*0.5, 0})
	append_translated(&bag, cap, la.Vector3f32{0, -BUNKER_ROW_HEIGHT*0.5, 0})

	defer geo.Destroy(&bag)

	// 3 straight runs (left, back, right) walked by a formula, staggered
	// (running-bond) between rows so it reads as stacked sandbags rather
	// than a stacked brick wall. bag_length is a runtime copy of the
	// constant so the division below is a normal float divide truncated at
	// runtime, not a compile-time constant fold (which refuses to truncate
	// a non-whole result when converting straight to int).
	bag_length: f32 = BUNKER_BAG_LENGTH

	for row in 0 ..< BUNKER_ROWS {
		y := BUNKER_ROW_HEIGHT * (f32(row) + 0.5)
		stagger := bag_length * 0.5 * f32(row % 2)

		bags_per_side := int(BUNKER_HALF_DEPTH * 2 / bag_length)
		for i in 0 ..< bags_per_side { 	// left wall, running along Z
			z := -BUNKER_HALF_DEPTH + BUNKER_BAG_LENGTH*(f32(i)+0.5) + stagger
			if z > BUNKER_HALF_DEPTH do continue
			append_translated(&root, bag, la.Vector3f32{-BUNKER_HALF_WIDTH, y, z})
		}
		for i in 0 ..< bags_per_side { 	// right wall
			z := -BUNKER_HALF_DEPTH + BUNKER_BAG_LENGTH*(f32(i)+0.5) + stagger
			if z > BUNKER_HALF_DEPTH do continue
			append_translated(&root, bag, la.Vector3f32{BUNKER_HALF_WIDTH, y, z})
		}

		bags_across := int(BUNKER_HALF_WIDTH * 2 / bag_length)
		for i in 0 ..< bags_across { 	// back wall, running along X
			x := -BUNKER_HALF_WIDTH + BUNKER_BAG_LENGTH*(f32(i)+0.5) + stagger
			if x > BUNKER_HALF_WIDTH do continue
			append_translated(&root, bag, la.Vector3f32{x, y, -BUNKER_HALF_DEPTH})
		}
	}

	geo.Upload(&root)
	Add_Node(h, "Sandbag Bunker", NO_PARENT, position_transform(BUNKER_POSITION), root, Default_Material(COLOR_SANDBAG))
}

// ---------------------------------------------------------------------------
// 5. Radar dish / antenna mast — mast root, plus child dish (rotates
// continuously in Patrol Mode, roadmap step 9) and beacon (blinks via a
// runtime sine function, same roadmap step, Plan.md §3) nodes.
// ---------------------------------------------------------------------------

RADAR_MAST_HEIGHT :: 3.2
RADAR_DISH_RADIUS :: 0.9
RADAR_DISH_SEGMENTS :: 10

build_radar :: proc(h: ^Hierarchy) {
	root := geo.Empty_Mesh()

	mast := geo.Cube(0.2, RADAR_MAST_HEIGHT, 0.2)
	defer geo.Destroy(&mast)
	append_translated(&root, mast, la.Vector3f32{0, RADAR_MAST_HEIGHT * 0.5, 0})

	geo.Upload(&root)
	radar := Add_Node(h, "Radar Mast", NO_PARENT, position_transform(RADAR_POSITION), root, Default_Material(COLOR_RADAR_MAST))

	dish_tangential_width := 2 * RADAR_DISH_RADIUS * math.sin(math.PI/f32(RADAR_DISH_SEGMENTS)) * 1.3
	dish_segment := geo.Cube(0.5, 0.08, dish_tangential_width)
	dish := geo.Empty_Mesh()
	append_ring_y(&dish, dish_segment, RADAR_DISH_SEGMENTS, RADAR_DISH_RADIUS*0.55, 0)
	geo.Destroy(&dish_segment)
	geo.Upload(&dish)

	dish_local := Identity_Transform()
	dish_local.Position = {0, RADAR_MAST_HEIGHT * 0.75, 0}
	dish_local.Rotation.x = math.to_radians(f32(35)) // tilted skyward
	Add_Node(h, "Radar Dish", radar, dish_local, dish, Default_Material(COLOR_RADAR_DISH))

	// Beacon is its own child node (not baked into root, unlike the old
	// version) — Plan.md §3 has it blinking via a runtime sine function in
	// Patrol Mode (roadmap step 9), which needs it independently
	// addressable, and MATERIAL_BEACON's emission previews that "lit
	// warning light" look under this session's placeholder shading.
	beacon := geo.Tetrahedron(0.35)
	geo.Upload(&beacon)
	beacon_local := Identity_Transform()
	beacon_local.Position = {0, RADAR_MAST_HEIGHT + 0.2, 0}
	Add_Node(h, "Radar Beacon", radar, beacon_local, beacon, MATERIAL_BEACON)
}

// ---------------------------------------------------------------------------
// 6. Barracks hut — box body + wedge roof, plus 3 child window nodes
// (area-light sampling, roadmap step 6, CLAUDE.md §6.3).
// ---------------------------------------------------------------------------

BARRACKS_SIZE :: la.Vector3f32{4.5, 1.6, 2.4}
BARRACKS_ROOF_RISE :: 1.0
BARRACKS_WINDOW_COUNT :: 3
BARRACKS_WINDOW_WIDTH :: 0.6
BARRACKS_WINDOW_HEIGHT :: 0.5

build_barracks :: proc(h: ^Hierarchy) {
	root := geo.Empty_Mesh()

	body := geo.Cube(BARRACKS_SIZE.x, BARRACKS_SIZE.y, BARRACKS_SIZE.z)
	defer geo.Destroy(&body)
	append_translated(&root, body, la.Vector3f32{0, BARRACKS_SIZE.y * 0.5, 0})

	door := geo.Cube(0.7, 1.1, 0.06)
	defer geo.Destroy(&door)
	append_translated(&root, door, la.Vector3f32{0, 0.55, BARRACKS_SIZE.z * 0.5})

	// Roof: 2 slabs tilted to meet at a ridge along X, each covering half
	// the depth — the low-poly "wedge roof" CLAUDE.md §5.1 describes.
	roof_slab := geo.Cube(BARRACKS_SIZE.x+0.3, 0.08, BARRACKS_SIZE.z*0.62)
	defer geo.Destroy(&roof_slab)
	roof_pitch := math.atan2(f32(BARRACKS_ROOF_RISE), BARRACKS_SIZE.z*0.5)
	for side in 0 ..< 2 {
		sign: f32 = -1 if side == 0 else 1
		transform := la.mul(
			la.matrix4_translate(la.Vector3f32{0, BARRACKS_SIZE.y + BARRACKS_ROOF_RISE*0.5, sign * BARRACKS_SIZE.z * 0.22}),
			la.matrix4_rotate(sign*roof_pitch, la.Vector3f32{1, 0, 0}),
		)
		geo.Append_Mesh(&root, roof_slab, transform)
	}

	geo.Upload(&root)
	barracks := Add_Node(h, "Barracks Hut", NO_PARENT, position_transform(BARRACKS_POSITION), root, Default_Material(COLOR_BARRACKS))

	// A separate geo.Plane + Upload PER window, not one shared mesh reused
	// across 3 Add_Node calls: every Node owns its own Mesh (Scene.Destroy
	// calls geo.Destroy once per node), so handing the same Mesh value to
	// more than one Add_Node call gives two nodes copies that share one
	// underlying Vertices/Indices allocation — the second Destroy then
	// frees already-freed memory. Caught via a real crash
	// ("pointer being freed was not allocated") during Scene.Destroy, not
	// spotted by inspection — see PROGRESS.md.
	// Window dimensions are named constants (BARRACKS_WINDOW_WIDTH/HEIGHT,
	// not inline literals) specifically so a later session can read them
	// back directly instead of re-deriving them from the Plane() call —
	// Prompts.md's Session 6 spec asks to "expose each window's quad
	// geometry (centre, width, height, normal) via the node's world
	// transform": centre = Scene.World_Position(world_matrix), normal =
	// Scene.World_Direction(world_matrix, {0,0,1}) (a Plane's local normal
	// is always +Z, Library/Geometry/Geometry.odin), width/height are
	// these two constants. Roadmap step 6 (Session 9) is exactly this
	// exposure actually being used: Library/Lights.Build_Rig reads
	// BARRACKS_WINDOW_WIDTH/HEIGHT directly to size each window's AREA
	// light quad. No new helper proc needed — Transform.odin's
	// existing World_Position/World_Direction already are that exposure
	// mechanism, given the node's own world matrix (computed fresh every
	// frame by Scene.Compute_World_Matrices, never cached).
	for i in 0 ..< BARRACKS_WINDOW_COUNT {
		window := geo.Plane(BARRACKS_WINDOW_WIDTH, BARRACKS_WINDOW_HEIGHT)
		geo.Upload(&window)

		t := (f32(i) + 0.5) / f32(BARRACKS_WINDOW_COUNT)
		window_local := Identity_Transform()
		// On the BACK (-Z) wall, not the front — the front is the door's
		// wall, and an evenly-spaced 3-window row is symmetric about X=0,
		// which is exactly the door's own X position, so a middle window on
		// the front wall would sit right on top of the door. Moving the
		// whole row to the back wall avoids that overlap by construction
		// rather than by carving an asymmetric gap out of the spacing
		// formula. A Plane's local normal is always +Z (Library/Geometry/
		// Geometry.odin), so it needs a 180-degree yaw to face -Z (outward
		// on this wall) instead of into the building.
		//
		// PROUD of the wall (a small POSITIVE offset past -SIZE.z*0.5, not
		// a negative one) — the previous version placed the window BEHIND
		// the wall's own outward-facing surface, i.e. embedded inside the
		// solid Cube body with no actual opening cut into it, so the wall's
		// opaque front face permanently occluded it from every exterior
		// angle (this is a Cube, not a wall with a real cut-out; there is
		// no CSG in this project, CLAUDE.md §2). Confirmed invisible via a
		// dedicated geometry-inspection capture, not caught at write time —
		// see PROGRESS.md. Proud placement matches how the door (a solid
		// Cube, so it inherently pokes out by half its own thickness) is
		// already visible.
		window_local.Position = {(t - 0.5) * (BARRACKS_SIZE.x - 0.8), BARRACKS_SIZE.y * 0.6, -BARRACKS_SIZE.z*0.5 - 0.02}
		window_local.Rotation.y = math.PI
		// MATERIAL_BARRACKS_WINDOW, not MATERIAL_GLASS (roadmap step 6,
		// Session 9) — a warm glow distinct from the cool jeep/tank glass,
		// since this window is now also an actual AREA light source
		// (Library/Lights.Build_Rig), not just an emissive-looking surface.
		Add_Node(h, fmt_window_name(i), barracks, window_local, window, MATERIAL_BARRACKS_WINDOW)
	}
}

@(private = "file")
fmt_window_name :: proc(index: int) -> string {
	switch index {
	case 0: return "Barracks Window 1"
	case 1: return "Barracks Window 2"
	case: return "Barracks Window 3"
	}
}

// ---------------------------------------------------------------------------
// 7. Cargo crate stack — several crates, sizes/rotation varied by a
// deterministic function of the loop index (not a literal per-crate list).
// ---------------------------------------------------------------------------

CRATE_COUNT :: 6
CRATE_BASE_SIZE :: 0.8

build_crate_stack :: proc(h: ^Hierarchy) {
	root := geo.Empty_Mesh()

	y := f32(0)
	for i in 0 ..< CRATE_COUNT {
		size := CRATE_BASE_SIZE * (1 + 0.2*math.sin(f32(i) * 1.7))
		crate := geo.Cube(size, size, size)
		defer geo.Destroy(&crate)

		// Staggered pyramid-ish stack: every 3rd crate starts a new,
		// slightly inset layer.
		layer := i / 3
		within_layer := i % 3
		x := (f32(within_layer) - 1) * (CRATE_BASE_SIZE*0.9) * (1 - 0.15*f32(layer))
		rotation_y := f32(i) * 0.35

		transform := la.mul(
			la.matrix4_translate(la.Vector3f32{x, y + size*0.5, f32(layer) * 0.15}),
			la.matrix4_rotate(rotation_y, la.Vector3f32{0, 1, 0}),
		)
		geo.Append_Mesh(&root, crate, transform)

		if within_layer == 2 do y += size
	}

	geo.Upload(&root)
	Add_Node(h, "Cargo Crate Stack", NO_PARENT, position_transform(CRATE_STACK_POSITION), root, Default_Material(COLOR_CRATE))
}

// ---------------------------------------------------------------------------
// 8. Battle tank — hull (root, with 2 baked-in headlight housings) ->
// turret (child, with a baked-in searchlight housing) -> barrel + periscope
// (children of turret). CLAUDE.md §5.3's clearest hierarchy showcase: the
// turret must rotate independently of the hull.
// ---------------------------------------------------------------------------

TANK_HULL_SIZE :: la.Vector3f32{2.2, 0.7, 4.2}
TANK_TREAD_HEIGHT :: 0.5
TANK_ROAD_WHEEL_COUNT :: 5
TANK_ROAD_WHEEL_RADIUS :: 0.22
TANK_ROAD_WHEEL_SEGMENTS :: 6 // matches JEEP_WHEEL_SEGMENTS and CLAUDE.md §2 item 8's 6-10 segment guidance; 5 read as fragmented at close/oblique angles (see PROGRESS.md)
TANK_TURRET_SIZE :: la.Vector3f32{1.5, 0.55, 1.8}
TANK_BARREL_LENGTH :: 2.4

build_tank :: proc(h: ^Hierarchy) {
	root := geo.Empty_Mesh()

	hull := geo.Cube(TANK_HULL_SIZE.x, TANK_HULL_SIZE.y, TANK_HULL_SIZE.z)
	defer geo.Destroy(&hull)
	append_translated(&root, hull, la.Vector3f32{0, TANK_TREAD_HEIGHT + TANK_HULL_SIZE.y*0.5, 0})

	glacis := geo.Tetrahedron(TANK_HULL_SIZE.x * 0.9)
	defer geo.Destroy(&glacis)
	glacis_transform := la.mul(
		la.matrix4_translate(la.Vector3f32{0, TANK_TREAD_HEIGHT + TANK_HULL_SIZE.y*0.5, TANK_HULL_SIZE.z*0.5}),
		la.matrix4_scale(la.Vector3f32{1, TANK_HULL_SIZE.y / (TANK_HULL_SIZE.x*0.9), 0.6}),
	)
	geo.Append_Mesh(&root, glacis, glacis_transform)

	// Two headlight housings on the hull (Prompts.md Session 6 spec) — like
	// the tank's turret headlights, baked into the composite rather than
	// given child nodes: THIS spec says only "on the hull," unlike the
	// jeep's Session 5 spec which explicitly asked for child nodes (see
	// this file's header for that distinction).
	headlight := geo.Cube(0.16, 0.16, 0.1)
	defer geo.Destroy(&headlight)
	for side in 0 ..< 2 {
		sign: f32 = -1 if side == 0 else 1
		append_translated(&root, headlight, la.Vector3f32{sign * TANK_HULL_SIZE.x * 0.35, TANK_TREAD_HEIGHT + TANK_HULL_SIZE.y*0.75, TANK_HULL_SIZE.z*0.5 - 0.15})
	}

	tread := geo.Cube(0.35, TANK_TREAD_HEIGHT, TANK_HULL_SIZE.z+0.2)
	defer geo.Destroy(&tread)
	for side in 0 ..< 2 {
		sign: f32 = -1 if side == 0 else 1
		append_translated(&root, tread, la.Vector3f32{sign * (TANK_HULL_SIZE.x*0.5 + 0.1), TANK_TREAD_HEIGHT * 0.5, 0})
	}

	// Road wheels are small box-ring "cylinders" (same append_ring_x
	// technique as the jeep's actual wheels), not flat boxes — matches
	// this project's low-poly-cylinder-over-plain-box convention
	// established fixing the sandbag bunker in Session 5.
	wheel_tangential_width := 2 * TANK_ROAD_WHEEL_RADIUS * math.sin(math.PI/f32(TANK_ROAD_WHEEL_SEGMENTS)) * 1.3
	wheel_segment := geo.Cube(0.12, wheel_tangential_width, wheel_tangential_width)
	defer geo.Destroy(&wheel_segment)
	road_wheel := geo.Empty_Mesh()
	append_ring_x(&road_wheel, wheel_segment, TANK_ROAD_WHEEL_SEGMENTS, TANK_ROAD_WHEEL_RADIUS, 0)
	defer geo.Destroy(&road_wheel)

	for side in 0 ..< 2 {
		sign: f32 = -1 if side == 0 else 1
		for i in 0 ..< TANK_ROAD_WHEEL_COUNT {
			t := (f32(i)+0.5) / f32(TANK_ROAD_WHEEL_COUNT)
			z := (t-0.5) * (TANK_HULL_SIZE.z - 0.3)
			geo.Append_Mesh(&root, road_wheel, la.matrix4_translate(la.Vector3f32{sign * (TANK_HULL_SIZE.x*0.5 + 0.1), TANK_TREAD_HEIGHT * 0.5, z}))
		}
	}

	geo.Upload(&root)
	hull_node := Add_Node(h, "Tank Hull", NO_PARENT, position_transform(TANK_POSITION), root, Default_Material(COLOR_TANK))

	// Turret mesh includes a searchlight housing (Prompts.md Session 6
	// spec: "a searchlight housing on the turret") baked in alongside the
	// turret box itself — same "on the X," not "child of X" reading as the
	// hull headlights above.
	turret := geo.Empty_Mesh()
	turret_box := geo.Cube(TANK_TURRET_SIZE.x, TANK_TURRET_SIZE.y, TANK_TURRET_SIZE.z)
	defer geo.Destroy(&turret_box)
	append_translated(&turret, turret_box, la.Vector3f32{0, 0, 0})

	searchlight := geo.Cube(0.22, 0.22, 0.22)
	defer geo.Destroy(&searchlight)
	append_translated(&turret, searchlight, la.Vector3f32{-0.5, TANK_TURRET_SIZE.y*0.5+0.1, 0})

	geo.Upload(&turret)
	turret_local := Identity_Transform()
	turret_local.Position = {0, TANK_TREAD_HEIGHT + TANK_HULL_SIZE.y + TANK_TURRET_SIZE.y*0.5, -0.3}
	turret_node := Add_Node(h, "Tank Turret", hull_node, turret_local, turret, Default_Material(COLOR_TANK))

	barrel := geo.Cube(0.18, 0.18, TANK_BARREL_LENGTH)
	geo.Upload(&barrel)
	barrel_local := Identity_Transform()
	barrel_local.Position = {0, 0, TANK_TURRET_SIZE.z*0.5 + TANK_BARREL_LENGTH*0.5}
	Add_Node(h, "Tank Barrel", turret_node, barrel_local, barrel, Default_Material(COLOR_GUN))

	periscope := geo.Plane(0.3, 0.2)
	geo.Upload(&periscope)
	periscope_local := Identity_Transform()
	periscope_local.Position = {0.5, TANK_TURRET_SIZE.y * 0.5+0.02, 0}
	periscope_local.Rotation.x = math.to_radians(f32(-90)) // faces up
	Add_Node(h, "Tank Periscope", turret_node, periscope_local, periscope, MATERIAL_GLASS)
}

// ---------------------------------------------------------------------------
// 9. Static gun emplacement — sandbag ring + tripod + gun + a work-light
// post. Deliberately static: no children, no independent articulation
// (contrasts with the tank, CLAUDE.md §5.1 item 9).
// ---------------------------------------------------------------------------

GUN_RING_RADIUS :: 1.4
GUN_RING_SEGMENTS :: 10
GUN_TRIPOD_LEG_COUNT :: 3
GUN_TRIPOD_HEIGHT :: 0.8
GUN_WORK_LIGHT_POST_HEIGHT :: 1.1

build_gun_emplacement :: proc(h: ^Hierarchy) {
	root := geo.Empty_Mesh()

	ring_tangential_width := 2 * GUN_RING_RADIUS * math.sin(math.PI/f32(GUN_RING_SEGMENTS)) * 1.3
	ring_segment := geo.Cube(0.4, 0.35, ring_tangential_width)
	defer geo.Destroy(&ring_segment)
	append_ring_y(&root, ring_segment, GUN_RING_SEGMENTS, GUN_RING_RADIUS, 0.17)

	leg := geo.Cube(0.08, GUN_TRIPOD_HEIGHT, 0.08)
	defer geo.Destroy(&leg)
	for i in 0 ..< GUN_TRIPOD_LEG_COUNT {
		angle := f32(i) * (2 * math.PI / f32(GUN_TRIPOD_LEG_COUNT))
		leg_radius := f32(0.35)
		// Legs splay outward: translated out from centre, tilted to lean
		// in toward the apex, then swept to their position by the same
		// rotate-after-translate composition as every other ring here.
		transform := la.mul(
			la.matrix4_rotate(angle, la.Vector3f32{0, 1, 0}),
			la.mul(
				la.matrix4_translate(la.Vector3f32{leg_radius, GUN_TRIPOD_HEIGHT * 0.5, 0}),
				la.matrix4_rotate(math.to_radians(f32(18)), la.Vector3f32{0, 0, 1}),
			),
		)
		geo.Append_Mesh(&root, leg, transform)
	}

	gun_body := geo.Cube(0.3, 0.3, 0.9)
	defer geo.Destroy(&gun_body)
	append_translated(&root, gun_body, la.Vector3f32{0, GUN_TRIPOD_HEIGHT, 0.2})

	gun_barrel := geo.Cube(0.1, 0.1, 1.1)
	defer geo.Destroy(&gun_barrel)
	append_translated(&root, gun_barrel, la.Vector3f32{0, GUN_TRIPOD_HEIGHT, 1.1})

	// Work-light post (Prompts.md Session 6 spec: "a small work-light post
	// beside it") — just the post; the light itself is a future point light
	// (roadmap step 5) with a constant local offset from this object's own
	// root, same treatment as the tank's hull headlights above, since
	// nothing here asks for it to be a separate child node.
	light_post := geo.Cube(0.08, GUN_WORK_LIGHT_POST_HEIGHT, 0.08)
	defer geo.Destroy(&light_post)
	append_translated(&root, light_post, la.Vector3f32{GUN_RING_RADIUS + 0.5, GUN_WORK_LIGHT_POST_HEIGHT * 0.5, 0})

	geo.Upload(&root)
	Add_Node(h, "Gun Emplacement", NO_PARENT, position_transform(GUN_EMPLACEMENT_POSITION), root, Default_Material(COLOR_SANDBAG))
}

// position_transform is Identity_Transform with only Position set — a
// one-line convenience for the many root nodes above that need no
// rotation/scale of their own.
@(private = "file")
position_transform :: proc(position: la.Vector3f32) -> Transform {
	t := Identity_Transform()
	t.Position = position
	return t
}
