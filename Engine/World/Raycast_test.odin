package World

import "../Procedural"
import "core:math"
import "core:math/linalg"
import "core:testing"

near :: proc(a, b: [3]f32, tolerance: f32 = 1e-4) -> bool {
	return linalg.length(a - b) < tolerance
}

BOX :: Procedural.Collision_Box{{2, 1, -1}, {4, 3, 1}}

@(test)
test_a_ray_hits_each_face_of_a_box_with_the_right_distance_and_normal :: proc(t: ^testing.T) {
	cases := [?]struct {
		origin, direction, normal: [3]f32,
		distance:                  f32,
	}{
		{{0, 2, 0}, {1, 0, 0}, {-1, 0, 0}, 2},
		{{9, 2, 0}, {-1, 0, 0}, {1, 0, 0}, 5},
		{{3, 8, 0}, {0, -1, 0}, {0, 1, 0}, 5},
		{{3, -4, 0}, {0, 1, 0}, {0, -1, 0}, 5},
		{{3, 2, -6}, {0, 0, 1}, {0, 0, -1}, 5},
		{{3, 2, 6}, {0, 0, -1}, {0, 0, 1}, 5},
	}
	for case_ in cases {
		hit := Ray_Box(case_.origin, case_.direction, BOX)
		testing.expect(t, hit.hit)
		testing.expect(t, abs(hit.distance - case_.distance) < 1e-4)
		testing.expect(t, near(hit.normal, case_.normal))
		testing.expect(t, near(hit.point, case_.origin + case_.direction * case_.distance))
	}
}

@(test)
test_a_ray_misses_a_box_it_does_not_cross_or_points_away_from :: proc(t: ^testing.T) {
	testing.expect(t, !Ray_Box({0, 5, 0}, {1, 0, 0}, BOX).hit) // Passes above.
	testing.expect(t, !Ray_Box({0, 2, 0}, {-1, 0, 0}, BOX).hit) // Points away.
	testing.expect(t, !Ray_Box({0, 2, 3}, {1, 0, 0}, BOX).hit) // Parallel and offset.
	hit := Ray_Box({0, 2, 0}, linalg.normalize([3]f32{1, 0.2, 0.1}), BOX)
	testing.expect(t, hit.hit) // A slanted ray that does cross.
}

@(test)
test_a_ray_diagonal_through_the_box_corner_region_hits_the_nearest_face :: proc(t: ^testing.T) {
	origin := [3]f32{0, 0, -3}
	direction := linalg.normalize([3]f32{1, 1, 1})
	hit := Ray_Box(origin, direction, BOX)
	testing.expect(t, hit.hit)
	testing.expect(t, abs(linalg.length(hit.normal) - 1) < 1e-5)
	inside_or_on_surface := hit.point.x >= BOX.lowest.x - 1e-3 && hit.point.x <= BOX.highest.x + 1e-3 && hit.point.y >= BOX.lowest.y - 1e-3 && hit.point.y <= BOX.highest.y + 1e-3 && hit.point.z >= BOX.lowest.z - 1e-3 && hit.point.z <= BOX.highest.z + 1e-3
	testing.expect(t, inside_or_on_surface)
}

@(test)
test_rays_against_spheres :: proc(t: ^testing.T) {
	hit := Ray_Sphere({0, 0, 0}, {1, 0, 0}, {6, 0, 0}, 1.5)
	testing.expect(t, hit.hit && abs(hit.distance - 4.5) < 1e-4 && near(hit.normal, {-1, 0, 0}))
	testing.expect(t, !Ray_Sphere({0, 0, 0}, {1, 0, 0}, {6, 2, 0}, 1.5).hit) // Passes beside it.
	testing.expect(t, !Ray_Sphere({0, 0, 0}, {-1, 0, 0}, {6, 0, 0}, 1.5).hit) // Behind the origin.
	grazing := Ray_Sphere({0, 1.5, 0}, {1, 0, 0}, {6, 0, 0}, 1.5)
	testing.expect(t, grazing.hit && abs(grazing.distance - 6) < 1e-2)
}

@(test)
test_rays_against_capsules :: proc(t: ^testing.T) {
	bottom, top: [3]f32 = {0, 0, 0}, {0, 1, 0}
	side := Ray_Capsule({-2, 0.5, 0}, {1, 0, 0}, bottom, top, 0.2)
	testing.expect(t, side.hit && abs(side.distance - 1.8) < 1e-4 && near(side.normal, {-1, 0, 0}))
	cap_hit := Ray_Capsule({0, 3, 0}, {0, -1, 0}, bottom, top, 0.2)
	testing.expect(t, cap_hit.hit && abs(cap_hit.distance - 1.8) < 1e-4 && near(cap_hit.normal, {0, 1, 0}))
	low_cap := Ray_Capsule({0, -3, 0}, {0, 1, 0}, bottom, top, 0.2)
	testing.expect(t, low_cap.hit && abs(low_cap.distance - 2.8) < 1e-4 && near(low_cap.normal, {0, -1, 0}))
	testing.expect(t, !Ray_Capsule({-2, 0.5, 0.3}, {1, 0, 0}, bottom, top, 0.2).hit) // Misses by more than the radius.
	testing.expect(t, !Ray_Capsule({-2, 0.5, 0}, {-1, 0, 0}, bottom, top, 0.2).hit)
}

sloped :: proc(data: rawptr, x, z: f32) -> f32 {
	return 0.1 * x
}

@(test)
test_rays_against_the_terrain :: proc(t: ^testing.T) {
	flat := Ground{height_at = flat_ground}
	hit := Ray_Terrain({0, 10, 0}, linalg.normalize([3]f32{0.6, -0.8, 0}), flat, 100)
	testing.expect(t, hit.hit && abs(hit.distance - 12.5) < 0.02 && abs(hit.point.y) < 0.02)
	testing.expect(t, near(hit.normal, {0, 1, 0}, 0.01))
	slope := Ground{height_at = sloped}
	down := Ray_Terrain({0, 10, 0}, {0, -1, 0}, slope, 100)
	testing.expect(t, down.hit && abs(down.distance - 10) < 0.02)
	along := Ray_Terrain({0, 5, 0}, linalg.normalize([3]f32{1, 0, 0}), slope, 100) // Hits where 0.1 x = 5: x = 50.
	testing.expect(t, along.hit && abs(along.distance - 50) < 0.05)
	testing.expect(t, !Ray_Terrain({0, 10, 0}, {0, 1, 0}, flat, 100).hit) // Up and away.
	testing.expect(t, !Ray_Terrain({0, 10, 0}, linalg.normalize([3]f32{1, -0.1, 0}), flat, 20).hit) // Would land beyond the range.
}

@(test)
test_the_world_ray_returns_the_nearest_of_box_and_terrain :: proc(t: ^testing.T) {
	world: Collision_World
	defer Collision_World_Destroy(&world)
	append(&world.boxes, Box_Solid({8, 0, -2}, {9, 4, 2}))
	append(&world.boxes, Box_Solid({3, 0, -2}, {4, 4, 2}))
	ground := Ground{height_at = flat_ground}
	level := Raycast_World(world, ground, {0, 1, 0}, {1, 0, 0}, 50)
	testing.expect(t, level.hit && level.kind == .Box && level.box_index == 1 && abs(level.distance - 3) < 1e-4) // The nearer box, not the one behind.
	downward := Raycast_World(world, ground, {0, 2, 0}, linalg.normalize([3]f32{1, -1, 0}), 50)
	testing.expect(t, downward.hit && downward.kind == .Terrain && abs(downward.point.x - 2) < 0.05)
	testing.expect(t, !Raycast_World(world, ground, {0, 1, 0}, {-1, 0, 0}, 50).hit)
	testing.expect(t, !Raycast_World(world, ground, {0, 1, 0}, {1, 0, 0}, 2).hit) // Short of the box.
}

@(test)
test_a_projectile_follows_the_exact_ballistic_path_whatever_the_step :: proc(t: ^testing.T) {
	gravity := [3]f32{0, -9.81, 0}
	start := Projectile{position = {1, 2, 3}, velocity = {10, 6, -4}}
	coarse, fine := start, start
	Ballistic_Step(&coarse, gravity, 1.5)
	for _ in 0 ..< 150 do Ballistic_Step(&fine, gravity, 0.01)
	expected_position := start.position + start.velocity * 1.5 + gravity * (0.5 * 1.5 * 1.5)
	testing.expect(t, near(coarse.position, expected_position, 1e-3) && near(fine.position, expected_position, 1e-3))
	testing.expect(t, near(coarse.velocity, start.velocity + gravity * 1.5, 1e-4))
	apex := Projectile{position = {}, velocity = {0, 9.81, 0}}
	Ballistic_Step(&apex, gravity, 1)
	testing.expect(t, abs(apex.velocity.y) < 1e-4 && abs(apex.position.y - 4.905) < 1e-3)
}

@(test)
test_spread_stays_inside_its_cone_and_is_uniform_over_it :: proc(t: ^testing.T) {
	aim := linalg.normalize([3]f32{0.3, 0.4, 0.8})
	testing.expect(t, near(Spread_Direction(aim, 0, 0.7, 0.2), aim, 1e-5))
	half_angle := math.to_radians(f32(5))
	cosine_sum: f32
	samples := 0
	for first in 0 ..< 40 do for second in 0 ..< 40 {
		direction := Spread_Direction(aim, half_angle, (f32(first) + 0.5) / 40, (f32(second) + 0.5) / 40)
		testing.expect(t, abs(linalg.length(direction) - 1) < 1e-4)
		cosine := linalg.dot(direction, aim)
		testing.expect(t, cosine >= math.cos(half_angle) - 1e-4)
		cosine_sum += cosine
		samples += 1
	}
	testing.expect(t, abs(cosine_sum / f32(samples) - (1 + math.cos(half_angle)) / 2) < 5e-4) // Mean cosine of a uniform cap.
}
