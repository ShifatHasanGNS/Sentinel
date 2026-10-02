package Catalogue

import "../../Engine/Procedural"
import "../Materials"

// Three metres of chain-link: two posts, two rails, vertical and horizontal wires, and a coil of razor wire on top.
@(private = "package")
fence_section :: proc() -> (parts: Parts) {
	for x in ([2]f32{-1.5, 1.5}) do add_cylinder(&parts, 0.05, 2.4, {x, 1.2, 0}, .Rusted_Metal, true, 8)
	add_collision_box(&parts, {3, 2.6, 0.1}, {0, 1.3, 0})
	add_cylinder_x(&parts, 0.03, 3, {0, 2.3, 0}, .Rusted_Metal, true, 6)
	add_cylinder_x(&parts, 0.03, 3, {0, 0.3, 0}, .Rusted_Metal, true, 6)
	for index in 0 ..< 19 do add_box(&parts, {0.02, 2, 0.02}, {-1.35 + f32(index) * 0.15, 1.3, 0}, .Rusted_Metal, false)
	for index in 0 ..< 6 do add_box(&parts, {2.96, 0.015, 0.015}, {0, 0.5 + f32(index) * 0.35, 0}, .Rusted_Metal, false)
	for index in 0 ..< 10 {
		add_part(&parts, Procedural.Part{primitive = Procedural.Torus(0.15, 0.012, 12, 4), position = {-1.35 + f32(index) * 0.3, 2.55, 0}, rotation_degrees = {0, 0, 90}, material = layer(.Rusted_Metal)})
	}
	return parts
}

// Two concrete posts and a lintel beam; the two mesh leaves between them are doors (see Doors.odin).
@(private = "package")
gate :: proc() -> (parts: Parts) {
	for x in ([2]f32{-4.25, 4.25}) do add_box(&parts, {0.5, 3.2, 0.5}, {x, 1.6, 0}, .Concrete)
	add_box(&parts, {8, 0.25, 0.3}, {0, 3.05, 0}, .Concrete, false)
	return parts
}

// A checkpoint boom: motor housing at one end, a long arm painted in alternating bands.
@(private = "package")
barrier_arm :: proc() -> (parts: Parts) {
	add_box(&parts, {0.6, 1.1, 0.6}, {-3.2, 0.55, 0}, .Painted_Metal)
	for index in 0 ..< 6 {
		material := Materials.Surface_Material.Painted_Metal if index % 2 == 0 else Materials.Surface_Material.Sand
		add_box(&parts, {1, 0.12, 0.12}, {-2.4 + f32(index), 1, 0}, material)
	}
	return parts
}

// An inverted-T concrete barrier: a wide foot under a tall thin stem.
@(private = "package")
t_wall :: proc() -> (parts: Parts) {
	add_box(&parts, {3, 0.4, 1.2}, {0, 0.2, 0}, .Concrete)
	add_box(&parts, {3, 2.9, 0.45}, {0, 1.85, 0}, .Concrete)
	return parts
}

// A collapsible wire-mesh cell lined with fabric and filled with earth: a bulging canvas cube with a dirt top.
@(private = "package")
hesco_barrier :: proc() -> (parts: Parts) {
	add_part(&parts, Procedural.Part{primitive = Procedural.Box({1.5, 1.5, 1.5}, {4, 4, 4}), position = {0, 0.75, 0}, deformers = {0 = Procedural.Bulge{0.06}}, material = layer(.Canvas), solid = true})
	add_box(&parts, {1.4, 0.06, 1.4}, {0, 1.5, 0}, .Dirt, false)
	return parts
}

// Four courses of stacked, staggered sandbags; each bag is a bulging, lumpy block.
@(private = "package")
sandbag_wall :: proc() -> (parts: Parts) {
	for row in 0 ..< 4 {
		per_row := 6 if row % 2 == 0 else 5
		offset: f32 = 0 if row % 2 == 0 else 0.25
		for index in 0 ..< per_row {
			x := (f32(index) - f32(per_row - 1) / 2) * 0.5
			seed := u32(row * 10 + index)
			add_part(&parts, Procedural.Part{
				primitive = Procedural.Box({0.5, 0.18, 0.45}, {4, 2, 4}),
				position = {x + (offset if row % 2 == 1 else 0) * 0, 0.09 + f32(row) * 0.17, 0},
				deformers = {0 = Procedural.Bulge{0.2}, 1 = Procedural.Noise_Displace{0.015, 6, 2, seed}},
				material = layer(.Canvas),
				solid = true,
			})
		}
	}
	return parts
}
