package Procedural

import "core:math"
import la "core:math/linalg"

Box_Spec :: struct {
	size:     [3]f32,
	segments: [3]int,
}

Sphere_Spec :: struct {
	radius:   f32,
	segments: int,
	rings:    int,
}

Cylinder_Spec :: struct {
	radius:          f32,
	height:          f32,
	segments:        int,
	height_segments: int,
}

Cone_Spec :: struct {
	radius:   f32,
	height:   f32,
	segments: int,
}

Capsule_Spec :: struct {
	radius:         f32,
	shaft_height:   f32,
	segments:       int,
	rings:          int,
	shaft_segments: int,
}

Torus_Spec :: struct {
	radius_major:   f32,
	radius_minor:   f32,
	segments_major: int,
	segments_minor: int,
}

Wedge_Spec :: struct {
	size: [3]f32,
}

Primitive :: union {
	Box_Spec,
	Sphere_Spec,
	Cylinder_Spec,
	Cone_Spec,
	Capsule_Spec,
	Torus_Spec,
	Wedge_Spec,
}

Box :: proc(size: [3]f32, segments := [3]int{1, 1, 1}) -> Primitive {
	return Box_Spec{size, segments}
}

Sphere :: proc(radius: f32, segments := 16, rings := 8) -> Primitive {
	return Sphere_Spec{radius, segments, rings}
}

Cylinder :: proc(radius, height: f32, segments := 16, height_segments := 1) -> Primitive {
	return Cylinder_Spec{radius, height, segments, height_segments}
}

Cone :: proc(radius, height: f32, segments := 16) -> Primitive {
	return Cone_Spec{radius, height, segments}
}

Capsule :: proc(radius, shaft_height: f32, segments := 16, rings := 6, shaft_segments := 1) -> Primitive {
	return Capsule_Spec{radius, shaft_height, segments, rings, shaft_segments}
}

Torus :: proc(radius_major, radius_minor: f32, segments_major := 24, segments_minor := 8) -> Primitive {
	return Torus_Spec{radius_major, radius_minor, segments_major, segments_minor}
}

Wedge :: proc(size: [3]f32) -> Primitive {
	return Wedge_Spec{size}
}

PART_DEFORMERS_MAX :: 3

// One building block of an object: a primitive, deformed in its own space, stretched, rotated (about X, then Y, then Z), moved.
Part :: struct {
	primitive:        Primitive,
	position:         [3]f32,
	rotation_degrees: [3]f32,
	stretch:          [3]f32, // Per-axis scale after deformers; a zero component means 1, so most parts leave it unset.
	deformers:        [PART_DEFORMERS_MAX]Deformer, // Stored inline (a slice literal would dangle once the table's proc returns); unused entries are nil.
	material:         i32, // Layer in the baked material arrays.
	emission:         [3]f32, // Linear radiance the part gives off (lit windows, lamps).
	solid:            bool, // Contributes a collision box.
	collision_only:   bool, // The collision box only: nothing is drawn. For thin things whose wires or bars a body must not pass between.
}

Collision_Box :: struct {
	lowest:  [3]f32,
	highest: [3]f32,
}

// Parts sharing a material and emission become one mesh, so an object costs one draw per material, not per part.
Assembly_Group :: struct {
	material: i32,
	emission: [3]f32,
	mesh:     Mesh,
}

Assembly :: struct {
	groups:          [dynamic]Assembly_Group,
	collision_boxes: [dynamic]Collision_Box,
}

Assembly_Build :: proc(parts: []Part) -> (assembly: Assembly) {
	for part in parts {
		mesh := primitive_mesh(part.primitive)
		defer Mesh_Destroy(&mesh)
		deformers := part.deformers
		for deformer, index in deformers {
			if deformer == nil do continue
			Mesh_Deform(&mesh, deformers[index:index + 1])
		}
		transform := part_transform(part)
		if !part.collision_only do Mesh_Append(&group_for(&assembly, part.material, part.emission).mesh, mesh, transform)
		if part.solid || part.collision_only do append(&assembly.collision_boxes, transformed_bounds(mesh, transform))
	}
	return assembly
}

Assembly_Destroy :: proc(assembly: ^Assembly) {
	for &group in assembly.groups do Mesh_Destroy(&group.mesh)
	delete(assembly.groups)
	delete(assembly.collision_boxes)
	assembly^ = {}
}

Assembly_Bounds :: proc(assembly: Assembly) -> (lowest, highest: [3]f32) {
	assert(len(assembly.groups) > 0, "Assembly_Bounds: empty assembly")
	lowest, highest = Mesh_Bounds(assembly.groups[0].mesh)
	for group in assembly.groups[1:] {
		group_lowest, group_highest := Mesh_Bounds(group.mesh)
		lowest = {min(lowest.x, group_lowest.x), min(lowest.y, group_lowest.y), min(lowest.z, group_lowest.z)}
		highest = {max(highest.x, group_highest.x), max(highest.y, group_highest.y), max(highest.z, group_highest.z)}
	}
	return
}

@(private = "file")
group_for :: proc(assembly: ^Assembly, material: i32, emission: [3]f32) -> ^Assembly_Group {
	for &group in assembly.groups {
		if group.material == material && group.emission == emission do return &group
	}
	append(&assembly.groups, Assembly_Group{material = material, emission = emission})
	return &assembly.groups[len(assembly.groups) - 1]
}

@(private = "file")
part_transform :: proc(part: Part) -> matrix[4, 4]f32 {
	stretch := part.stretch
	for &component in stretch do if component == 0 do component = 1
	rotation := la.matrix4_rotate_f32(math.to_radians(part.rotation_degrees.z), {0, 0, 1}) * la.matrix4_rotate_f32(math.to_radians(part.rotation_degrees.y), {0, 1, 0}) * la.matrix4_rotate_f32(math.to_radians(part.rotation_degrees.x), {1, 0, 0})
	return la.matrix4_translate_f32(part.position) * rotation * la.matrix4_scale_f32(stretch)
}

@(private = "file")
transformed_bounds :: proc(mesh: Mesh, transform: matrix[4, 4]f32) -> Collision_Box {
	transformed: Mesh
	defer Mesh_Destroy(&transformed)
	Mesh_Append(&transformed, mesh, transform)
	lowest, highest := Mesh_Bounds(transformed)
	return Collision_Box{lowest, highest}
}

@(private = "file")
primitive_mesh :: proc(primitive: Primitive) -> Mesh {
	switch spec in primitive {
	case Box_Spec: return Box_Create(spec.size, spec.segments)
	case Sphere_Spec: return Sphere_Create(spec.radius, spec.segments, spec.rings)
	case Cylinder_Spec: return Cylinder_Create(spec.radius, spec.height, spec.segments, spec.height_segments)
	case Cone_Spec: return Cone_Create(spec.radius, spec.height, spec.segments)
	case Capsule_Spec: return Capsule_Create(spec.radius, spec.shaft_height, spec.segments, spec.rings, spec.shaft_segments)
	case Torus_Spec: return Torus_Create(spec.radius_major, spec.radius_minor, spec.segments_major, spec.segments_minor)
	case Wedge_Spec: return Wedge_Create(spec.size)
	}
	panic("primitive_mesh: part has no primitive")
}
