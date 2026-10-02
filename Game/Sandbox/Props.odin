package Sandbox

import "../../Engine/Procedural"
import "../../Engine/Render"
import "core:math"
import la "core:math/linalg"

TREE_CAPACITY :: 6000
ROCK_CAPACITY :: 4000
BUSH_CAPACITY :: 8000
GRASS_CAPACITY :: 24000
GRASS_DRAW_DISTANCE_METERS :: 45.0

// Scatter variant thresholds: [0, TREE) tree, [TREE, ROCK) rock, the rest bush.
TREE_VARIANT_LIMIT :: 0.30
ROCK_VARIANT_LIMIT :: 0.45

// Each prop has a detailed mesh for the camera and a crude proxy for the shadow pass that draws the same instances: a shadow
// is a silhouette, so a few dozen triangles do the work of a thousand.
Props :: struct {
	tree_trunk:         Render.Mesh,
	tree_canopy:        Render.Mesh,
	rock:               Render.Mesh,
	bush:               Render.Mesh,
	grass:              Render.Mesh,
	tree_trunk_shadow:  Render.Mesh,
	tree_canopy_shadow: Render.Mesh,
	rock_shadow:        Render.Mesh,
	bush_shadow:        Render.Mesh,
}

Props_Create :: proc() -> (props: Props) {
	props.tree_trunk = upload_prop(tree_trunk_mesh(), TREE_CAPACITY)
	props.tree_canopy = upload_prop(tree_canopy_mesh(), TREE_CAPACITY)
	props.rock = upload_prop(rock_mesh(), ROCK_CAPACITY)
	props.bush = upload_prop(bush_mesh(), BUSH_CAPACITY)
	props.grass = upload_prop(grass_tuft_mesh(), GRASS_CAPACITY)
	props.tree_trunk_shadow = upload_shadow_proxy(placed(Procedural.Cylinder_Create(0.2, 4, 5, 1), {0, 2, 0}, {1, 1, 1}), &props.tree_trunk)
	props.tree_canopy_shadow = upload_shadow_proxy(placed(Procedural.Sphere_Create(2.0, 8, 4), {0, 5.2, 0}, {1, 1.25, 1}), &props.tree_canopy)
	props.rock_shadow = upload_shadow_proxy(placed(Procedural.Sphere_Create(0.9, 8, 4), {0, 0.25, 0}, {1.2, 0.7, 1}), &props.rock)
	props.bush_shadow = upload_shadow_proxy(placed(Procedural.Sphere_Create(0.7, 6, 3), {0, 0.35, 0}, {1.3, 0.9, 1.3}), &props.bush)
	return props
}

Props_Destroy :: proc(props: ^Props) {
	Render.Mesh_Destroy(&props.tree_trunk_shadow)
	Render.Mesh_Destroy(&props.tree_canopy_shadow)
	Render.Mesh_Destroy(&props.rock_shadow)
	Render.Mesh_Destroy(&props.bush_shadow)
	Render.Mesh_Destroy(&props.tree_trunk)
	Render.Mesh_Destroy(&props.tree_canopy)
	Render.Mesh_Destroy(&props.rock)
	Render.Mesh_Destroy(&props.bush)
	Render.Mesh_Destroy(&props.grass)
}

@(private = "file")
upload_shadow_proxy :: proc(mesh: Procedural.Mesh, owner: ^Render.Mesh) -> Render.Mesh {
	mesh := mesh
	defer Procedural.Mesh_Destroy(&mesh)
	return Render.Mesh_Upload_Instanced_Sharing(mesh, owner)
}

@(private = "file")
upload_prop :: proc(mesh: Procedural.Mesh, capacity: int) -> Render.Mesh {
	mesh := mesh
	defer Procedural.Mesh_Destroy(&mesh)
	return Render.Mesh_Upload_Instanced(mesh, capacity)
}

BRANCHES :: 6
BRANCH_LENGTH_METERS :: 1.5

// Where branch i leaves the trunk and where it ends: spread around the trunk by the golden angle, rising and tilting out ~50 degrees.
@(private = "file")
branch_ends :: proc(index: int) -> (base, tip: [3]f32) {
	around := f32(index) * 2.3999632
	height := 2.3 + 0.35 * f32(index)
	tilt := math.to_radians(f32(50) - 4 * f32(index))
	direction := [3]f32{math.sin(tilt) * math.cos(around), math.cos(tilt), math.sin(tilt) * math.sin(around)}
	base = {0, height, 0}
	return base, base + direction * (BRANCH_LENGTH_METERS - 0.12 * f32(index))
}

// A tapering trunk 4 m tall with six branches reaching out and up from it, standing on y = 0.
@(private = "file")
tree_trunk_mesh :: proc() -> (tree: Procedural.Mesh) {
	trunk := Procedural.Cylinder_Create(0.22, 4.4, 10, 6)
	Procedural.Mesh_Deform(&trunk, {Procedural.Taper{1, 0.4}, Procedural.Noise_Displace{0.05, 2.5, 2, 3}})
	Procedural.Mesh_Append(&tree, trunk, la.matrix4_translate_f32({0, 2.2, 0}))
	Procedural.Mesh_Destroy(&trunk)
	for index in 0 ..< BRANCHES {
		base, tip := branch_ends(index)
		span := tip - base
		length := la.length(span)
		branch := Procedural.Cylinder_Create(0.075, length, 6, 2)
		Procedural.Mesh_Deform(&branch, {Procedural.Taper{1, 0.35}, Procedural.Noise_Displace{0.02, 3, 2, u32(60 + index)}})
		axis := span / length
		reference: [3]f32 = {1, 0, 0} if abs(axis.x) < 0.9 else {0, 0, 1}
		side := la.normalize(la.cross(axis, reference))
		forward := la.cross(side, axis)
		frame := matrix[4, 4]f32{
			side.x, axis.x, forward.x, base.x + span.x / 2,
			side.y, axis.y, forward.y, base.y + span.y / 2,
			side.z, axis.z, forward.z, base.z + span.z / 2,
			0, 0, 0, 1,
		}
		Procedural.Mesh_Append(&tree, branch, frame)
		Procedural.Mesh_Destroy(&branch)
	}
	return tree
}

// Foliage clumps sit on the branch tips (plus one on top), so the crown follows the branching instead of being a ball.
@(private = "file")
tree_canopy_mesh :: proc() -> (canopy: Procedural.Mesh) {
	for index in 0 ..< BRANCHES {
		_, tip := branch_ends(index)
		radius := 0.95 - 0.04 * f32(index)
		blob := Procedural.Sphere_Create(radius, 14, 7)
		Procedural.Mesh_Deform(&blob, {Procedural.Noise_Displace{radius * 0.32, 2.6 / radius, 4, u32(11 + index)}})
		Procedural.Mesh_Append(&canopy, blob, la.matrix4_translate_f32(tip + {0, radius * 0.3, 0}) * la.matrix4_scale_f32({1.1, 0.85, 1.1}))
		Procedural.Mesh_Destroy(&blob)
	}
	top := Procedural.Sphere_Create(1.0, 14, 7)
	Procedural.Mesh_Deform(&top, {Procedural.Noise_Displace{0.3, 2.6, 4, 19}})
	Procedural.Mesh_Append(&canopy, top, la.matrix4_translate_f32({0, 5.0, 0}) * la.matrix4_scale_f32({1, 0.9, 1}))
	Procedural.Mesh_Destroy(&top)
	return canopy
}

@(private = "file")
rock_mesh :: proc() -> Procedural.Mesh {
	rock := Procedural.Sphere_Create(0.9, 20, 10)
	Procedural.Mesh_Deform(&rock, {Procedural.Noise_Displace{0.3, 1.5, 3, 21}})
	return placed(rock, {0, 0.25, 0}, {1.2, 0.7, 1})
}

// A shrub is a cluster of five small lumpy clumps at different heights rather than one smooth mound.
@(private = "file")
bush_mesh :: proc() -> (bush: Procedural.Mesh) {
	clumps := [?]struct {
		position: [3]f32,
		radius:   f32,
	}{{{0, 0.3, 0}, 0.38}, {{0.35, 0.22, 0.1}, 0.28}, {{-0.3, 0.25, -0.12}, 0.3}, {{0.05, 0.52, -0.08}, 0.24}, {{-0.05, 0.2, 0.35}, 0.25}}
	for clump, index in clumps {
		blob := Procedural.Sphere_Create(clump.radius, 10, 5)
		Procedural.Mesh_Deform(&blob, {Procedural.Noise_Displace{clump.radius * 0.18, 2.5 / clump.radius, 2, u32(31 + index)}})
		Procedural.Mesh_Append(&bush, blob, la.matrix4_translate_f32(clump.position) * la.matrix4_scale_f32({1.15, 0.9, 1.15}))
		Procedural.Mesh_Destroy(&blob)
	}
	return bush
}

@(private = "file")
placed :: proc(mesh: Procedural.Mesh, offset, scale: [3]f32) -> (result: Procedural.Mesh) {
	mesh := mesh
	defer Procedural.Mesh_Destroy(&mesh)
	Procedural.Mesh_Append(&result, mesh, la.matrix4_translate_f32(offset) * la.matrix4_scale_f32(scale))
	return result
}

// A tuft of eleven blades fanned out from one root, each a thin four-sided spike leaning outward and bent by a noise displacement,
// so no two directions look alike. Blades are pointed (a blade is a taper to nothing) and about 0.25-0.55 m tall.
@(private = "file")
grass_tuft_mesh :: proc() -> (tuft: Procedural.Mesh) {
	BLADES :: 11
	for index in 0 ..< BLADES {
		hash := Procedural.Hash_U32(u32(index) * 2654435761 + 17)
		around := f32(index) / BLADES * 2 * math.PI + Procedural.Hash_To_Unit_Float(hash) * 0.5
		lean := 0.3 + 0.6 * Procedural.Hash_To_Unit_Float(Procedural.Hash_U32(hash ~ 1))
		height := 0.14 + 0.2 * Procedural.Hash_To_Unit_Float(Procedural.Hash_U32(hash ~ 2))
		blade := Procedural.Cone_Create(0.011, height, 4)
		Procedural.Mesh_Deform(&blade, {Procedural.Bend{lean * 5.0}})
		root := [3]f32{math.cos(around), 0, math.sin(around)} * (0.03 + 0.1 * Procedural.Hash_To_Unit_Float(Procedural.Hash_U32(hash ~ 3)))
		turn := la.matrix4_rotate_f32(-around + math.PI / 2, {0, 1, 0})
		Procedural.Mesh_Append(&tuft, blade, la.matrix4_translate_f32(root + {0, height / 2, 0}) * turn)
		Procedural.Mesh_Destroy(&blade)
	}
	return tuft
}
