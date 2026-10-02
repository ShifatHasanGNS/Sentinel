package Vehicles

import "../Catalogue"
import "../Gameplay"
import World "../../Engine/World"
import "core:math"
import "core:testing"

// Seam: the Vehicles procs against a Gameplay.Battle (world, enemies, projectiles).

flat :: proc(data: rawptr, x, z: f32) -> f32 {
	return 0
}

GROUND :: World.Ground{height_at = flat}

make_battle :: proc(kinds: []Catalogue.Object_Kind) -> (battle: Gameplay.Battle, vehicles: [dynamic]Vehicle) {
	battle = Gameplay.Battle_Create(GROUND, nil, {0, 0, -50}, 1)
	placed := make([dynamic]Placed, context.temp_allocator)
	for kind, index in kinds do append(&placed, Placed{kind, f32(index) * 12, 0, 0})
	vehicles = Vehicles_Create(placed[:], GROUND, &battle.collision)
	return
}

@(test)
test_vehicles_are_created_at_their_placement_with_a_hull_solid_each :: proc(t: ^testing.T) {
	battle, vehicles := make_battle({.Jeep, .Battle_Tank})
	defer Gameplay.Battle_Destroy(&battle)
	defer delete(vehicles)
	testing.expect_value(t, len(vehicles), 2)
	testing.expect_value(t, len(battle.collision.boxes), 2)
	testing.expect_value(t, vehicles[1].body.position.x, 12)
	testing.expect(t, battle.collision.boxes[vehicles[1].solid_index].half_extents.z == vehicles[1].spec.handling.half_length)
}

@(test)
test_boarding_needs_to_be_close_unoccupied_and_nearly_still :: proc(t: ^testing.T) {
	battle, vehicles := make_battle({.Jeep})
	defer Gameplay.Battle_Destroy(&battle)
	defer delete(vehicles)
	jeep := &vehicles[0]
	half_width := jeep.spec.handling.half_width
	testing.expect(t, Vehicle_Can_Board(jeep^, {half_width + 2, 0, 0})) // 2 m from the side.
	testing.expect(t, !Vehicle_Can_Board(jeep^, {half_width + 4.5, 0, 0})) // Too far.
	jeep.body.speed = 6
	testing.expect(t, !Vehicle_Can_Board(jeep^, {half_width + 2, 0, 0})) // Rolling.
	jeep.body.speed = 0
	jeep.occupied = true
	testing.expect(t, !Vehicle_Can_Board(jeep^, {half_width + 2, 0, 0})) // Taken.
}

@(test)
test_the_exit_spot_is_clear_and_goes_to_the_other_side_when_one_is_blocked :: proc(t: ^testing.T) {
	battle, vehicles := make_battle({.Cargo_Truck})
	defer Gameplay.Battle_Destroy(&battle)
	defer delete(vehicles)
	truck := vehicles[0]
	left := Vehicle_Exit_Position(truck, battle.collision, GROUND)
	testing.expect(t, left.x > 0) // The left side is +X when facing +Z.
	testing.expect(t, !World.Body_Blocked(battle.collision, left))
	append(&battle.collision.boxes, World.Solid{center = {left.x, 1.5, left.z}, half_extents = {1.5, 1.5, 1.5}})
	other := Vehicle_Exit_Position(truck, battle.collision, GROUND)
	testing.expect(t, other.x < 0)
	testing.expect(t, !World.Body_Blocked(battle.collision, other))
}

@(test)
test_a_driven_vehicle_moves_and_an_empty_one_stays_put :: proc(t: ^testing.T) {
	battle, vehicles := make_battle({.Jeep, .Jeep})
	defer Gameplay.Battle_Destroy(&battle)
	defer delete(vehicles)
	vehicles[0].occupied = true
	for _ in 0 ..< 120 {
		Vehicle_Update(&vehicles[0], Vehicle_Controls{drive = {throttle = 1}}, &battle.collision, GROUND, 1.0 / 60)
		Vehicle_Update(&vehicles[1], Vehicle_Controls{drive = {throttle = 1}}, &battle.collision, GROUND, 1.0 / 60) // Ignored: nobody is in it.
	}
	testing.expect(t, vehicles[0].body.position.z > 8)
	testing.expect_value(t, vehicles[1].body.position.z, 0)
	testing.expect_value(t, battle.collision.boxes[vehicles[0].solid_index].center.z, vehicles[0].body.position.z)
}

// A world heading of 0 is the vehicle's own forward; turning the aim 90 degrees left should swing the turret that way at its rate.
@(test)
test_the_turret_turns_toward_the_aim_at_its_own_pace_the_short_way :: proc(t: ^testing.T) {
	battle, vehicles := make_battle({.Battle_Tank})
	defer Gameplay.Battle_Destroy(&battle)
	defer delete(vehicles)
	tank := &vehicles[0]
	tank.occupied = true
	controls := Vehicle_Controls{aim_yaw = math.PI / 2}
	for _ in 0 ..< 60 do Vehicle_Update(tank, controls, &battle.collision, GROUND, 1.0 / 60)
	testing.expect(t, abs(tank.turret_yaw - TURRET_TURN_CANNON) < 0.02) // One second at the tank's rate.
	for _ in 0 ..< 240 do Vehicle_Update(tank, controls, &battle.collision, GROUND, 1.0 / 60)
	testing.expect(t, abs(tank.turret_yaw - math.PI / 2) < 0.01)
	controls.aim_yaw = -math.PI + 0.1 // Nearly behind: the short way from +90 degrees is through the back, not through the front.
	for _ in 0 ..< 60 do Vehicle_Update(tank, controls, &battle.collision, GROUND, 1.0 / 60)
	testing.expect(t, tank.turret_yaw > math.PI / 2) // Went further left, past 90, not back through 0.
}

@(test)
test_the_cannon_fires_a_shell_that_survives_leaving_the_hull_and_then_reloads :: proc(t: ^testing.T) {
	battle, vehicles := make_battle({.Battle_Tank})
	defer Gameplay.Battle_Destroy(&battle)
	defer delete(vehicles)
	tank := &vehicles[0]
	testing.expect(t, Vehicle_Fire(tank, &battle))
	testing.expect_value(t, len(battle.projectiles), 1)
	testing.expect(t, !Vehicle_Fire(tank, &battle)) // Reloading.
	Gameplay.Battle_Update(&battle, {}, 0.05)
	testing.expect_value(t, len(battle.projectiles), 1) // Still flying: not blown up by its own hull.
	testing.expect(t, !battle.collision.boxes[tank.solid_index].disabled) // The hull is solid again.
	Vehicle_Update(tank, {}, &battle.collision, GROUND, CANNON_COOLDOWN_SECONDS)
	testing.expect(t, Vehicle_Fire(tank, &battle))
}

@(test)
test_the_machine_gun_hits_an_enemy_ahead_through_its_own_hull :: proc(t: ^testing.T) {
	battle, vehicles := make_battle({.Armored_Carrier})
	defer Gameplay.Battle_Destroy(&battle)
	defer delete(vehicles)
	Gameplay.Battle_Add_Enemy(&battle, .Enemy, {0.5, 0, 30}, math.PI, nil)
	carrier := &vehicles[0]
	carrier.occupied = true
	for _ in 0 ..< 400 {
		Vehicle_Update(carrier, Vehicle_Controls{aim_yaw = math.atan2(f32(0.5), f32(30)), aim_pitch = -0.055}, &battle.collision, GROUND, 1.0 / 60) // Aimed down at the chest: the turret is 2.8 m up.
		Vehicle_Fire(carrier, &battle)
	}
	testing.expect(t, battle.enemies[0].health.current < battle.enemies[0].health.maximum)
}

@(test)
test_running_over_enemies_needs_speed_and_a_footprint_hit :: proc(t: ^testing.T) {
	battle := Gameplay.Battle_Create(GROUND, nil, {0, 0, -50}, 1)
	defer Gameplay.Battle_Destroy(&battle)
	Gameplay.Battle_Add_Enemy(&battle, .Enemy, {0, 0, 1}, 0, nil) // Under the hull.
	Gameplay.Battle_Add_Enemy(&battle, .Enemy, {5, 0, 1}, 0, nil) // Beside it.
	Gameplay.Battle_Run_Over(&battle, {0, 0, 0}, 1, 2, 0, 1.0) // Too slow.
	testing.expect_value(t, battle.enemies[0].health.current, battle.enemies[0].health.maximum)
	Gameplay.Battle_Run_Over(&battle, {0, 0, 0}, 1, 2, 0, 9.0)
	testing.expect(t, !Gameplay.Enemy_Is_Alive(battle.enemies[0]))
	testing.expect_value(t, battle.enemies[1].health.current, battle.enemies[1].health.maximum)
}

@(test)
test_a_helicopter_lifts_off_only_when_occupied_and_comes_back_down_when_abandoned :: proc(t: ^testing.T) {
	battle, vehicles := make_battle({.Helicopter})
	defer Gameplay.Battle_Destroy(&battle)
	defer delete(vehicles)
	heli := &vehicles[0]
	testing.expect(t, heli.spec.is_aircraft)
	for _ in 0 ..< 60 * 3 do Vehicle_Update(heli, Vehicle_Controls{fly = {collective = 1}}, &battle.collision, GROUND, 1.0 / 60) // Nobody in it.
	testing.expect_value(t, heli.air.position.y, 0)
	heli.occupied = true
	for _ in 0 ..< 60 * 8 do Vehicle_Update(heli, Vehicle_Controls{fly = {collective = 1}}, &battle.collision, GROUND, 1.0 / 60)
	testing.expect(t, heli.air.position.y > 10)
	testing.expect_value(t, battle.collision.boxes[heli.solid_index].center.y > heli.air.position.y, true) // The hull solid rides with it.
	heli.occupied = false
	for _ in 0 ..< 60 * 20 do Vehicle_Update(heli, {}, &battle.collision, GROUND, 1.0 / 60)
	testing.expect_value(t, heli.air.position.y, 0)
	testing.expect_value(t, heli.air.rotor, 0)
}

@(test)
test_a_helicopter_in_the_air_cannot_be_boarded_or_left :: proc(t: ^testing.T) {
	battle, vehicles := make_battle({.Helicopter})
	defer Gameplay.Battle_Destroy(&battle)
	defer delete(vehicles)
	heli := &vehicles[0]
	testing.expect(t, Vehicle_Can_Board(heli^, {2.5, 0, 0}))
	heli.air.position.y, heli.air.on_ground = 8, false
	testing.expect(t, !Vehicle_Can_Board(heli^, {2.5, 0, 0}))
	testing.expect(t, !Vehicle_Is_Settled(heli^))
	heli.air.position.y, heli.air.on_ground = 0, true
	testing.expect(t, Vehicle_Is_Settled(heli^))
}

// The hull rectangle is centred behind the pose point (the tail boom), so boarding is measured from it, and a helicopter turned
// 90 degrees is boarded from the matching side.
@(test)
test_the_helicopter_hull_is_offset_along_its_heading :: proc(t: ^testing.T) {
	battle, vehicles := make_battle({.Helicopter})
	defer Gameplay.Battle_Destroy(&battle)
	defer delete(vehicles)
	heli := &vehicles[0]
	testing.expect(t, Vehicle_Can_Board(heli^, {0, 0, -9})) // 9 m behind the pose point is beside the tail boom's end (hull reaches -7.4).
	testing.expect(t, !Vehicle_Can_Board(heli^, {0, 0, 9})) // 9 m ahead is far from the nose (hull reaches 3).
	heli.air.yaw_radians = math.PI / 2
	testing.expect(t, Vehicle_Can_Board(heli^, {-9, 0, 0})) // Now the tail points toward -X.
}
