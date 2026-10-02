package Sandbox

import "../../Engine/Procedural"
import "../../Engine/Render"
import la "core:math/linalg"

TREE_CAPACITY :: 6000
ROCK_CAPACITY :: 4000
BUSH_CAPACITY :: 8000

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

// A tapering trunk 4 m tall, standing on y = 0.
@(private = "file")
tree_trunk_mesh :: proc() -> Procedural.Mesh {
	trunk := Procedural.Cylinder_Create(0.22, 4, 10, 6)
	Procedural.Mesh_Deform(&trunk, {Procedural.Taper{1, 0.55}, Procedural.Noise_Displace{0.04, 2.5, 2, 3}})
	return placed(trunk, {0, 2, 0}, {1, 1, 1})
}

// Two overlapping lumpy blobs make a canopy that reads as foliage without any leaf geometry.
@(private = "file")
tree_canopy_mesh :: proc() -> (canopy: Procedural.Mesh) {
	lobes := [?]struct {
		position: [3]f32,
		radius:   f32,
		seed:     u32,
	}{{{0, 5.2, 0}, 1.5, 11}, {{0.9, 4.4, 0.5}, 1.05, 12}, {{-0.8, 4.7, -0.6}, 1.1, 13}, {{-0.3, 6.1, 0.3}, 1.0, 14}, {{0.6, 5.6, -0.7}, 0.9, 15}, {{-1.0, 5.6, 0.7}, 0.85, 16}}
	for lobe in lobes {
		blob := Procedural.Sphere_Create(lobe.radius, 24, 12)
		Procedural.Mesh_Deform(&blob, {Procedural.Noise_Displace{lobe.radius * 0.3, 2.6 / lobe.radius, 4, lobe.seed}})
		Procedural.Mesh_Append(&canopy, blob, la.matrix4_translate_f32(lobe.position) * la.matrix4_scale_f32({1, 1.25, 1}))
		Procedural.Mesh_Destroy(&blob)
	}
	return canopy
}

@(private = "file")
rock_mesh :: proc() -> Procedural.Mesh {
	rock := Procedural.Sphere_Create(0.9, 20, 10)
	Procedural.Mesh_Deform(&rock, {Procedural.Noise_Displace{0.3, 1.5, 3, 21}})
	return placed(rock, {0, 0.25, 0}, {1.2, 0.7, 1})
}

@(private = "file")
bush_mesh :: proc() -> Procedural.Mesh {
	bush := Procedural.Sphere_Create(0.7, 14, 7)
	Procedural.Mesh_Deform(&bush, {Procedural.Noise_Displace{0.14, 2.2, 2, 31}})
	return placed(bush, {0, 0.35, 0}, {1.3, 0.9, 1.3})
}

@(private = "file")
placed :: proc(mesh: Procedural.Mesh, offset, scale: [3]f32) -> (result: Procedural.Mesh) {
	mesh := mesh
	defer Procedural.Mesh_Destroy(&mesh)
	Procedural.Mesh_Append(&result, mesh, la.matrix4_translate_f32(offset) * la.matrix4_scale_f32(scale))
	return result
}
