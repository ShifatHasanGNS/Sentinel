package Catalogue

import "../Materials"

// Ground surfacing: laid flat on the plateau (a few centimetres high, never solid), so people and vehicles drive straight over it.
// Different thicknesses keep overlapping pieces from fighting for the same depth: apron < plaza < road < painted lines.
PAVING :: bit_set[Object_Kind]{.Road, .Parade_Ground, .Walkway, .Apron, .Lawn}

@(private = "file")
slab :: proc(parts: ^Parts, width, thickness, length: f32, x, z: f32, material: Materials.Surface_Material) {
	add_box(parts, {width, thickness, length}, {x, thickness / 2, z}, material, false)
}

// A 6 m wide two-lane road, 16 m long along Z: asphalt, painted edge lines and a dashed centre line.
@(private = "package")
road :: proc() -> (parts: Parts) {
	slab(&parts, 6, 0.05, 16, 0, 0, .Asphalt)
	for side in ([2]f32{-2.6, 2.6}) do slab(&parts, 0.16, 0.056, 16, side, 0, .Concrete)
	for z in ([4]f32{-6, -2, 2, 6}) do slab(&parts, 0.16, 0.056, 1.8, 0, z, .Concrete)
	return parts
}

// A parade ground: a dark asphalt field inside a pale concrete border, with a painted square and a centre cross.
@(private = "package")
parade_ground :: proc() -> (parts: Parts) {
	slab(&parts, 24, 0.04, 14, 0, 0, .Concrete)
	slab(&parts, 22, 0.05, 12, 0, 0, .Asphalt)
	for z in ([2]f32{-4, 4}) do slab(&parts, 18, 0.056, 0.14, 0, z, .Concrete)
	for x in ([2]f32{-9, 9}) do slab(&parts, 0.14, 0.056, 8.14, x, 0, .Concrete)
	slab(&parts, 0.14, 0.056, 8, 0, 0, .Concrete)
	slab(&parts, 18, 0.056, 0.14, 0, 0, .Concrete)
	return parts
}

// A 2.2 m footpath, 16 m long: pale concrete with dark expansion joints every 2 m and a darker kerb line each side.
@(private = "package")
walkway :: proc() -> (parts: Parts) {
	slab(&parts, 2.2, 0.045, 16, 0, 0, .Concrete)
	for side in ([2]f32{-1.05, 1.05}) do slab(&parts, 0.1, 0.05, 16, side, 0, .Asphalt)
	for index in 0 ..< 7 do slab(&parts, 2.0, 0.05, 0.04, 0, -7 + f32(index) * 2, .Asphalt)
	return parts
}

// A vehicle apron: a wide asphalt slab with painted parking bays.
@(private = "package")
apron :: proc() -> (parts: Parts) {
	slab(&parts, 44, 0.03, 16, 0, 0, .Asphalt)
	for index in 0 ..< 12 do slab(&parts, 0.12, 0.036, 9, -20.25 + f32(index) * 3.7, 0, .Concrete)
	return parts
}

// A mown lawn with a pale kerb all round.
@(private = "package")
lawn :: proc() -> (parts: Parts) {
	slab(&parts, 10, 0.07, 6, 0, 0, .Grass)
	for side in ([2]f32{-2.9, 2.9}) do slab(&parts, 10.2, 0.09, 0.2, 0, side, .Concrete)
	for side in ([2]f32{-4.9, 4.9}) do slab(&parts, 0.2, 0.09, 6, side, 0, .Concrete)
	return parts
}
