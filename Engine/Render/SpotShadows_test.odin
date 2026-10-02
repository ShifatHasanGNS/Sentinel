package Render

import la "core:math/linalg"
import "core:testing"

// Seams: Spot_Shadows_Choose and Spot_Shadow_Matrix.

shadowed_spot :: proc(position: [3]f32) -> Light {
	light := Light_Spot(position, {0, 0, -1}, {1, 1, 1}, 100, 30, 15, 30)
	light.casts_shadow = true
	return light
}

project :: proc(matrix_: matrix[4, 4]f32, point: [3]f32) -> [3]f32 {
	clip := matrix_ * [4]f32{point.x, point.y, point.z, 1}
	return clip.xyz / clip.w
}

@(test)
test_axis_point_projects_to_the_map_centre_inside_the_depth_range :: proc(t: ^testing.T) {
	matrix_ := Spot_Shadow_Matrix(shadowed_spot({0, 5, 0}))
	for distance in ([3]f32{1, 10, 29}) {
		ndc := project(matrix_, {0, 5, -distance})
		testing.expect(t, abs(ndc.x) < 1e-4 && abs(ndc.y) < 1e-4)
		testing.expect(t, ndc.z > -1 && ndc.z < 1)
	}
}

// The cone's outer edge (30 degrees) must land inside the map; a point 45 degrees off axis must land outside it.
@(test)
test_cone_edge_is_inside_the_map_and_far_off_axis_is_outside :: proc(t: ^testing.T) {
	matrix_ := Spot_Shadow_Matrix(shadowed_spot({0, 0, 0}))
	edge := project(matrix_, {10 * 0.5, 0, -10 * 0.866}) // 30 degrees off axis
	testing.expect(t, abs(edge.x) < 1 && abs(edge.y) < 1)
	outside := project(matrix_, {10, 0, -10}) // 45 degrees
	testing.expect(t, abs(outside.x) > 1)
}

@(test)
test_straight_down_light_has_a_valid_matrix :: proc(t: ^testing.T) {
	light := Light_Spot({0, 10, 0}, {0, -1, 0}, {1, 1, 1}, 100, 30, 15, 30)
	ndc := project(Spot_Shadow_Matrix(light), {0, 0, 0})
	testing.expect(t, abs(ndc.x) < 1e-4 && abs(ndc.y) < 1e-4 && ndc.z > -1 && ndc.z < 1)
}

@(test)
test_choose_takes_the_nearest_shadowed_spots_only :: proc(t: ^testing.T) {
	lights: [dynamic]Light
	defer delete(lights)
	for distance in ([6]f32{50, 10, 30, 20, 40, 5}) do append(&lights, shadowed_spot({distance, 0, 0}))
	append(&lights, Light_Point({1, 0, 0}, {1, 1, 1}, 10, 10)) // Not a spot.
	unshadowed := Light_Spot({2, 0, 0}, {0, 0, -1}, {1, 1, 1}, 10, 10, 10, 20) // Does not ask for a shadow.
	append(&lights, unshadowed)
	set := Spot_Shadows_Choose(lights[:], {0, 0, 0})
	testing.expect_value(t, set.count, SPOT_SHADOWS_MAX)
	testing.expect_value(t, set.light_index, [SPOT_SHADOWS_MAX]int{5, 1, 3, 2}) // Distances 5, 10, 20, 30, nearest first.
}

@(test)
test_choose_with_few_candidates_leaves_unused_slots_empty :: proc(t: ^testing.T) {
	lights := []Light{shadowed_spot({3, 0, 0})}
	set := Spot_Shadows_Choose(lights, {0, 0, 0})
	testing.expect_value(t, set.count, 1)
	testing.expect_value(t, set.light_index, [SPOT_SHADOWS_MAX]int{0, -1, -1, -1})
	empty := Spot_Shadows_Choose(nil, {0, 0, 0})
	testing.expect_value(t, empty.count, 0)
}
