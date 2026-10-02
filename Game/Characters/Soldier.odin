package Characters

import "../../Engine/Procedural"
import "../Materials"
import "../Weapons"
import "core:math"
import la "core:math/linalg"

Soldier_Variant :: enum {
	Rifleman,
	Officer,
	Sniper,
	Guard,
	Enemy,
}

// Body parts, each a mesh authored along +Y from its proximal joint (the foot along +Z from the ankle).
Segment :: enum {
	Torso,
	Head,
	Upper_Arm_Left,
	Upper_Arm_Right,
	Forearm_Left,
	Forearm_Right,
	Thigh_Left,
	Thigh_Right,
	Shin_Left,
	Shin_Right,
	Foot_Left,
	Foot_Right,
}

Headgear :: enum {
	Helmet,
	Cap,
	Hood,
}

// What a variant wears: materials for each garment, and which pieces it has.
Palette :: struct {
	uniform:         Materials.Surface_Material,
	vest:            Materials.Surface_Material,
	headgear_style:  Headgear,
	headgear:        Materials.Surface_Material,
	backpack:        Materials.Surface_Material,
	gloves:          Materials.Surface_Material,
	boots:           Materials.Surface_Material,
	has_vest:        bool,
	has_backpack:    bool,
	has_goggles:     bool,
	ghillie:         bool, // Lumpy camouflage cover on the shoulders and back.
}

palette_for :: proc(variant: Soldier_Variant) -> Palette {
	switch variant {
	case .Rifleman: return Palette{.Woodland_Camo, .Canvas, .Helmet, .Olive_Paint, .Canvas, .Rubber, .Rubber, true, true, true, false}
	case .Officer: return Palette{.Fabric_Desert, .Fabric_Desert, .Cap, .Fabric_Dark, .Fabric_Desert, .Skin, .Rubber, false, false, false, false}
	case .Sniper: return Palette{.Woodland_Camo, .Woodland_Camo, .Hood, .Woodland_Camo, .Fabric_Dark, .Fabric_Dark, .Rubber, false, true, false, true}
	case .Guard: return Palette{.Canvas, .Rubber, .Helmet, .Painted_Metal, .Canvas, .Rubber, .Rubber, true, false, true, false}
	case .Enemy: return Palette{.Fabric_Dark, .Rubber, .Hood, .Rubber, .Fabric_Dark, .Rubber, .Rubber, true, true, false, false}
	}
	unreachable()
}

Soldier_Weapon :: proc(variant: Soldier_Variant) -> Weapons.Weapon_Kind {
	switch variant {
	case .Rifleman, .Guard, .Enemy: return .Rifle
	case .Officer: return .Pistol
	case .Sniper: return .Sniper_Rifle
	}
	unreachable()
}

Soldier_Segment_Assembly :: proc(variant: Soldier_Variant, segment: Segment) -> Procedural.Assembly {
	palette := palette_for(variant)
	parts: [dynamic]Procedural.Part
	defer delete(parts)
	switch segment {
	case .Torso: torso_parts(&parts, palette)
	case .Head: head_parts(&parts, palette)
	case .Upper_Arm_Left, .Upper_Arm_Right: add(&parts, Procedural.Capsule(0.047, 0.2, 12, 5), {0, 0.15, 0}, palette.uniform)
	case .Forearm_Left, .Forearm_Right: forearm_parts(&parts, palette)
	case .Thigh_Left, .Thigh_Right: add(&parts, Procedural.Capsule(0.075, 0.3, 12, 5), {0, 0.225, 0}, palette.uniform)
	case .Shin_Left, .Shin_Right: shin_parts(&parts, palette)
	case .Foot_Left, .Foot_Right: foot_parts(&parts, palette)
	}
	return Procedural.Assembly_Build(parts[:])
}

@(private = "file")
Parts :: [dynamic]Procedural.Part

@(private = "file")
add :: proc(parts: ^Parts, primitive: Procedural.Primitive, position: [3]f32, material: Materials.Surface_Material, stretch := [3]f32{}, deformers := [Procedural.PART_DEFORMERS_MAX]Procedural.Deformer{}) {
	append(parts, Procedural.Part{primitive = primitive, position = position, stretch = stretch, deformers = deformers, material = i32(material)})
}

// Torso origin is the pelvis; +Y runs up the spine. The hips block, chest block and shoulder balls are the uniform;
// a vest, backpack and ghillie cover are layered on by the palette.
@(private = "file")
torso_parts :: proc(parts: ^Parts, palette: Palette) {
	add(parts, Procedural.Box({0.34, 0.16, 0.2}), {0, 0.04, 0}, palette.uniform)
	add(parts, Procedural.Box({0.38, 0.4, 0.21}, {2, 3, 2}), {0, 0.3, 0}, palette.uniform)
	for x in ([2]f32{-SHOULDER_HALF_WIDTH_METERS, SHOULDER_HALF_WIDTH_METERS}) do add(parts, Procedural.Sphere(0.065, 12, 6), {x, 0.45, 0}, palette.uniform)
	if palette.has_vest {
		add(parts, Procedural.Box({0.41, 0.3, 0.25}), {0, 0.32, 0}, palette.vest)
		for x in ([3]f32{-0.1, 0, 0.1}) do add(parts, Procedural.Box({0.08, 0.1, 0.05}), {x, 0.22, 0.15}, palette.vest)
	}
	if palette.has_backpack do add(parts, Procedural.Box({0.32, 0.38, 0.16}), {0, 0.3, -0.19}, palette.backpack)
	if palette.ghillie do ghillie_parts(parts)
}

@(private = "file")
ghillie_parts :: proc(parts: ^Parts) {
	lumps := [?]struct {
		position: [3]f32,
		radius:   f32,
	}{{{-0.17, 0.47, -0.04}, 0.1}, {{0.17, 0.47, -0.04}, 0.1}, {{0, 0.34, -0.2}, 0.14}, {{-0.13, 0.2, -0.16}, 0.09}, {{0.13, 0.2, -0.16}, 0.09}}
	for lump, index in lumps {
		add(parts, Procedural.Sphere(lump.radius, 12, 6), lump.position, .Grass, {1, 1, 1}, {0 = Procedural.Noise_Displace{lump.radius * 0.35, 6, 2, u32(40 + index)}})
	}
}

// Head origin is the neck; the skull centre is 0.14 m up.
@(private = "file")
head_parts :: proc(parts: ^Parts, palette: Palette) {
	add(parts, Procedural.Cylinder(0.05, 0.1, 10), {0, 0.03, 0}, .Skin)
	add(parts, Procedural.Sphere(0.105, 16, 8), {0, 0.14, 0}, .Skin, {0.92, 1.08, 1})
	switch palette.headgear_style {
	case .Helmet: add(parts, Procedural.Sphere(0.125, 16, 8), {0, 0.175, 0}, palette.headgear, {1, 0.82, 1.1})
	case .Cap:
		add(parts, Procedural.Cylinder(0.115, 0.06, 16), {0, 0.22, 0}, palette.headgear)
		append(parts, Procedural.Part{primitive = Procedural.Box({0.18, 0.015, 0.07}), position = {0, 0.205, 0.12}, rotation_degrees = {10, 0, 0}, material = i32(palette.headgear)})
	case .Hood:
		add(parts, Procedural.Sphere(0.115, 16, 8), {0, 0.14, 0}, palette.headgear, {0.96, 1.12, 1.02}, {0 = Procedural.Noise_Displace{0.01, 12, 2, 7}})
		add(parts, Procedural.Box({0.13, 0.025, 0.02}), {0, 0.15, 0.105}, .Skin)
	}
	if palette.has_goggles do add(parts, Procedural.Box({0.16, 0.04, 0.03}), {0, 0.16, 0.115}, .Glass)
}

@(private = "file")
forearm_parts :: proc(parts: ^Parts, palette: Palette) {
	add(parts, Procedural.Capsule(0.04, 0.17, 12, 5), {0, 0.135, 0}, palette.uniform)
	add(parts, Procedural.Sphere(0.052, 10, 6), {0, 0.27, 0}, palette.gloves, {1, 1.2, 1})
}

@(private = "file")
shin_parts :: proc(parts: ^Parts, palette: Palette) {
	add(parts, Procedural.Capsule(0.06, 0.31, 12, 5), {0, 0.225, 0}, palette.uniform)
	add(parts, Procedural.Cylinder(0.066, 0.2, 12), {0, 0.36, 0}, palette.boots)
}

// Foot origin is the ankle, 0.08 m above the sole; +Z is the toe.
@(private = "file")
foot_parts :: proc(parts: ^Parts, palette: Palette) {
	add(parts, Procedural.Box({0.1, 0.08, 0.28}), {0, -0.04, 0.06}, palette.boots)
	add(parts, Procedural.Sphere(0.055, 8, 4), {0, -0.045, 0.2}, palette.boots, {1, 0.6, 1})
}

// The world matrix that places a segment's mesh on the posed skeleton.
Segment_Matrix :: proc(pose: Pose, segment: Segment) -> matrix[4, 4]f32 {
	forward := [3]f32{math.sin(pose.heading_radians), 0, math.cos(pose.heading_radians)}
	joints := pose.joints
	switch segment {
	case .Torso: return frame(joints[.Pelvis], joints[.Chest] - joints[.Pelvis], forward)
	case .Head: return frame(joints[.Neck], joints[.Head] - joints[.Neck], pose.aim_direction)
	case .Upper_Arm_Left: return frame(joints[.Shoulder_Left], joints[.Elbow_Left] - joints[.Shoulder_Left], forward)
	case .Upper_Arm_Right: return frame(joints[.Shoulder_Right], joints[.Elbow_Right] - joints[.Shoulder_Right], forward)
	case .Forearm_Left: return frame(joints[.Elbow_Left], joints[.Hand_Left] - joints[.Elbow_Left], forward)
	case .Forearm_Right: return frame(joints[.Elbow_Right], joints[.Hand_Right] - joints[.Elbow_Right], forward)
	case .Thigh_Left: return frame(joints[.Hip_Left], joints[.Knee_Left] - joints[.Hip_Left], forward)
	case .Thigh_Right: return frame(joints[.Hip_Right], joints[.Knee_Right] - joints[.Hip_Right], forward)
	case .Shin_Left: return frame(joints[.Knee_Left], joints[.Ankle_Left] - joints[.Knee_Left], forward)
	case .Shin_Right: return frame(joints[.Knee_Right], joints[.Ankle_Right] - joints[.Knee_Right], forward)
	case .Foot_Left: return la.matrix4_translate_f32(joints[.Ankle_Left]) * la.matrix4_rotate_f32(pose.heading_radians, {0, 1, 0})
	case .Foot_Right: return la.matrix4_translate_f32(joints[.Ankle_Right]) * la.matrix4_rotate_f32(pose.heading_radians, {0, 1, 0})
	}
	unreachable()
}

// The weapon's grip sits in the right hand with its muzzle along the aim direction and its sights up.
Weapon_Matrix :: proc(pose: Pose) -> matrix[4, 4]f32 {
	aim := pose.aim_direction
	up := [3]f32{0, 1, 0}
	sights := la.normalize(up - aim * la.dot(up, aim))
	right_axis := la.cross(sights, aim)
	hand := pose.joints[.Hand_Right]
	return matrix[4, 4]f32{
		right_axis.x, sights.x, aim.x, hand.x,
		right_axis.y, sights.y, aim.y, hand.y,
		right_axis.z, sights.z, aim.z, hand.z,
		0, 0, 0, 1,
	}
}

// Every segment (and optionally the weapon) merged into one mesh at a pose, for measuring or debugging.
Soldier_Mesh_At_Pose :: proc(variant: Soldier_Variant, pose: Pose, include_weapon: bool) -> (mesh: Procedural.Mesh) {
	for segment in Segment {
		assembly := Soldier_Segment_Assembly(variant, segment)
		defer Procedural.Assembly_Destroy(&assembly)
		for group in assembly.groups do Procedural.Mesh_Append(&mesh, group.mesh, Segment_Matrix(pose, segment))
	}
	if include_weapon {
		assembly := Weapons.Weapon_Build(Soldier_Weapon(variant))
		defer Procedural.Assembly_Destroy(&assembly)
		for group in assembly.groups do Procedural.Mesh_Append(&mesh, group.mesh, Weapon_Matrix(pose))
	}
	return mesh
}

// A rigid frame at origin with +Y along y_axis and +Z as close to forward_hint as the perpendicularity allows.
@(private = "file")
frame :: proc(origin, y_axis, forward_hint: [3]f32) -> matrix[4, 4]f32 {
	y := la.normalize(y_axis)
	z := forward_hint - y * la.dot(forward_hint, y)
	if la.length(z) < 1e-4 do z = la.cross(y, [3]f32{1, 0, 0} if abs(y.x) < 0.9 else [3]f32{0, 1, 0})
	z = la.normalize(z)
	x := la.cross(y, z)
	return matrix[4, 4]f32{
		x.x, y.x, z.x, origin.x,
		x.y, y.y, z.y, origin.y,
		x.z, y.z, z.z, origin.z,
		0, 0, 0, 1,
	}
}
