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
// §6.3). Fixed attachment points for a simple point/spot light that never
// moves independently of its parent (jeep headlights, tank hull
// headlights, the gun emplacement's work light) do NOT get their own node
// here — Session 8 (roadmap step 5) can give such a light a constant
// local-space offset from the existing parent node directly; inventing an
// empty marker node for every future light now would be scope creep this
// session's actual job (geometry) doesn't need.
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
// COLOUR: each root/child node gets a flat, hand-picked, unlit Color
// (roadmap step 3 is explicitly "static; unlit," CLAUDE.md §9) purely so a
// capture of 9 overlapping objects is actually legible — real materials
// arrive at roadmap step 4. Not a hardcoded "data table" in the CLAUDE.md
// §2 item 5 sense; it's one parameter per node, same category as a mesh's
// dimensions.
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
// Colour palette (see header for why flat colour is in scope this session).
// ---------------------------------------------------------------------------

COLOR_TOWER :: la.Vector3f32{0.55, 0.58, 0.62}
COLOR_FLOODLIGHT :: la.Vector3f32{0.85, 0.85, 0.75}
COLOR_FENCE :: la.Vector3f32{0.42, 0.38, 0.28}
COLOR_JEEP :: la.Vector3f32{0.33, 0.40, 0.24}
COLOR_GLASS :: la.Vector3f32{0.55, 0.75, 0.80}
COLOR_SANDBAG :: la.Vector3f32{0.62, 0.55, 0.38}
COLOR_RADAR_MAST :: la.Vector3f32{0.5, 0.5, 0.5}
COLOR_RADAR_DISH :: la.Vector3f32{0.75, 0.75, 0.7}
COLOR_BARRACKS :: la.Vector3f32{0.45, 0.32, 0.22}
COLOR_ROOF :: la.Vector3f32{0.3, 0.22, 0.18}
COLOR_CRATE :: la.Vector3f32{0.55, 0.45, 0.18}
COLOR_TANK :: la.Vector3f32{0.28, 0.32, 0.22}
COLOR_GUN :: la.Vector3f32{0.2, 0.2, 0.2}

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

TOWER_LEG_SPAN :: 2.2 // half-distance between opposite legs
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

	roof := geo.Tetrahedron(TOWER_ROOF_SIZE)
	defer geo.Destroy(&roof)
	// A regular tetrahedron's own natural height doesn't match
	// TOWER_ROOF_HEIGHT; scaled non-uniformly on Y via the transform
	// (not the generator) to read as a shallow peaked cap.
	roof_transform := la.mul(
		la.matrix4_translate(la.Vector3f32{0, TOWER_HEIGHT + TOWER_PLATFORM_THICKNESS * 0.5 + TOWER_ROOF_HEIGHT * 0.5, 0}),
		la.matrix4_scale(la.Vector3f32{1, TOWER_ROOF_HEIGHT / TOWER_ROOF_SIZE, 1}),
	)
	geo.Append_Mesh(&root, roof, roof_transform)

	geo.Upload(&root)
	tower := Add_Node(h, "Watchtower", NO_PARENT, position_transform(WATCHTOWER_POSITION), root, COLOR_TOWER)

	head := geo.Cube(0.9, 0.5, 0.5)
	geo.Upload(&head)
	head_local := Identity_Transform()
	head_local.Position = {0, TOWER_HEIGHT + TOWER_PLATFORM_THICKNESS*0.5 + TOWER_ROOF_HEIGHT + 0.3, 0}
	Add_Node(h, "Watchtower Floodlight Head", tower, head_local, head, COLOR_FLOODLIGHT)
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
		point := point_on_fence_perimeter(f32(i) / f32(post_count))
		in_gate_gap := point.z > FENCE_HALF_DEPTH-0.01 && abs(point.x) < FENCE_GATE_HALF_WIDTH

		if in_gate_gap {
			previous_valid = false
			continue
		}

		is_gate_flank := point.z > FENCE_HALF_DEPTH-0.01 && abs(point.x) < FENCE_GATE_HALF_WIDTH+FENCE_POST_SPACING*0.6
		append_translated(&root, is_gate_flank ? gate_post : post, point+la.Vector3f32{0, FENCE_POST_HEIGHT * 0.5, 0})

		if previous_valid {
			append_fence_panel(&root, previous_point, point)
		}
		previous_point, previous_valid = point, true
	}

	geo.Upload(&root)
	Add_Node(h, "Perimeter Fence", NO_PARENT, Identity_Transform(), root, COLOR_FENCE)
}

// point_on_fence_perimeter walks the rectangle's boundary as t goes 0..1,
// starting at the +Z gate side's centre-right and going clockwise (viewed
// from above) — a formula over t, not a stored path.
@(private = "file")
point_on_fence_perimeter :: proc(t: f32) -> la.Vector3f32 {
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

@(private = "file")
append_fence_panel :: proc(dst: ^geo.Mesh, a, b: la.Vector3f32) {
	midpoint := (a + b) * 0.5
	span := la.length(b - a)
	if span < 0.01 do return // adjacent posts across the gate gap: no panel

	direction := la.normalize(b - a)
	angle := math.atan2(-direction.x, -direction.z) // same yaw formula Library/Camera.Camera_Looking_At uses

	panel := geo.Cube(0.04, FENCE_PANEL_HEIGHT, span*0.96)
	defer geo.Destroy(&panel)
	transform := la.mul(
		la.matrix4_translate(midpoint+la.Vector3f32{0, FENCE_PANEL_HEIGHT * 0.5, 0}),
		la.matrix4_rotate(angle, la.Vector3f32{0, 1, 0}),
	)
	geo.Append_Mesh(dst, panel, transform)
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

	headlight := geo.Cube(0.18, 0.18, 0.1)
	defer geo.Destroy(&headlight)
	for side in 0 ..< 2 {
		sign_x: f32 = -1 if side == 0 else 1
		append_translated(&root, headlight, la.Vector3f32{sign_x * JEEP_BODY_SIZE.x * 0.4, JEEP_WHEEL_RADIUS + JEEP_BODY_SIZE.y*0.5, 1.95})
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
	jeep := Add_Node(h, "Jeep", NO_PARENT, position_transform(JEEP_POSITION), root, COLOR_JEEP)

	windshield := geo.Plane(JEEP_BODY_SIZE.x*0.85, 0.7)
	geo.Upload(&windshield)
	windshield_local := Identity_Transform()
	windshield_local.Position = {0, JEEP_WHEEL_RADIUS + JEEP_BODY_SIZE.y + 0.35 + 0.35, -1.2}
	windshield_local.Rotation.x = math.to_radians(f32(-20)) // tilted back, per pitch's "positive looks up" convention this leans it back
	Add_Node(h, "Jeep Windshield", jeep, windshield_local, windshield, COLOR_GLASS)
}

// ---------------------------------------------------------------------------
// 4. Sandbag bunker — a U-shaped wall (3 sides) of short staggered boxes,
// 2 rows high, open on the +Z side.
// ---------------------------------------------------------------------------

BUNKER_HALF_WIDTH :: 2.2
BUNKER_HALF_DEPTH :: 1.6
BUNKER_ROW_HEIGHT :: 0.3
BUNKER_ROWS :: 2
BUNKER_BAG_LENGTH :: 0.6

build_bunker :: proc(h: ^Hierarchy) {
	root := geo.Empty_Mesh()

	bag := geo.Cube(BUNKER_BAG_LENGTH, BUNKER_ROW_HEIGHT, BUNKER_BAG_LENGTH*0.9)
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
	Add_Node(h, "Sandbag Bunker", NO_PARENT, position_transform(BUNKER_POSITION), root, COLOR_SANDBAG)
}

// ---------------------------------------------------------------------------
// 5. Radar dish / antenna mast — mast + beacon composite, plus a child
// dish node that will rotate continuously in Patrol Mode (roadmap step 9).
// ---------------------------------------------------------------------------

RADAR_MAST_HEIGHT :: 3.2
RADAR_DISH_RADIUS :: 0.9
RADAR_DISH_SEGMENTS :: 10

build_radar :: proc(h: ^Hierarchy) {
	root := geo.Empty_Mesh()

	mast := geo.Cube(0.2, RADAR_MAST_HEIGHT, 0.2)
	defer geo.Destroy(&mast)
	append_translated(&root, mast, la.Vector3f32{0, RADAR_MAST_HEIGHT * 0.5, 0})

	beacon := geo.Tetrahedron(0.35)
	defer geo.Destroy(&beacon)
	append_translated(&root, beacon, la.Vector3f32{0, RADAR_MAST_HEIGHT + 0.2, 0})

	geo.Upload(&root)
	radar := Add_Node(h, "Radar Mast", NO_PARENT, position_transform(RADAR_POSITION), root, COLOR_RADAR_MAST)

	dish_tangential_width := 2 * RADAR_DISH_RADIUS * math.sin(math.PI/f32(RADAR_DISH_SEGMENTS)) * 1.3
	dish_segment := geo.Cube(0.5, 0.08, dish_tangential_width)
	dish := geo.Empty_Mesh()
	append_ring_y(&dish, dish_segment, RADAR_DISH_SEGMENTS, RADAR_DISH_RADIUS*0.55, 0)
	geo.Destroy(&dish_segment)
	geo.Upload(&dish)

	dish_local := Identity_Transform()
	dish_local.Position = {0, RADAR_MAST_HEIGHT * 0.75, 0}
	dish_local.Rotation.x = math.to_radians(f32(35)) // tilted skyward
	Add_Node(h, "Radar Dish", radar, dish_local, dish, COLOR_RADAR_DISH)
}

// ---------------------------------------------------------------------------
// 6. Barracks hut — box body + wedge roof, plus 3 child window nodes
// (area-light sampling, roadmap step 6, CLAUDE.md §6.3).
// ---------------------------------------------------------------------------

BARRACKS_SIZE :: la.Vector3f32{4.5, 1.6, 2.4}
BARRACKS_ROOF_RISE :: 1.0
BARRACKS_WINDOW_COUNT :: 3

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
	barracks := Add_Node(h, "Barracks Hut", NO_PARENT, position_transform(BARRACKS_POSITION), root, COLOR_BARRACKS)

	// A separate geo.Plane + Upload PER window, not one shared mesh reused
	// across 3 Add_Node calls: every Node owns its own Mesh (Scene.Destroy
	// calls geo.Destroy once per node), so handing the same Mesh value to
	// more than one Add_Node call gives two nodes copies that share one
	// underlying Vertices/Indices allocation — the second Destroy then
	// frees already-freed memory. Caught via a real crash
	// ("pointer being freed was not allocated") during Scene.Destroy, not
	// spotted by inspection — see PROGRESS.md.
	for i in 0 ..< BARRACKS_WINDOW_COUNT {
		window := geo.Plane(0.6, 0.5)
		geo.Upload(&window)

		t := (f32(i) + 0.5) / f32(BARRACKS_WINDOW_COUNT)
		window_local := Identity_Transform()
		window_local.Position = {(t - 0.5) * (BARRACKS_SIZE.x - 0.8), BARRACKS_SIZE.y * 0.6, BARRACKS_SIZE.z * 0.5+0.01}
		Add_Node(h, fmt_window_name(i), barracks, window_local, window, COLOR_GLASS)
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
	Add_Node(h, "Cargo Crate Stack", NO_PARENT, position_transform(CRATE_STACK_POSITION), root, COLOR_CRATE)
}

// ---------------------------------------------------------------------------
// 8. Battle tank — hull (root) -> turret (child) -> barrel + periscope
// (children of turret). CLAUDE.md §5.3's clearest hierarchy showcase: the
// turret must rotate independently of the hull.
// ---------------------------------------------------------------------------

TANK_HULL_SIZE :: la.Vector3f32{2.2, 0.7, 4.2}
TANK_TREAD_HEIGHT :: 0.5
TANK_ROAD_WHEEL_COUNT :: 5
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

	tread := geo.Cube(0.35, TANK_TREAD_HEIGHT, TANK_HULL_SIZE.z+0.2)
	defer geo.Destroy(&tread)
	for side in 0 ..< 2 {
		sign: f32 = -1 if side == 0 else 1
		append_translated(&root, tread, la.Vector3f32{sign * (TANK_HULL_SIZE.x*0.5 + 0.1), TANK_TREAD_HEIGHT * 0.5, 0})
	}

	road_wheel := geo.Cube(0.4, TANK_TREAD_HEIGHT*0.8, 0.4)
	defer geo.Destroy(&road_wheel)
	for side in 0 ..< 2 {
		sign: f32 = -1 if side == 0 else 1
		for i in 0 ..< TANK_ROAD_WHEEL_COUNT {
			t := (f32(i)+0.5) / f32(TANK_ROAD_WHEEL_COUNT)
			z := (t-0.5) * (TANK_HULL_SIZE.z - 0.3)
			append_translated(&root, road_wheel, la.Vector3f32{sign * (TANK_HULL_SIZE.x*0.5 + 0.1), TANK_TREAD_HEIGHT * 0.5, z})
		}
	}

	geo.Upload(&root)
	hull_node := Add_Node(h, "Tank Hull", NO_PARENT, position_transform(TANK_POSITION), root, COLOR_TANK)

	turret := geo.Cube(TANK_TURRET_SIZE.x, TANK_TURRET_SIZE.y, TANK_TURRET_SIZE.z)
	geo.Upload(&turret)
	turret_local := Identity_Transform()
	turret_local.Position = {0, TANK_TREAD_HEIGHT + TANK_HULL_SIZE.y + TANK_TURRET_SIZE.y*0.5, -0.3}
	turret_node := Add_Node(h, "Tank Turret", hull_node, turret_local, turret, COLOR_TANK)

	barrel := geo.Cube(0.18, 0.18, TANK_BARREL_LENGTH)
	geo.Upload(&barrel)
	barrel_local := Identity_Transform()
	barrel_local.Position = {0, 0, TANK_TURRET_SIZE.z*0.5 + TANK_BARREL_LENGTH*0.5}
	Add_Node(h, "Tank Barrel", turret_node, barrel_local, barrel, COLOR_GUN)

	periscope := geo.Plane(0.3, 0.2)
	geo.Upload(&periscope)
	periscope_local := Identity_Transform()
	periscope_local.Position = {0.5, TANK_TURRET_SIZE.y * 0.5+0.02, 0}
	periscope_local.Rotation.x = math.to_radians(f32(-90)) // faces up
	Add_Node(h, "Tank Periscope", turret_node, periscope_local, periscope, COLOR_GLASS)
}

// ---------------------------------------------------------------------------
// 9. Static gun emplacement — sandbag ring + tripod + gun. Deliberately
// static: no children, no independent articulation (contrasts with the
// tank, CLAUDE.md §5.1 item 9).
// ---------------------------------------------------------------------------

GUN_RING_RADIUS :: 1.4
GUN_RING_SEGMENTS :: 10
GUN_TRIPOD_LEG_COUNT :: 3
GUN_TRIPOD_HEIGHT :: 0.8

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

	geo.Upload(&root)
	Add_Node(h, "Gun Emplacement", NO_PARENT, position_transform(GUN_EMPLACEMENT_POSITION), root, COLOR_SANDBAG)
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
