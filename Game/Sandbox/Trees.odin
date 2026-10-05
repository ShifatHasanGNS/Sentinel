package Sandbox

import "../../Engine/Procedural"
import "../../Engine/Render"
import "../Materials"
import "core:math"
import la "core:math/linalg"

TREE_CAPACITY :: 3000 // Per species: a world of four species spreads the old single-species load.
TREE_DETAIL_DISTANCE_METERS :: 110.0
TRUNK_SWAY :: 0.6
FOLIAGE_SWAY :: 2.0 // Above 1, leaves flutter as well as lean (see Geometry.glsl: wind_offset).
GOLDEN_ANGLE_RADIANS :: 2.3999632

Tree_Species :: enum {
	Oak, // Broad crown on a short thick trunk.
	Pine, // Tall straight trunk, tiers of needle skirts.
	Birch, // Slender, leaning, pale bark, light narrow crown.
	Cypress, // A dark narrow column.
}

Tree_Spec :: struct {
	trunk_half_width_meters: f32,
	trunk_height_meters:     f32, // The solid part a player bumps into.
	bark:                    Materials.Surface_Material,
	foliage:                 Materials.Surface_Material,
}

@(rodata)
TREE_SPECS := [Tree_Species]Tree_Spec{
	.Oak     = {0.3, 4.0, .Bark, .Leaves},
	.Pine    = {0.22, 6.0, .Bark, .Needles},
	.Birch   = {0.12, 5.0, .Birch_Bark, .Leaves},
	.Cypress = {0.17, 4.0, .Bark, .Needles},
}

// Near and far detail for the camera, plus a crude silhouette for the shadow pass, all drawing the same instances.
Tree_Meshes :: struct {
	trunk:         Render.Mesh,
	canopy:        Render.Mesh,
	far_trunk:     Render.Mesh,
	far_canopy:    Render.Mesh,
	trunk_shadow:  Render.Mesh,
	canopy_shadow: Render.Mesh,
}

Tree_Instances :: struct {
	trunk:      [dynamic]Render.Instance,
	canopy:     [dynamic]Render.Instance,
	far_trunk:  [dynamic]Render.Instance,
	far_canopy: [dynamic]Render.Instance,
}

// A branch from base to tip, and a lump of foliage: the whole content of a tree is two short tables of these.
@(private = "file")
Limb :: struct {
	base, tip:     [3]f32,
	radius_meters: f32,
}

@(private = "file")
Lump :: struct {
	center:        [3]f32,
	radius_meters: f32,
	stretch:       [3]f32,
}

Trees_Create :: proc() -> (trees: [Tree_Species]Tree_Meshes) {
	trees[.Oak] = tree_meshes(oak_trunk(), oak_canopy(), 0.3, 4.4, oak_far_lumps(), {2.6, 0.9}, {0, 5.4, 0})
	trees[.Pine] = tree_meshes(pine_trunk(), pine_canopy(), 0.22, 9, pine_far_lumps(), {1.7, 2.2}, {0, 5.5, 0})
	trees[.Birch] = tree_meshes(birch_trunk(), birch_canopy(), 0.12, 6.4, birch_far_lumps(), {1.3, 1.5}, {0, 5.0, 0})
	trees[.Cypress] = tree_meshes(cypress_trunk(), cypress_canopy(), 0.17, 3, cypress_far_lumps(), {1.1, 4.2}, {0, 5.6, 0})
	return trees
}

Trees_Destroy :: proc(trees: ^[Tree_Species]Tree_Meshes) {
	for &meshes in trees {
		Render.Mesh_Destroy(&meshes.trunk_shadow)
		Render.Mesh_Destroy(&meshes.canopy_shadow)
		Render.Mesh_Destroy(&meshes.trunk)
		Render.Mesh_Destroy(&meshes.canopy)
		Render.Mesh_Destroy(&meshes.far_trunk)
		Render.Mesh_Destroy(&meshes.far_canopy)
	}
}

Tree_Instances_Destroy :: proc(instances: ^[Tree_Species]Tree_Instances) {
	for &species in instances {
		delete(species.trunk)
		delete(species.canopy)
		delete(species.far_trunk)
		delete(species.far_canopy)
	}
}

Tree_Instances_Clear :: proc(instances: ^[Tree_Species]Tree_Instances) {
	for &species in instances {
		clear(&species.trunk)
		clear(&species.canopy)
		clear(&species.far_trunk)
		clear(&species.far_canopy)
	}
}

Tree_Instances_Upload :: proc(trees: ^[Tree_Species]Tree_Meshes, instances: ^[Tree_Species]Tree_Instances) {
	for species in Tree_Species {
		meshes, listed := &trees[species], &instances[species]
		Render.Mesh_Set_Instances(&meshes.trunk, listed.trunk[:min(len(listed.trunk), TREE_CAPACITY)])
		Render.Mesh_Set_Instances(&meshes.canopy, listed.canopy[:min(len(listed.canopy), TREE_CAPACITY)])
		Render.Mesh_Set_Instances(&meshes.far_trunk, listed.far_trunk[:min(len(listed.far_trunk), TREE_CAPACITY)])
		Render.Mesh_Set_Instances(&meshes.far_canopy, listed.far_canopy[:min(len(listed.far_canopy), TREE_CAPACITY)])
	}
}

// Draw items for the camera (every mesh, near and far) and for the shadow pass (the proxies).
Tree_Items :: proc(trees: ^[Tree_Species]Tree_Meshes, items, shadow_items: ^[dynamic]Render.Draw_Item) {
	for species in Tree_Species {
		meshes := &trees[species]
		append(items, tree_item(&meshes.trunk, .Cook_Torrance), tree_item(&meshes.canopy, .Oren_Nayar), tree_item(&meshes.far_trunk, .Cook_Torrance), tree_item(&meshes.far_canopy, .Oren_Nayar))
		append(shadow_items, shadow_item(&meshes.trunk_shadow), shadow_item(&meshes.canopy_shadow))
	}
}

@(private = "file")
tree_item :: proc(mesh: ^Render.Mesh, model: Render.Illumination_Model) -> Render.Draw_Item {
	return Render.Draw_Item{mesh = mesh, model = la.MATRIX4F32_IDENTITY, uv_scale = {1, 1}, triplanar = true, illumination_model = model}
}

@(private = "file")
shadow_item :: proc(mesh: ^Render.Mesh) -> Render.Draw_Item {
	return Render.Draw_Item{mesh = mesh, model = la.MATRIX4F32_IDENTITY}
}

Tree_Species_Of :: proc(variant: f32) -> Tree_Species {
	return Tree_Species(clamp(int(variant / TREE_VARIANT_LIMIT * f32(len(Tree_Species))), 0, len(Tree_Species) - 1))
}

// One stable roll in [0, 1) per (tree, purpose): a tree's height, width, lean and tint never change between frames.
@(private = "file")
tree_roll :: proc(point: Procedural.Scatter_Point, salt: u32) -> f32 {
	return Procedural.Hash_To_Unit_Float(Procedural.Hash_U32(transmute(u32)point.variant ~ (salt * 0x9E3779B9)))
}

// A tree stands upright-ish on its spot: taller or stockier than its neighbours, leaning a few degrees, tinted its own green.
Tree_Place :: proc(instances: ^[Tree_Species]Tree_Instances, point: Procedural.Scatter_Point, camera_position: [3]f32) {
	species := Tree_Species_Of(point.variant)
	spec, listed := TREE_SPECS[species], &instances[species]
	height_scale := point.scale * math.lerp(f32(0.85), f32(1.3), tree_roll(point, 1))
	width_scale := point.scale * math.lerp(f32(0.8), f32(1.25), tree_roll(point, 2))
	lean_x, lean_z := (tree_roll(point, 3) - 0.5) * 0.09, (tree_roll(point, 4) - 0.5) * 0.09
	model := la.matrix4_translate_f32(point.position) * la.matrix4_rotate_f32(point.yaw_radians, {0, 1, 0}) * la.matrix4_rotate_f32(lean_x, {1, 0, 0}) * la.matrix4_rotate_f32(lean_z, {0, 0, 1}) * la.matrix4_scale_f32({width_scale, height_scale, width_scale})
	foliage_tint := tree_roll(point, 5) * 2 - 1
	bark_tint := (tree_roll(point, 6) * 2 - 1) * 0.5
	trunk := Render.Instance{model = model, material_layer = f32(spec.bark), tint = bark_tint, sway = TRUNK_SWAY}
	canopy := Render.Instance{model = model, material_layer = f32(spec.foliage), tint = foliage_tint, sway = FOLIAGE_SWAY}
	if la.length(point.position - camera_position) > TREE_DETAIL_DISTANCE_METERS {
		append(&listed.far_trunk, trunk)
		append(&listed.far_canopy, canopy)
		return
	}
	append(&listed.trunk, trunk)
	append(&listed.canopy, canopy)
}

Tree_Solid_For :: proc(point: Procedural.Scatter_Point) -> (half_width_meters, height_meters: f32) {
	spec := TREE_SPECS[Tree_Species_Of(point.variant)]
	return spec.trunk_half_width_meters * point.scale, spec.trunk_height_meters * point.scale
}

@(private = "file")
tree_meshes :: proc(trunk, canopy: Procedural.Mesh, far_trunk_radius, far_trunk_height: f32, far_lumps: []Lump, shadow_canopy: [2]f32, shadow_center: [3]f32) -> (meshes: Tree_Meshes) {
	meshes.trunk = upload_prop(trunk, TREE_CAPACITY)
	meshes.canopy = upload_prop(canopy, TREE_CAPACITY)
	meshes.far_trunk = upload_prop(placed(Procedural.Cylinder_Create(far_trunk_radius, far_trunk_height, 5, 1), {0, far_trunk_height / 2, 0}, {1, 1, 1}), TREE_CAPACITY)
	meshes.far_canopy = upload_prop(lumps_mesh(far_lumps, 8, 4, 0.2, 70), TREE_CAPACITY)
	meshes.trunk_shadow = upload_shadow_proxy(placed(Procedural.Cylinder_Create(far_trunk_radius, far_trunk_height, 5, 1), {0, far_trunk_height / 2, 0}, {1, 1, 1}), &meshes.trunk)
	meshes.canopy_shadow = upload_shadow_proxy(placed(Procedural.Sphere_Create(shadow_canopy.x, 8, 4), shadow_center, {1, shadow_canopy.y, 1}), &meshes.canopy)
	return meshes
}

// A limb is a tapering cylinder from base to tip; its frame is built from the branch axis.
@(private = "file")
limbs_mesh :: proc(limbs: []Limb, seed: u32) -> (mesh: Procedural.Mesh) {
	for limb, index in limbs {
		span := limb.tip - limb.base
		length := la.length(span)
		piece := Procedural.Cylinder_Create(limb.radius_meters, length, 6, 3)
		Procedural.Mesh_Deform(&piece, {Procedural.Taper{1, 0.35}, Procedural.Noise_Displace{limb.radius_meters * 0.3, 3, 2, seed + u32(index)}})
		axis := span / length
		reference: [3]f32 = {1, 0, 0} if abs(axis.x) < 0.9 else {0, 0, 1}
		side := la.normalize(la.cross(axis, reference))
		forward := la.cross(side, axis)
		middle := limb.base + span / 2
		frame := matrix[4, 4]f32{
			side.x, axis.x, forward.x, middle.x,
			side.y, axis.y, forward.y, middle.y,
			side.z, axis.z, forward.z, middle.z,
			0, 0, 0, 1,
		}
		Procedural.Mesh_Append(&mesh, piece, frame)
		Procedural.Mesh_Destroy(&piece)
	}
	return mesh
}

// Foliage lumps: noise-displaced spheres, stretched as the species wants, so a crown is a cluster of masses and not a ball.
@(private = "file")
lumps_mesh :: proc(lumps: []Lump, segments, rings: int, roughness: f32, seed: u32) -> (mesh: Procedural.Mesh) {
	for lump, index in lumps {
		blob := Procedural.Sphere_Create(lump.radius_meters, segments, rings)
		Procedural.Mesh_Deform(&blob, {Procedural.Noise_Displace{lump.radius_meters * roughness, 2.4 / lump.radius_meters, 4, seed + u32(index)}})
		Procedural.Mesh_Append(&mesh, blob, la.matrix4_translate_f32(lump.center) * la.matrix4_scale_f32(lump.stretch))
		Procedural.Mesh_Destroy(&blob)
	}
	return mesh
}

@(private = "file")
trunk_piece :: proc(radius_meters, height_meters: f32, taper_top: f32, bend: f32, seed: u32, base_offset: [3]f32) -> (mesh: Procedural.Mesh) {
	trunk := Procedural.Cylinder_Create(radius_meters, height_meters, 10, 8)
	Procedural.Mesh_Deform(&trunk, {Procedural.Taper{1, taper_top}, Procedural.Bend{bend}, Procedural.Noise_Displace{radius_meters * 0.18, 2.5, 2, seed}})
	Procedural.Mesh_Append(&mesh, trunk, la.matrix4_translate_f32(base_offset + {0, height_meters / 2, 0}))
	Procedural.Mesh_Destroy(&trunk)
	return mesh
}

// Where limb i leaves a trunk of the given height band and which way it points: around by the golden angle, tilted from vertical.
@(private = "file")
limb_ends :: proc(index: int, base_height, rise_per_limb, tilt_degrees, length: f32) -> (base, tip: [3]f32) {
	around := f32(index) * GOLDEN_ANGLE_RADIANS
	tilt := math.to_radians(tilt_degrees - 3 * f32(index % 3))
	direction := [3]f32{math.sin(tilt) * math.cos(around), math.cos(tilt), math.sin(tilt) * math.sin(around)}
	base = {0, base_height + rise_per_limb * f32(index), 0}
	return base, base + direction * length
}

// Oak: five main limbs, each forking once; a lump on every tip and one on top.
@(private = "file")
oak_limb_list :: proc() -> (limbs: [dynamic]Limb, lumps: [dynamic]Lump) {
	for index in 0 ..< 5 {
		base, tip := limb_ends(index, 2.5, 0.25, 40, 2.3)
		append(&limbs, Limb{base, tip, 0.14})
		append(&lumps, Lump{tip + {0, 0.5, 0}, 1.35, {1.15, 0.85, 1.15}})
		fork_base := base + (tip - base) * 0.62
		for side in 0 ..< 2 {
			sign := f32(side * 2 - 1)
			fork_direction := la.normalize([3]f32{math.cos(f32(index) * GOLDEN_ANGLE_RADIANS + sign * 0.9), 0.75, math.sin(f32(index) * GOLDEN_ANGLE_RADIANS + sign * 0.9)})
			fork_tip := fork_base + fork_direction * 1.3
			append(&limbs, Limb{fork_base, fork_tip, 0.08})
			append(&lumps, Lump{fork_tip + {0, 0.3, 0}, 0.95, {1.1, 0.85, 1.1}})
		}
	}
	append(&lumps, Lump{{0, 5.7, 0}, 1.5, {1.1, 0.9, 1.1}})
	return
}

@(private = "file")
oak_trunk :: proc() -> (mesh: Procedural.Mesh) {
	limbs, lumps := oak_limb_list()
	defer delete(limbs)
	defer delete(lumps)
	trunk := trunk_piece(0.3, 3.4, 0.55, 0, 3, {})
	flare := trunk_piece(0.55, 0.7, 0.55, 0, 5, {})
	branches := limbs_mesh(limbs[:], 60)
	Procedural.Mesh_Append(&mesh, trunk, la.MATRIX4F32_IDENTITY)
	Procedural.Mesh_Append(&mesh, flare, la.MATRIX4F32_IDENTITY)
	Procedural.Mesh_Append(&mesh, branches, la.MATRIX4F32_IDENTITY)
	Procedural.Mesh_Destroy(&trunk)
	Procedural.Mesh_Destroy(&flare)
	Procedural.Mesh_Destroy(&branches)
	return mesh
}

@(private = "file")
oak_canopy :: proc() -> Procedural.Mesh {
	limbs, lumps := oak_limb_list()
	defer delete(limbs)
	defer delete(lumps)
	return lumps_mesh(lumps[:], 12, 6, 0.32, 11)
}

@(private = "file")
oak_far_lumps :: proc() -> []Lump {
	@(static) lumps := [3]Lump{{{0, 5.2, 0}, 2.0, {1.3, 0.9, 1.3}}, {{1.4, 4.4, 0.6}, 1.4, {1.1, 0.9, 1.1}}, {{-1.3, 4.5, -0.8}, 1.4, {1.1, 0.9, 1.1}}}
	return lumps[:]
}

// Pine: a straight trunk and eight skirts of needles, widest low down, each a displaced cone.
@(private = "file")
pine_trunk :: proc() -> Procedural.Mesh {
	return trunk_piece(0.22, 9, 0.14, 0.01, 7, {})
}

@(private = "file")
pine_canopy :: proc() -> (mesh: Procedural.Mesh) {
	TIERS :: 11
	for tier in 0 ..< TIERS {
		fraction := f32(tier) / (TIERS - 1)
		radius := 2.1 * math.pow(1 - fraction, 0.85) + 0.4
		height := f32(2.4)
		skirt := Procedural.Cylinder_Create(radius, height, 14, 3)
		Procedural.Mesh_Deform(&skirt, {Procedural.Taper{1, 0.06}, Procedural.Noise_Displace{radius * 0.2, 1.8, 3, 80 + u32(tier)}})
		turn := la.matrix4_rotate_f32(f32(tier) * 0.7, {0, 1, 0})
		Procedural.Mesh_Append(&mesh, skirt, la.matrix4_translate_f32({0, 1.7 + fraction * 7.0, 0}) * turn)
		Procedural.Mesh_Destroy(&skirt)
	}
	return mesh
}

@(private = "file")
pine_far_lumps :: proc() -> []Lump {
	@(static) lumps := [3]Lump{{{0, 3.0, 0}, 1.7, {1, 1.0, 1}}, {{0, 5.4, 0}, 1.3, {1, 1.2, 1}}, {{0, 7.6, 0}, 0.8, {1, 1.5, 1}}}
	return lumps[:]
}

// Birch: a slender curved trunk, thin upswept limbs, small light lumps strung along them.
@(private = "file")
birch_limb_list :: proc() -> (limbs: [dynamic]Limb, lumps: [dynamic]Lump) {
	for index in 0 ..< 7 {
		base, tip := limb_ends(index, 2.6, 0.4, 28, 1.7)
		append(&limbs, Limb{base, tip, 0.05})
		append(&lumps, Lump{tip + {0, 0.5, 0}, 0.8, {1.0, 1.3, 1.0}})
		append(&lumps, Lump{base + (tip - base) * 0.55 + {0, 0.2, 0}, 0.62, {1.0, 1.25, 1.0}})
	}
	append(&lumps, Lump{{0, 6.2, 0}, 0.75, {1.0, 1.4, 1.0}})
	return
}

@(private = "file")
birch_trunk :: proc() -> (mesh: Procedural.Mesh) {
	limbs, lumps := birch_limb_list()
	defer delete(limbs)
	defer delete(lumps)
	trunk := trunk_piece(0.12, 6.4, 0.35, 0.03, 9, {})
	branches := limbs_mesh(limbs[:], 90)
	Procedural.Mesh_Append(&mesh, trunk, la.MATRIX4F32_IDENTITY)
	Procedural.Mesh_Append(&mesh, branches, la.MATRIX4F32_IDENTITY)
	Procedural.Mesh_Destroy(&trunk)
	Procedural.Mesh_Destroy(&branches)
	return mesh
}

@(private = "file")
birch_canopy :: proc() -> Procedural.Mesh {
	limbs, lumps := birch_limb_list()
	defer delete(limbs)
	defer delete(lumps)
	return lumps_mesh(lumps[:], 10, 5, 0.3, 21)
}

@(private = "file")
birch_far_lumps :: proc() -> []Lump {
	@(static) lumps := [2]Lump{{{0, 4.4, 0}, 1.2, {1, 1.5, 1}}, {{0.2, 6.0, 0}, 0.8, {1, 1.5, 1}}}
	return lumps[:]
}

// Cypress: six stacked ellipsoids make a dark column.
@(private = "file")
cypress_trunk :: proc() -> Procedural.Mesh {
	return trunk_piece(0.17, 3, 0.6, 0, 13, {})
}

@(private = "file")
cypress_canopy :: proc() -> Procedural.Mesh {
	@(static) radii := [6]f32{0.85, 1.05, 1.1, 1.0, 0.8, 0.5}
	lumps: [6]Lump
	for index in 0 ..< 6 do lumps[index] = Lump{{0, 2.6 + f32(index) * 1.3, 0}, radii[index], {1, 1.9, 1}}
	return lumps_mesh(lumps[:], 10, 6, 0.22, 31)
}

@(private = "file")
cypress_far_lumps :: proc() -> []Lump {
	@(static) lumps := [2]Lump{{{0, 4.4, 0}, 1.1, {1, 2.4, 1}}, {{0, 7.6, 0}, 0.7, {1, 2.2, 1}}}
	return lumps[:]
}
