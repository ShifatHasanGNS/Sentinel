package Catalogue

import "../../Engine/Procedural"
import "core:math"

@(private = "package")
barracks :: proc() -> (parts: Parts) {
	add_box(&parts, {18.4, 0.3, 6.9}, {0, 0.15, 0}, .Concrete)
	add_box(&parts, {18, 2.8, 6}, {0, 1.7, 0}, .Concrete)
	add_gable_roof(&parts, 18.6, 7, 1.4, 3.1, 0, .Painted_Metal)
	for x in ([2]f32{-7, 7}) {
		add_box(&parts, {1.2, 2.1, 0.12}, {x, 1.35, 3.06}, .Wood, false)
		add_box(&parts, {1.6, 0.3, 0.8}, {x, 0.15, 3.4}, .Concrete, false)
	}
	add_front_windows(&parts, 5, 2, 2, 3.05, {1.1, 1})
	return parts
}

@(private = "package")
headquarters :: proc() -> (parts: Parts) {
	add_box(&parts, {14.4, 0.3, 10.4}, {0, 0.15, 0}, .Concrete)
	add_box(&parts, {14, 3, 10}, {0, 1.8, 0}, .Concrete)
	add_box(&parts, {14.6, 0.3, 10.6}, {0, 3.45, 0}, .Concrete)
	add_box(&parts, {5, 1.6, 4}, {-2, 4.4, -1}, .Concrete)
	add_cylinder(&parts, 0.08, 3, {5, 5.1, -3}, .Rusted_Metal, false, 8)
	add_front_windows(&parts, 7, 1.8, 2.1, 5.05, {1.2, 1.1})
	add_box(&parts, {2.2, 2.3, 0.14}, {0, 1.45, 5.06}, .Wood, false)
	add_box(&parts, {3, 0.3, 1.2}, {0, 0.15, 5.6}, .Concrete, false)
	return parts
}

// A half-pipe roof of nine slabs; each slab is tangent to a circle of radius 8 about the floor line.
@(private = "package")
hangar :: proc() -> (parts: Parts) {
	radius: f32 = 8
	segments := 9
	step := f32(180) / f32(segments)
	chord := 2 * radius * math.sin(math.to_radians(step) / 2)
	for index in 0 ..< segments {
		middle := (f32(index) + 0.5) * step
		inset := radius * math.cos(math.to_radians(step) / 2)
		add_part(&parts, Procedural.Part{
			primitive = Procedural.Box({chord + 0.1, 0.25, 24}),
			position = {inset * math.cos(math.to_radians(middle)), inset * math.sin(math.to_radians(middle)), 0},
			rotation_degrees = {0, 0, middle + 90},
			material = layer(.Painted_Metal),
		})
	}
	add_box(&parts, {16.4, 0.2, 24.4}, {0, 0.1, 0}, .Concrete, false)
	add_box(&parts, {15.6, 7.6, 0.3}, {0, 3.8, -12}, .Painted_Metal)
	for x in ([2]f32{-7.85, 7.85}) do add_box(&parts, {0.3, 4, 24}, {x, 2, 0}, .Painted_Metal)
	return parts
}

@(private = "package")
mess_hall :: proc() -> (parts: Parts) {
	add_box(&parts, {14.4, 0.3, 8.4}, {0, 0.15, 0}, .Concrete)
	add_box(&parts, {14, 2.7, 8}, {0, 1.65, 0}, .Wood)
	add_gable_roof(&parts, 14.8, 9, 1.6, 3, 0, .Painted_Metal)
	add_cylinder(&parts, 0.35, 2.4, {5, 4.4, -2.5}, .Concrete, false, 10)
	add_front_windows(&parts, 4, 2.6, 1.9, 4.05, {1.3, 1.1})
	add_box(&parts, {1.6, 2.1, 0.12}, {5.5, 1.35, 4.06}, .Wood, false)
	return parts
}

@(private = "package")
generator_shed :: proc() -> (parts: Parts) {
	add_box(&parts, {3.4, 2.2, 3}, {0, 1.1, 0}, .Painted_Metal)
	add_box(&parts, {3.7, 0.15, 3.3}, {0, 2.3, 0}, .Painted_Metal)
	add_cylinder(&parts, 0.12, 0.9, {1.1, 2.7, -0.8}, .Rusted_Metal, false, 8)
	for index in 0 ..< 4 do add_box(&parts, {0.04, 0.9, 1.4}, {1.72, 1.2, -0.9 + f32(index) * 0.55}, .Rusted_Metal, false)
	add_box(&parts, {1.1, 1.8, 0.1}, {-0.8, 0.9, 1.52}, .Rusted_Metal, false)
	return parts
}

// One horizontal tank on two concrete cradles, with a manway hatch and a filler pipe.
@(private = "package")
fuel_tank :: proc() -> (parts: Parts) {
	add_part(&parts, Procedural.Part{primitive = Procedural.Cylinder(1.4, 7, 24, 2), position = {0, 1.9, 0}, rotation_degrees = {0, 0, 90}, deformers = {0 = Procedural.Bulge{0.04}}, material = layer(.Painted_Metal), solid = true})
	for x in ([2]f32{-2.4, 2.4}) do add_box(&parts, {0.6, 0.5, 2.4}, {x, 0.25, 0}, .Concrete)
	add_cylinder(&parts, 0.35, 0.25, {0, 3.4, 0}, .Rusted_Metal, false, 12)
	add_cylinder(&parts, 0.08, 0.8, {-3, 2.6, 0.9}, .Rusted_Metal, false, 8)
	return parts
}

@(private = "package")
water_tower :: proc() -> (parts: Parts) {
	for x in ([2]f32{-2, 2}) {
		for z in ([2]f32{-2, 2}) do add_cylinder(&parts, 0.18, 8, {x, 4, z}, .Rusted_Metal, true, 10)
	}
	for height in ([2]f32{2.5, 5.5}) {
		add_box(&parts, {4.2, 0.1, 0.1}, {0, height, 2}, .Rusted_Metal, false)
		add_box(&parts, {4.2, 0.1, 0.1}, {0, height, -2}, .Rusted_Metal, false)
		add_box(&parts, {0.1, 0.1, 4.2}, {2, height, 0}, .Rusted_Metal, false)
		add_box(&parts, {0.1, 0.1, 4.2}, {-2, height, 0}, .Rusted_Metal, false)
	}
	add_part(&parts, Procedural.Part{primitive = Procedural.Cylinder(2.4, 4, 24, 3), position = {0, 10, 0}, deformers = {0 = Procedural.Bulge{0.05}}, material = layer(.Painted_Metal), solid = true})
	add_part(&parts, Procedural.Part{primitive = Procedural.Cone(2.6, 1.2, 24), position = {0, 12.6, 0}, material = layer(.Painted_Metal)})
	add_box(&parts, {0.1, 3.5, 0.1}, {2.6, 8.2, 0}, .Rusted_Metal, false)
	return parts
}

@(private = "package")
watchtower :: proc() -> (parts: Parts) {
	for x in ([2]f32{-1.1, 1.1}) {
		for z in ([2]f32{-1.1, 1.1}) {
			add_part(&parts, Procedural.Part{primitive = Procedural.Cylinder(0.13, 6, 10, 2), position = {x, 3, z}, deformers = {0 = Procedural.Taper{1.3, 1}}, material = layer(.Wood), solid = true})
		}
	}
	for height in ([2]f32{1.8, 3.8}) {
		add_box(&parts, {2.3, 0.08, 0.08}, {0, height, 1.1}, .Wood, false)
		add_box(&parts, {2.3, 0.08, 0.08}, {0, height, -1.1}, .Wood, false)
		add_box(&parts, {0.08, 0.08, 2.3}, {1.1, height, 0}, .Wood, false)
		add_box(&parts, {0.08, 0.08, 2.3}, {-1.1, height, 0}, .Wood, false)
	}
	add_box(&parts, {3, 0.2, 3}, {0, 6.1, 0}, .Wood)
	add_box(&parts, {2.6, 1.6, 2.6}, {0, 7, 0}, .Wood)
	add_box(&parts, {2.7, 0.7, 0.1}, {0, 7.2, 1.35}, .Glass, false, {}, {0.9, 0.65, 0.3})
	add_part(&parts, Procedural.Part{primitive = Procedural.Cone(2.2, 0.9, 4), position = {0, 8.25, 0}, rotation_degrees = {0, 45, 0}, material = layer(.Painted_Metal), solid = true})
	add_cylinder_z(&parts, 0.18, 0.5, {1.1, 7.6, 1.5}, .Painted_Metal, false, 12)
	add_box(&parts, {0.08, 6.2, 0.4}, {-0.4, 3.1, 1.45}, .Wood, false)
	return parts
}

@(private = "package")
guard_post :: proc() -> (parts: Parts) {
	add_box(&parts, {2.4, 2.5, 2.4}, {0, 1.25, 0}, .Concrete)
	add_box(&parts, {3, 0.2, 3}, {0, 2.6, 0}, .Painted_Metal)
	add_box(&parts, {1.4, 0.8, 0.1}, {0, 1.7, 1.25}, .Glass, false, {}, {0.9, 0.65, 0.3})
	add_box(&parts, {0.9, 1.9, 0.1}, {-0.7, 0.95, 1.22}, .Wood, false)
	return parts
}

@(private = "package")
bunker :: proc() -> (parts: Parts) {
	add_box(&parts, {6, 1.8, 6}, {0, 0.9, 0}, .Concrete)
	add_box(&parts, {6.6, 0.5, 6.6}, {0, 2.05, 0}, .Concrete)
	add_box(&parts, {3, 0.4, 0.3}, {0, 1.4, 3.05}, .Rubber, false)
	for index in 0 ..< 10 {
		x := (f32(index) - 4.5) * 0.55
		add_part(&parts, Procedural.Part{primitive = Procedural.Box({0.5, 0.2, 0.32}), position = {x, 2.4, 3.1}, deformers = {0 = Procedural.Bulge{0.15}}, material = layer(.Canvas)})
	}
	add_box(&parts, {1.2, 1.7, 0.1}, {2, 0.85, 3.02}, .Rusted_Metal, false)
	return parts
}

@(private = "package")
helipad :: proc() -> (parts: Parts) {
	add_part(&parts, Procedural.Part{primitive = Procedural.Cylinder(9, 0.2, 48), position = {0, 0.1, 0}, material = layer(.Concrete), solid = true})
	add_box(&parts, {0.6, 0.03, 5}, {-1.4, 0.215, 0}, .Sand, false)
	add_box(&parts, {0.6, 0.03, 5}, {1.4, 0.215, 0}, .Sand, false)
	add_box(&parts, {2.2, 0.03, 0.6}, {0, 0.215, 0}, .Sand, false)
	for index in 0 ..< 16 {
		angle := f32(index) / 16 * 2 * math.PI
		add_part(&parts, Procedural.Part{primitive = Procedural.Sphere(0.14, 8, 4), position = {8.6 * math.cos(angle), 0.3, 8.6 * math.sin(angle)}, material = layer(.Glass), emission = {1, 0.85, 0.4}})
	}
	return parts
}

GUY_ANCHOR_RADIUS_METERS :: 3.5

@(private = "package")
radio_mast :: proc() -> (parts: Parts) {
	add_part(&parts, Procedural.Part{primitive = Procedural.Cylinder(0.25, 24, 12, 8), position = {0, 12, 0}, deformers = {0 = Procedural.Taper{1, 0.5}}, material = layer(.Rusted_Metal), solid = true})
	add_cylinder(&parts, 0.04, 3, {0, 25.5, 0}, .Rusted_Metal, false, 6)
	for height in ([3]f32{14, 18, 22}) do add_box(&parts, {2.4 - (height - 14) * 0.1, 0.06, 0.06}, {0, height, 0}, .Rusted_Metal, false)
	for index in 0 ..< 3 {
		azimuth := f32(index) * 120 + 20
		anchor := [2]f32{math.sin(math.to_radians(azimuth)), math.cos(math.to_radians(azimuth))} * GUY_ANCHOR_RADIUS_METERS
		attach_height: f32 = 16
		length := math.sqrt(GUY_ANCHOR_RADIUS_METERS * GUY_ANCHOR_RADIUS_METERS + attach_height * attach_height)
		add_part(&parts, Procedural.Part{
			primitive = Procedural.Cylinder(0.015, length, 6),
			position = {anchor.x / 2, attach_height / 2, anchor.y / 2},
			rotation_degrees = {math.to_degrees(math.atan(f32(GUY_ANCHOR_RADIUS_METERS) / attach_height)), azimuth, 0},
			material = layer(.Rusted_Metal),
		})
	}
	add_box(&parts, {0.8, 0.5, 0.8}, {0, 0.25, 0}, .Concrete, false)
	return parts
}

@(private = "package")
radar_station :: proc() -> (parts: Parts) {
	add_box(&parts, {2.4, 2.4, 3}, {0, 1.2, 0.2}, .Concrete)
	add_cylinder(&parts, 0.3, 0.9, {0, 2.85, 0}, .Painted_Metal, true, 12)
	add_part(&parts, Procedural.Part{primitive = Procedural.Sphere(2.4, 28, 14), position = {0, 4.1, 0.3}, rotation_degrees = {-55, 0, 0}, stretch = {1, 0.14, 1}, material = layer(.Painted_Metal), solid = true})
	add_part(&parts, Procedural.Part{primitive = Procedural.Cylinder(0.05, 1.6, 8), position = {0, 4.9, 1.0}, rotation_degrees = {-55, 0, 0}, material = layer(.Rusted_Metal)})
	add_box(&parts, {1.4, 1.2, 0.08}, {0, 1.0, 1.24}, .Rusted_Metal, false)
	return parts
}
