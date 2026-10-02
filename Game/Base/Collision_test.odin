package Base

import "../Catalogue"
import World "../../Engine/World"
import "core:testing"

// Seam: a body walking at an object through the world built from Placement_Solids. Every object blocks, except the ones a person
// legitimately steps over or through: a flat pad and a low ammunition box (under the 0.35 m step height), a net strung overhead,
// the open legs of the water tower, and the gate (whose leaves are doors, tested in Doors_test.odin).

flat :: proc(data: rawptr, x, z: f32) -> f32 {
	return 0
}

PASS_THROUGH :: bit_set[Catalogue.Object_Kind]{.Helipad, .Ammo_Box, .Camo_Net, .Water_Tower, .Gate}

// The body starts 8 m behind the object (-Z, away from any door) and walks along the object's own centre line (x = 0).
@(test)
test_every_object_blocks_a_body_walking_into_its_middle :: proc(t: ^testing.T) {
	for kind in Catalogue.Object_Kind {
		if kind in PASS_THROUGH do continue
		info := Catalogue.Catalogue_Info(kind)
		middle_z := (info.lowest.z + info.highest.z) / 2
		solids := Placement_Solids(Placement{kind = kind})
		world := World.Collision_World{boxes = solids}
		controller := World.Controller_Create({0, 0, info.lowest.z - 8})
		for _ in 0 ..< 60 * 8 do World.Controller_Step(&controller, world, World.Ground{height_at = flat}, {0, 3}, false, 1.0 / 60)
		testing.expectf(t, controller.position.z < middle_z, "%v does not block: walked through to z=%.2f (middle %.2f)", kind, controller.position.z, middle_z)
		World.Collision_World_Destroy(&world)
	}
}
