package Vehicles

import "../Catalogue"
import "../../Engine/Procedural"
import "../../Engine/Render"
import "core:math"
import la "core:math/linalg"

ROTOR_BLUR_COPIES :: 5
ROTOR_BLUR_STEP_RADIANS :: 0.16
TAIL_ROTOR_SPEED_RATIO :: 1.7 // The small rotor turns faster than the main one.

Part_Group :: struct {
	mesh:     Render.Mesh,
	material: i32,
	emission: [3]f32,
}

// The meshes of one vehicle kind: hull, turret and gun are drawn once per vehicle; the wheel is instanced across every wheel of
// every vehicle of the kind.
Kind_Render :: struct {
	body:   [dynamic]Part_Group,
	wheel:  [dynamic]Part_Group,
	turret: [dynamic]Part_Group,
	gun:    [dynamic]Part_Group,
	links:  [dynamic]Part_Group,
	main_rotor: [dynamic]Part_Group,
	tail_rotor: [dynamic]Part_Group,
	present: bool,
}

Vehicle_Renderer :: struct {
	kinds: [Catalogue.Object_Kind]Kind_Render,
}

Vehicle_Renderer_Create :: proc(vehicles: []Vehicle) -> (renderer: Vehicle_Renderer) {
	for vehicle in vehicles {
		if renderer.kinds[vehicle.kind].present do continue
		wheels := 0
		for other in vehicles do if other.kind == vehicle.kind do wheels += len(other.spec.wheel_mounts)
		render := &renderer.kinds[vehicle.kind]
		render.present = true
		upload(&render.body, vehicle.spec.body, 0)
		upload(&render.wheel, vehicle.spec.wheel, wheels)
		upload(&render.turret, vehicle.spec.turret, 0)
		upload(&render.gun, vehicle.spec.gun, 0)
		if track, has_track := vehicle.spec.track.?; has_track {
			per_vehicle := 2 * (int((2 * 2 * track.half_run + 2 * math.PI * track.radius) / track.pitch) + 2)
			upload(&render.links, track.link, per_vehicle * count_of_kind(vehicles, vehicle.kind))
		}
		upload(&render.main_rotor, vehicle.spec.main_rotor, 0)
		upload(&render.tail_rotor, vehicle.spec.tail_rotor, 0)
	}
	return renderer
}

Vehicle_Renderer_Destroy :: proc(renderer: ^Vehicle_Renderer) {
	for &render in renderer.kinds {
		for groups in ([7]^[dynamic]Part_Group{&render.body, &render.wheel, &render.turret, &render.gun, &render.links, &render.main_rotor, &render.tail_rotor}) {
			for &group in groups do Render.Mesh_Destroy(&group.mesh)
			delete(groups^)
		}
	}
}

// `instance_capacity` of zero uploads an ordinary mesh.
@(private = "file")
upload :: proc(groups: ^[dynamic]Part_Group, parts: [dynamic]Procedural.Part, instance_capacity: int) {
	if len(parts) == 0 do return
	assembly := Procedural.Assembly_Build(parts[:])
	defer Procedural.Assembly_Destroy(&assembly)
	for group in assembly.groups {
		mesh := Render.Mesh_Upload(group.mesh) if instance_capacity == 0 else Render.Mesh_Upload_Instanced(group.mesh, instance_capacity)
		append(groups, Part_Group{mesh, group.material, group.emission})
	}
}

// Draw items for every vehicle: hull, turret and gun with their current angles, and the wheels as instances, steered and spinning.
Vehicle_Renderer_Items :: proc(renderer: ^Vehicle_Renderer, vehicles: []Vehicle, allocator := context.temp_allocator) -> (items: [dynamic]Render.Draw_Item) {
	items = make([dynamic]Render.Draw_Item, allocator)
	for kind in Catalogue.Object_Kind {
		render := &renderer.kinds[kind]
		if !render.present do continue
		wheels := make([dynamic]Render.Instance, allocator)
		links := make([dynamic]Render.Instance, allocator)
		for vehicle in vehicles {
			if vehicle.kind != kind do continue
			hull := Vehicle_Hull_Matrix(vehicle)
			add_group_items(&items, render.body[:], hull)
			add_group_items(&items, render.turret[:], Vehicle_Turret_Matrix(vehicle))
			add_group_items(&items, render.gun[:], Vehicle_Gun_Matrix(vehicle))
			// Rotor blur: a fast rotor turns a stroboscopic fan of copies trailing the blades, which the eye reads as a smear; the
			// copies are drawn at angles behind the true one, spaced by how far the rotor turns in a frame at 60 Hz.
			copies := 1 + int(vehicle.air.rotor * ROTOR_BLUR_COPIES)
			for copy in 0 ..< copies {
				trail := f32(copy) * ROTOR_BLUR_STEP_RADIANS * vehicle.air.rotor
				add_group_items(&items, render.main_rotor[:], hull * la.matrix4_translate_f32(vehicle.spec.main_rotor_pivot) * la.matrix4_rotate_f32(vehicle.air.rotor_angle_radians - trail, {0, 1, 0}))
			}
			add_group_items(&items, render.tail_rotor[:], hull * la.matrix4_translate_f32(vehicle.spec.tail_rotor_pivot) * la.matrix4_rotate_f32(vehicle.air.rotor_angle_radians * TAIL_ROTOR_SPEED_RATIO, {1, 0, 0}))
			for mount in vehicle.spec.wheel_mounts do append(&wheels, Render.Instance{model = wheel_matrix(vehicle, hull, mount)})
			if track, has_track := vehicle.spec.track.?; has_track do append_track_links(&links, vehicle, hull, track)
		}
		for &group in render.links {
			for &instance in links do instance.material_layer = f32(group.material)
			Render.Mesh_Set_Instances(&group.mesh, links[:])
			append(&items, Render.Draw_Item{mesh = &group.mesh, model = la.MATRIX4F32_IDENTITY, uv_scale = {1, 1}, triplanar = true, illumination_model = .Cook_Torrance, emission = group.emission})
		}
		for &group in render.wheel {
			for &instance in wheels do instance.material_layer = f32(group.material)
			Render.Mesh_Set_Instances(&group.mesh, wheels[:])
			append(&items, Render.Draw_Item{mesh = &group.mesh, model = la.MATRIX4F32_IDENTITY, uv_scale = {1, 1}, triplanar = true, illumination_model = .Cook_Torrance, emission = group.emission})
		}
	}
	return items
}

@(private = "file")
add_group_items :: proc(items: ^[dynamic]Render.Draw_Item, groups: []Part_Group, model: matrix[4, 4]f32) {
	for &group in groups {
		append(items, Render.Draw_Item{mesh = &group.mesh, model = model, material_layer = group.material, uv_scale = {1, 1}, triplanar = true, illumination_model = .Cook_Torrance, emission = group.emission})
	}
}

// A wheel: its mount, steered about +Y (right is a negative turn about +Y), spun about its axle by the distance rolled over its radius.
@(private = "file")
wheel_matrix :: proc(vehicle: Vehicle, hull: matrix[4, 4]f32, mount: Catalogue.Wheel_Mount) -> matrix[4, 4]f32 {
	steer: f32 = 0
	if mount.steered do steer = -vehicle.body.steer * vehicle.spec.handling.steer_angle_max
	spin := (vehicle.body.wheel_spin_radians + track_side_offset(vehicle, mount.position.x)) / vehicle.spec.wheel_radius
	return hull * la.matrix4_translate_f32(mount.position) * la.matrix4_rotate_f32(steer, {0, 1, 0}) * la.matrix4_rotate_f32(math.mod(spin, 2 * math.PI), {1, 0, 0})
}

// How far a tracked vehicle's track on the side at `x` has travelled beyond the vehicle's own travel: turning left (positive yaw) drives
// the right-hand track (x < 0 when facing +Z) forward and the left-hand one back, so the tracks run opposite ways when pivoting.
@(private = "file")
track_side_offset :: proc(vehicle: Vehicle, x: f32) -> f32 {
	if !vehicle.spec.handling.tracked do return 0
	return (vehicle.body.yaw_radians * vehicle.spec.handling.half_width) * (1 if x < 0 else -1)
}

@(private = "file")
count_of_kind :: proc(vehicles: []Vehicle, kind: Catalogue.Object_Kind) -> (count: int) {
	for vehicle in vehicles do if vehicle.kind == kind do count += 1
	return
}

// Places every link of both belts on the stadium path: bottom run (moving backward on the vehicle), rear arc, top run, front arc.
// `distance` slides all links along the path; a link's local +Y is the belt's outward normal.
@(private = "file")
append_track_links :: proc(links: ^[dynamic]Render.Instance, vehicle: Vehicle, hull: matrix[4, 4]f32, track: Catalogue.Track_Spec) {
	run := 2 * track.half_run
	arc := math.PI * track.radius
	perimeter := 2 * run + 2 * arc
	count := int(perimeter / track.pitch)
	for x in track.sides {
		offset := vehicle.body.wheel_spin_radians + track_side_offset(vehicle, x)
		for index in 0 ..< count {
			distance := math.mod(f32(index) * perimeter / f32(count) + offset, perimeter)
			if distance < 0 do distance += perimeter
			y, z, angle := track_point(track, distance, run, arc)
			local := la.matrix4_translate_f32({x, y, z}) * la.matrix4_rotate_f32(angle, {1, 0, 0})
			append(links, Render.Instance{model = hull * local})
		}
	}
}

@(private = "file")
track_point :: proc(track: Catalogue.Track_Spec, distance, run, arc: f32) -> (y, z, angle: f32) {
	radius, centre := track.radius, track.centre_y
	switch {
	case distance < run: return centre - radius, track.half_run - distance, math.PI
	case distance < run + arc:
		turn := (distance - run) / radius // The rear arc turns the normal from down (pi) through backward to up (2 pi).
		angle = math.PI + turn
		return centre + radius * math.cos(angle), -track.half_run + radius * math.sin(angle), angle
	case distance < 2 * run + arc: return centre + radius, -track.half_run + (distance - run - arc), 0
	}
	turn := (distance - 2 * run - arc) / radius // The front arc turns the normal from up (0) through forward to down (pi).
	return centre + radius * math.cos(turn), track.half_run + radius * math.sin(turn), turn
}
