package Weapons

import "../../Engine/Procedural"
import "core:math"
import "core:testing"

// Real-world sizes in meters as {width x, height y, length z}. The grip sits at the origin and the muzzle points along +Z.
Size_Range :: struct {
	lowest:  [3]f32,
	highest: [3]f32,
}

size_ranges := [Weapon_Kind]Size_Range{
	.Rifle = {{0.04, 0.2, 0.8}, {0.1, 0.35, 1.1}},
	.Sniper_Rifle = {{0.05, 0.22, 1.1}, {0.12, 0.4, 1.4}},
	.Pistol = {{0.025, 0.12, 0.17}, {0.05, 0.2, 0.25}},
	.Rocket_Launcher = {{0.1, 0.12, 0.95}, {0.25, 0.25, 1.3}},
	.Grenade = {{0.05, 0.07, 0.05}, {0.12, 0.14, 0.12}},
}

@(test)
test_every_weapon_is_valid_and_human_sized :: proc(t: ^testing.T) {
	for kind in Weapon_Kind {
		assembly := Weapon_Build(kind)
		defer Procedural.Assembly_Destroy(&assembly)
		testing.expectf(t, len(assembly.groups) > 0, "%v: no geometry", kind)
		if len(assembly.groups) == 0 do continue
		for group in assembly.groups {
			problem := Procedural.Mesh_Find_Problem(group.mesh)
			testing.expectf(t, problem == "", "%v: %s", kind, problem)
		}
		lowest, highest := Procedural.Assembly_Bounds(assembly)
		size := highest - lowest
		range := size_ranges[kind]
		for axis in 0 ..< 3 do testing.expectf(t, size[axis] >= range.lowest[axis] && size[axis] <= range.highest[axis], "%v: axis %d is %.3f m, expected %.3f to %.3f", kind, axis, size[axis], range.lowest[axis], range.highest[axis])
	}
}

// Long guns point forward from the hand: most of their length is in front of the grip, and the grip is inside their height.
@(test)
test_long_weapons_extend_mostly_ahead_of_the_grip :: proc(t: ^testing.T) {
	for kind in ([3]Weapon_Kind{.Rifle, .Sniper_Rifle, .Rocket_Launcher}) {
		assembly := Weapon_Build(kind)
		defer Procedural.Assembly_Destroy(&assembly)
		lowest, highest := Procedural.Assembly_Bounds(assembly)
		testing.expectf(t, highest.z > 0.45 && highest.z > -lowest.z, "%v: muzzle is not ahead of the grip", kind)
		testing.expectf(t, lowest.y < 0.02 && highest.y > 0.03, "%v: the grip is not within the weapon's height", kind)
	}
}

@(test)
test_weapons_are_deterministic :: proc(t: ^testing.T) {
	for kind in Weapon_Kind {
		first, second := Weapon_Build(kind), Weapon_Build(kind)
		defer Procedural.Assembly_Destroy(&first)
		defer Procedural.Assembly_Destroy(&second)
		testing.expect_value(t, len(first.groups), len(second.groups))
		for group, index in first.groups {
			testing.expect_value(t, len(group.mesh.vertices), len(second.groups[index].mesh.vertices))
		}
	}
}
