package Catalogue

import "../../Engine/Procedural"

@(private = "package")
crate :: proc() -> (parts: Parts) {
	add_part(&parts, Procedural.Part{primitive = Procedural.Box({1, 1, 1}, {3, 3, 3}), position = {0, 0.5, 0}, material = layer(.Wood), solid = true})
	for x in ([2]f32{-0.5, 0.5}) {
		for z in ([2]f32{-0.5, 0.5}) do add_box(&parts, {0.08, 1.04, 0.08}, {x, 0.5, z}, .Wood, false)
	}
	add_box(&parts, {0.06, 1.3, 0.03}, {0, 0.5, 0.5}, .Wood, false, {0, 0, 40})
	return parts
}

@(private = "package")
barrel :: proc() -> (parts: Parts) {
	add_part(&parts, Procedural.Part{primitive = Procedural.Cylinder(0.29, 0.88, 18, 4), position = {0, 0.44, 0}, deformers = {0 = Procedural.Bulge{0.08}}, material = layer(.Rusted_Metal), solid = true})
	for height in ([3]f32{0.14, 0.44, 0.74}) {
		add_part(&parts, Procedural.Part{primitive = Procedural.Torus(0.3, 0.014, 18, 4), position = {0, height, 0}, material = layer(.Rusted_Metal)})
	}
	add_cylinder(&parts, 0.22, 0.02, {0, 0.89, 0}, .Rusted_Metal, false, 14)
	return parts
}

// A 1.2 x 1.2 m pallet carrying two stacked ammunition crates.
@(private = "package")
pallet :: proc() -> (parts: Parts) {
	for index in 0 ..< 5 do add_box(&parts, {1.2, 0.03, 0.17}, {0, 0.14, -0.5 + f32(index) * 0.25}, .Wood)
	for index in 0 ..< 3 do add_box(&parts, {0.12, 0.1, 1.2}, {-0.5 + f32(index) * 0.5, 0.07, 0}, .Wood, false)
	for index in 0 ..< 3 do add_box(&parts, {1.2, 0.02, 0.12}, {0, 0.01, -0.5 + f32(index) * 0.5}, .Wood, false)
	add_box(&parts, {1, 0.5, 0.9}, {0, 0.4, 0}, .Olive_Paint)
	add_box(&parts, {1, 0.5, 0.9}, {0, 0.9, 0}, .Olive_Paint)
	return parts
}

@(private = "package")
tent :: proc() -> (parts: Parts) {
	add_box(&parts, {5, 1.4, 6}, {0, 0.7, 0}, .Canvas)
	add_gable_roof(&parts, 5.4, 6.4, 1.4, 1.4, 0, .Canvas)
	add_box(&parts, {1.4, 1.2, 0.05}, {0, 0.6, 3.03}, .Rubber, false)
	return parts
}

// A camouflage net stretched over four poles.
@(private = "package")
camo_net :: proc() -> (parts: Parts) {
	add_part(&parts, Procedural.Part{primitive = Procedural.Box({11.5, 0.06, 11.5}, {16, 1, 16}), position = {0, 2.7, 0}, deformers = {0 = Procedural.Noise_Displace{0.25, 0.5, 3, 12}}, material = layer(.Woodland_Camo)})
	for x in ([2]f32{-5.5, 5.5}) {
		for z in ([2]f32{-5.5, 5.5}) do add_cylinder(&parts, 0.06, 2.7, {x, 1.35, z}, .Wood, true, 8)
	}
	return parts
}

@(private = "package")
floodlight :: proc() -> (parts: Parts) {
	add_cylinder(&parts, 0.08, 4.6, {0, 2.3, 0}, .Rusted_Metal, true, 8)
	add_cylinder(&parts, 0.25, 0.1, {0, 0.05, 0}, .Rusted_Metal, false, 12)
	add_box(&parts, {0.6, 0.06, 0.06}, {0.3, 4.55, 0}, .Rusted_Metal, false)
	add_box(&parts, {0.7, 0.25, 0.45}, {0.6, 4.55, 0}, .Olive_Paint)
	add_box(&parts, {0.62, 0.04, 0.38}, {0.6, 4.41, 0}, .Glass, false, {}, {2.5, 2.3, 1.8})
	return parts
}

@(private = "package")
sign :: proc() -> (parts: Parts) {
	for x in ([2]f32{-0.6, 0.6}) do add_cylinder(&parts, 0.04, 2.2, {x, 1.1, 0}, .Rusted_Metal, true, 8)
	add_box(&parts, {1.6, 0.9, 0.05}, {0, 2.0, 0}, .Olive_Paint)
	add_box(&parts, {1.4, 0.12, 0.06}, {0, 2.2, 0}, .Sand, false)
	return parts
}

@(private = "package")
flag :: proc() -> (parts: Parts) {
	add_cylinder(&parts, 0.04, 6.5, {0, 3.25, 0}, .Rusted_Metal, true, 8)
	add_part(&parts, Procedural.Part{primitive = Procedural.Box({1.4, 0.9, 0.02}, {10, 6, 1}), position = {0.75, 5.9, 0}, deformers = {0 = Procedural.Noise_Displace{0.1, 1.2, 2, 5}}, material = layer(.Canvas), solid = true})
	add_part(&parts, Procedural.Part{primitive = Procedural.Sphere(0.07, 10, 5), position = {0, 6.55, 0}, material = layer(.Rusted_Metal)})
	return parts
}

@(private = "package")
ammo_box :: proc() -> (parts: Parts) {
	add_box(&parts, {0.45, 0.25, 0.22}, {0, 0.125, 0}, .Olive_Paint)
	add_box(&parts, {0.18, 0.03, 0.03}, {0, 0.265, 0}, .Rusted_Metal, false)
	add_box(&parts, {0.1, 0.05, 0.02}, {0, 0.18, 0.115}, .Rusted_Metal, false)
	return parts
}
