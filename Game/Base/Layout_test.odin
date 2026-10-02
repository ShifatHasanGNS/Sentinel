package Base

import "../Catalogue"
import World "../../Engine/World"
import "../../Engine/Procedural"
import "core:math"
import "core:slice"
import "core:testing"

PLATEAU_RADIUS_METERS :: 90.0
EDGE_MARGIN_METERS :: 5.0

@(test)
test_layout_is_deterministic_and_seed_dependent :: proc(t: ^testing.T) {
	first, second, other := Layout_Create(7, PLATEAU_RADIUS_METERS), Layout_Create(7, PLATEAU_RADIUS_METERS), Layout_Create(8, PLATEAU_RADIUS_METERS)
	defer Layout_Destroy(&first)
	defer Layout_Destroy(&second)
	defer Layout_Destroy(&other)
	testing.expect_value(t, len(first.placements), len(second.placements))
	for placement, index in first.placements do testing.expect_value(t, placement, second.placements[index])
	testing.expect_value(t, len(first.placements), len(other.placements))
	differs := false
	for placement, index in first.placements do if placement != other.placements[index] do differs = true
	testing.expect(t, differs)
}

@(test)
test_every_footprint_lies_inside_the_plateau :: proc(t: ^testing.T) {
	layout := Layout_Create(7, PLATEAU_RADIUS_METERS)
	defer Layout_Destroy(&layout)
	for placement in layout.placements {
		corners := Footprint_Corners(placement)
		for corner in corners {
			testing.expectf(t, math.sqrt(corner.x * corner.x + corner.y * corner.y) <= PLATEAU_RADIUS_METERS - EDGE_MARGIN_METERS, "%v at (%.1f, %.1f) pokes off the plateau", placement.kind, placement.x, placement.z)
		}
	}
}

@(test)
test_no_two_footprints_overlap_except_where_stacking_is_intended :: proc(t: ^testing.T) {
	layout := Layout_Create(7, PLATEAU_RADIUS_METERS)
	defer Layout_Destroy(&layout)
	for first in 0 ..< len(layout.placements) {
		for second in first + 1 ..< len(layout.placements) {
			a, b := layout.placements[first], layout.placements[second]
			if Placements_May_Overlap(a.kind, b.kind) do continue
			testing.expectf(t, !Footprints_Overlap(a, b, 0.05), "%v at (%.1f, %.1f) overlaps %v at (%.1f, %.1f)", a.kind, a.x, a.z, b.kind, b.x, b.z)
		}
	}
}

// Walking around the perimeter ring, each fence section, tower or gate must touch the next: no gaps except where a gate stands.
@(test)
test_the_perimeter_is_closed :: proc(t: ^testing.T) {
	layout := Layout_Create(7, PLATEAU_RADIUS_METERS)
	defer Layout_Destroy(&layout)
	ring := make([dynamic]Placement)
	defer delete(ring)
	for placement in layout.placements {
		if placement.kind != .Fence_Section && placement.kind != .Gate && placement.kind != .Watchtower do continue
		radius := math.sqrt(placement.x * placement.x + placement.z * placement.z)
		if abs(radius - PERIMETER_RADIUS_METERS) < 1.5 do append(&ring, placement)
	}
	testing.expect(t, len(ring) > 100)
	slice.sort_by(ring[:], proc(a, b: Placement) -> bool {
		return math.atan2(a.z, a.x) < math.atan2(b.z, b.x)
	})
	for index in 0 ..< len(ring) {
		a, b := ring[index], ring[(index + 1) % len(ring)]
		half_a, half_b := Footprint_Half_Length(a), Footprint_Half_Length(b)
		gap := math.sqrt((a.x - b.x) * (a.x - b.x) + (a.z - b.z) * (a.z - b.z)) - half_a - half_b
		testing.expectf(t, gap <= 0.4, "gap of %.2f m in the perimeter between %v and %v", gap, a.kind, b.kind)
	}
}

@(test)
test_the_gate_faces_outward_on_the_approach_road :: proc(t: ^testing.T) {
	layout := Layout_Create(7, PLATEAU_RADIUS_METERS)
	defer Layout_Destroy(&layout)
	gates := 0
	for placement in layout.placements {
		if placement.kind != .Gate do continue
		gates += 1
		testing.expect(t, abs(placement.x) < 0.01 && abs(placement.z - PERIMETER_RADIUS_METERS) < 0.5)
		testing.expect(t, abs(placement.yaw_degrees) < 0.01) // Front (+Z) points out along the road.
	}
	testing.expect_value(t, gates, 1)
}

@(test)
test_the_base_has_everything_it_needs :: proc(t: ^testing.T) {
	layout := Layout_Create(7, PLATEAU_RADIUS_METERS)
	defer Layout_Destroy(&layout)
	counts: [Catalogue.Object_Kind]int
	for placement in layout.placements do counts[placement.kind] += 1
	minimums := [Catalogue.Object_Kind]int{
		.Barracks = 3, .Headquarters = 1, .Hangar = 1, .Mess_Hall = 1, .Generator_Shed = 1, .Fuel_Tank = 2, .Water_Tower = 1,
		.Watchtower = 4, .Guard_Post = 2, .Bunker = 2, .Helipad = 1, .Radio_Mast = 1, .Radar_Station = 1,
		.Fence_Section = 100, .Gate = 1, .Barrier_Arm = 1, .T_Wall = 4, .Hesco_Barrier = 4, .Sandbag_Wall = 2,
		.Jeep = 2, .Cargo_Truck = 2, .Armored_Carrier = 2, .Battle_Tank = 2, .Helicopter = 1,
		.Crate = 4, .Barrel = 4, .Pallet = 2, .Tent = 3, .Camo_Net = 1, .Floodlight = 4, .Sign = 2, .Flag = 1, .Ammo_Box = 4,
	}
	for kind in Catalogue.Object_Kind do testing.expectf(t, counts[kind] >= minimums[kind], "%v: %d placed, need at least %d", kind, counts[kind], minimums[kind])
}

// A placement turned 90 degrees keeps its solids' sizes, carries their yaw, and puts the object where it was placed: a barracks
// long along X becomes long along Z.
@(test)
test_solids_follow_the_placement_rotation :: proc(t: ^testing.T) {
	upright := Placement_Solids(Placement{kind = .Barracks, x = 0, z = 0, yaw_degrees = 0})
	defer delete(upright)
	turned := Placement_Solids(Placement{kind = .Barracks, x = 10, z = -5, yaw_degrees = 90})
	defer delete(turned)
	testing.expect(t, len(upright) > 0 && len(turned) == len(upright))
	extent :: proc(solids: []World.Solid) -> (size, center: [3]f32) {
		lowest, highest := [3]f32{max(f32), max(f32), max(f32)}, [3]f32{min(f32), min(f32), min(f32)}
		for solid in solids {
			for corner in 0 ..< 8 {
				local := [3]f32{solid.half_extents.x * (1 if corner & 1 != 0 else -1), solid.half_extents.y * (1 if corner & 2 != 0 else -1), solid.half_extents.z * (1 if corner & 4 != 0 else -1)}
				world := solid.center + World.rotate_about_y(local, solid.yaw_radians)
				lowest = {min(lowest.x, world.x), min(lowest.y, world.y), min(lowest.z, world.z)}
				highest = {max(highest.x, world.x), max(highest.y, world.y), max(highest.z, world.z)}
			}
		}
		return highest - lowest, (highest + lowest) / 2
	}
	upright_size, _ := extent(upright[:])
	turned_size, turned_center := extent(turned[:])
	testing.expect(t, abs(upright_size.x - turned_size.z) < 0.05 && abs(upright_size.z - turned_size.x) < 0.05 && abs(upright_size.y - turned_size.y) < 0.05)
	testing.expect(t, abs(turned_center.x - 10) < 1.0 && abs(turned_center.z + 5) < 1.0)
}

@(test)
test_layout_solids_cover_every_placement_at_the_ground_height :: proc(t: ^testing.T) {
	layout := Layout_Create(7, PLATEAU_RADIUS_METERS)
	defer Layout_Destroy(&layout)
	solids := Layout_Solids(layout, 10)
	defer delete(solids)
	expected := 0
	for placement in layout.placements {
		own := Placement_Solids(placement)
		expected += len(own)
		delete(own)
	}
	testing.expect_value(t, len(solids), expected)
	for solid in solids {
		testing.expect(t, solid.center.y - solid.half_extents.y >= 10 - 0.3 - 1e-3) // On the plateau, allowing the catalogue's footings 0.3 m into it.
		testing.expect(t, solid.half_extents.y > 0)
	}
}
