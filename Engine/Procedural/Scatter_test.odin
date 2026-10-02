package Procedural

import "core:math/linalg"
import "core:testing"

test_rules :: proc() -> Scatter_Rules {
	return Scatter_Rules{seed = 5, attempts_per_chunk = 200, min_normal_y = 0.9, exclusion_radius_meters = 140, scale_range = {0.8, 1.4}}
}

@(test)
test_scatter_is_deterministic_per_chunk :: proc(t: ^testing.T) {
	first := Scatter_Chunk(test_terrain(), test_rules(), {4, 3}, 64)
	defer delete(first)
	second := Scatter_Chunk(test_terrain(), test_rules(), {4, 3}, 64)
	defer delete(second)
	testing.expect(t, len(first) > 0)
	testing.expect_value(t, len(first), len(second))
	for point, index in first do testing.expect_value(t, point, second[index])
}

@(test)
test_scatter_points_obey_the_rules :: proc(t: ^testing.T) {
	terrain, rules := test_terrain(), test_rules()
	for chunk in ([4][2]i32{{4, 3}, {-5, 2}, {0, 0}, {6, -6}}) {
		points := Scatter_Chunk(terrain, rules, chunk, 64)
		defer delete(points)
		testing.expect(t, len(points) <= rules.attempts_per_chunk)
		for point in points {
			testing.expect(t, point.position.x >= f32(chunk.x) * 64 && point.position.x < f32(chunk.x + 1) * 64)
			testing.expect(t, point.position.z >= f32(chunk.y) * 64 && point.position.z < f32(chunk.y + 1) * 64)
			testing.expect_value(t, point.position.y, Terrain_Height(terrain, point.position.x, point.position.z))
			testing.expect(t, linalg.length([2]f32{point.position.x, point.position.z} - terrain.plateau_center) >= rules.exclusion_radius_meters)
			testing.expect(t, point.scale >= rules.scale_range.x && point.scale <= rules.scale_range.y)
			step: f32 = 0.5
			slope_x := (Terrain_Height(terrain, point.position.x + step, point.position.z) - Terrain_Height(terrain, point.position.x - step, point.position.z)) / (2 * step)
			slope_z := (Terrain_Height(terrain, point.position.x, point.position.z + step) - Terrain_Height(terrain, point.position.x, point.position.z - step)) / (2 * step)
			testing.expect(t, linalg.normalize([3]f32{-slope_x, 1, -slope_z}).y >= rules.min_normal_y - 0.02)
		}
	}
}

@(test)
test_nothing_is_scattered_on_the_plateau :: proc(t: ^testing.T) {
	points := Scatter_Chunk(test_terrain(), test_rules(), {0, 0}, 64)
	defer delete(points)
	testing.expect_value(t, len(points), 0)
}

@(test)
test_different_chunks_get_different_layouts :: proc(t: ^testing.T) {
	a := Scatter_Chunk(test_terrain(), test_rules(), {4, 3}, 64)
	defer delete(a)
	b := Scatter_Chunk(test_terrain(), test_rules(), {5, 3}, 64)
	defer delete(b)
	testing.expect(t, len(a) > 0 && len(b) > 0)
	shifted_copy := len(a) == len(b)
	for index in 0 ..< min(len(a), len(b)) {
		if abs((a[index].position.x + 64) - b[index].position.x) > 1e-3 || abs(a[index].position.z - b[index].position.z) > 1e-3 do shifted_copy = false
	}
	testing.expect(t, !shifted_copy)
}
