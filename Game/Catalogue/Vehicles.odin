package Catalogue

import "../../Engine/Procedural"

// A light utility truck. Front is +Z; four wheels, a boxy cab, hood, spare tyre and headlights.
@(private = "package")
jeep :: proc() -> (parts: Parts) {
	for x in ([2]f32{-0.98, 0.98}) {
		for z in ([2]f32{-1.5, 1.5}) do add_wheel(&parts, 0.45, 0.35, {x, 0.45, z})
	}
	add_box(&parts, {2, 0.55, 4.6}, {0, 0.8, 0}, .Olive_Paint)
	add_box(&parts, {1.9, 0.35, 1.5}, {0, 1.2, 1.5}, .Olive_Paint)
	add_box(&parts, {1.9, 0.7, 2.2}, {0, 1.45, -0.5}, .Olive_Paint)
	add_box(&parts, {1.95, 0.1, 2.3}, {0, 1.85, -0.5}, .Olive_Paint)
	add_box(&parts, {1.8, 0.55, 0.06}, {0, 1.5, 0.62}, .Glass, false)
	for x in ([2]f32{-0.96, 0.96}) do add_box(&parts, {0.05, 0.5, 1.0}, {x, 1.5, -0.5}, .Glass, false)
	add_box(&parts, {2.1, 0.2, 0.2}, {0, 0.55, 2.4}, .Rusted_Metal)
	add_box(&parts, {2.1, 0.2, 0.2}, {0, 0.55, -2.4}, .Rusted_Metal, false)
	for x in ([2]f32{-0.7, 0.7}) {
		add_part(&parts, Procedural.Part{primitive = Procedural.Sphere(0.12, 10, 5), position = {x, 0.95, 2.32}, stretch = {1, 1, 0.6}, material = layer(.Glass), emission = {1, 0.95, 0.8}})
	}
	add_cylinder_z(&parts, 0.4, 0.25, {0, 0.9, -2.52}, .Rubber, false, 18)
	return parts
}

@(private = "package")
cargo_truck :: proc() -> (parts: Parts) {
	for z in ([3]f32{3, -0.9, -2.5}) {
		for x in ([2]f32{-1.1, 1.1}) do add_wheel(&parts, 0.55, 0.3, {x, 0.55, z})
	}
	add_box(&parts, {2.2, 0.45, 7}, {0, 0.95, 0}, .Olive_Paint)
	add_box(&parts, {2.3, 1.6, 1.9}, {0, 1.95, 2.7}, .Olive_Paint)
	add_box(&parts, {2.35, 0.1, 1.95}, {0, 2.8, 2.7}, .Olive_Paint, false)
	add_box(&parts, {2.1, 0.7, 0.06}, {0, 2.2, 3.66}, .Glass, false)
	add_box(&parts, {2.1, 0.9, 1.3}, {0, 1.4, 4}, .Olive_Paint)
	add_box(&parts, {2.3, 0.25, 0.2}, {0, 0.75, 4.7}, .Rusted_Metal, false)
	add_box(&parts, {2.3, 0.2, 4.7}, {0, 1.3, -1.4}, .Wood)
	for x in ([2]f32{-1.15, 1.15}) do add_box(&parts, {0.1, 0.6, 4.7}, {x, 1.7, -1.4}, .Olive_Paint, false)
	add_part(&parts, Procedural.Part{primitive = Procedural.Box({2.2, 1.3, 4.6}, {4, 4, 4}), position = {0, 2.25, -1.4}, deformers = {0 = Procedural.Bulge{0.08}}, material = layer(.Canvas), solid = true})
	add_box(&parts, {2.3, 0.2, 0.2}, {0, 0.75, -3.8}, .Rusted_Metal, false)
	for x in ([2]f32{-0.8, 0.8}) {
		add_part(&parts, Procedural.Part{primitive = Procedural.Sphere(0.13, 10, 5), position = {x, 1.45, 4.66}, stretch = {1, 1, 0.6}, material = layer(.Glass), emission = {1, 0.95, 0.8}})
	}
	return parts
}

// Eight-wheeled troop carrier: sloped nose, boxy hull, small remote turret with a cannon.
@(private = "package")
armored_carrier :: proc() -> (parts: Parts) {
	for x in ([2]f32{-1.25, 1.25}) {
		for z in ([4]f32{-2.4, -0.8, 0.8, 2.4}) do add_wheel(&parts, 0.5, 0.35, {x, 0.5, z})
	}
	add_box(&parts, {2.7, 1.2, 6.2}, {0, 1.2, 0}, .Olive_Paint)
	add_part(&parts, Procedural.Part{primitive = Procedural.Wedge({2.7, 1.2, 1.8}), position = {0, 1.2, 4}, material = layer(.Olive_Paint), solid = true})
	add_box(&parts, {2.5, 0.7, 3.5}, {0, 2.15, -0.8}, .Olive_Paint)
	add_cylinder(&parts, 0.65, 0.55, {0.5, 2.75, -0.5}, .Olive_Paint, true, 18)
	add_cylinder_z(&parts, 0.05, 1.8, {0.5, 2.8, 0.7}, .Rusted_Metal, false, 10)
	add_box(&parts, {0.5, 0.15, 0.1}, {-0.7, 2.55, 1.0}, .Glass, false)
	for x in ([2]f32{-0.8, 0.8}) {
		add_part(&parts, Procedural.Part{primitive = Procedural.Sphere(0.1, 8, 4), position = {x, 0.95, 4.2}, material = layer(.Glass), emission = {1, 0.95, 0.8}})
	}
	return parts
}

// Main battle tank: low hull with a sloped glacis, track units with road wheels, a rounded turret and a long gun.
@(private = "package")
battle_tank :: proc() -> (parts: Parts) {
	add_box(&parts, {3, 0.9, 6.2}, {0, 1.15, 0}, .Olive_Paint)
	add_part(&parts, Procedural.Part{primitive = Procedural.Wedge({3, 0.7, 1.5}), position = {0, 1.25, 3.85}, material = layer(.Olive_Paint), solid = true})
	for x in ([2]f32{-1.5, 1.5}) {
		add_box(&parts, {0.65, 0.9, 6.9}, {x, 0.45, 0}, .Rubber)
		for index in 0 ..< 7 do add_cylinder_x(&parts, 0.32, 0.72, {x, 0.4, -2.7 + f32(index) * 0.9}, .Olive_Paint, false, 14)
	}
	add_part(&parts, Procedural.Part{primitive = Procedural.Sphere(1, 20, 10), position = {0, 2, -0.3}, stretch = {1.6, 0.5, 1.9}, material = layer(.Olive_Paint), solid = true})
	add_cylinder(&parts, 0.3, 0.25, {0.7, 2.6, -0.6}, .Olive_Paint, false, 12)
	add_cylinder_z(&parts, 0.12, 4.2, {0, 2.1, 2.3}, .Olive_Paint, true, 14)
	add_cylinder_z(&parts, 0.17, 0.4, {0, 2.1, 4.4}, .Rusted_Metal, false, 14)
	add_box(&parts, {0.5, 0.08, 0.2}, {-0.9, 2.45, 0.6}, .Glass, false)
	return parts
}

// A light utility helicopter: egg fuselage with a glass nose, tapering tail boom, two-blade rotor and skids.
@(private = "package")
helicopter :: proc() -> (parts: Parts) {
	add_part(&parts, Procedural.Part{primitive = Procedural.Sphere(1.2, 20, 10), position = {0, 1.9, 0.2}, stretch = {0.9, 1, 2.1}, material = layer(.Olive_Paint), solid = true})
	add_part(&parts, Procedural.Part{primitive = Procedural.Sphere(0.8, 16, 8), position = {0, 2.0, 1.9}, stretch = {0.9, 0.75, 1}, material = layer(.Glass), solid = true})
	add_part(&parts, Procedural.Part{primitive = Procedural.Cylinder(0.35, 4.8, 12, 4), position = {0, 2.2, -4.7}, rotation_degrees = {90, 0, 0}, deformers = {0 = Procedural.Taper{0.35, 1}}, material = layer(.Olive_Paint), solid = true})
	add_box(&parts, {0.08, 1.2, 0.9}, {0, 2.7, -6.9}, .Olive_Paint, false)
	add_box(&parts, {0.05, 1.2, 0.12}, {0.15, 2.7, -7}, .Rusted_Metal, false)
	add_cylinder(&parts, 0.1, 0.7, {0, 3.3, 0.2}, .Rusted_Metal, false, 8)
	add_cylinder(&parts, 0.25, 0.15, {0, 3.65, 0.2}, .Rusted_Metal, false, 10)
	add_box(&parts, {13, 0.05, 0.4}, {0, 3.7, 0.2}, .Rusted_Metal)
	add_part(&parts, Procedural.Part{primitive = Procedural.Box({13, 0.05, 0.4}), position = {0, 3.7, 0.2}, rotation_degrees = {0, 90, 0}, material = layer(.Rusted_Metal), solid = true})
	for x in ([2]f32{-1.1, 1.1}) {
		add_cylinder_z(&parts, 0.05, 3.4, {x, 0.15, 0.3}, .Rusted_Metal, true, 8)
		add_cylinder(&parts, 0.04, 1.4, {x, 0.85, 1.2}, .Rusted_Metal, false, 6)
		add_cylinder(&parts, 0.04, 1.4, {x, 0.85, -0.6}, .Rusted_Metal, false, 6)
	}
	return parts
}
