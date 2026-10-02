package Render

import "core:math"
import "core:math/linalg"
import "core:testing"

// Camera at the origin looking down -Z: 90 degree field of view, aspect 1, near 1, far 100.
test_frustum :: proc() -> (Frustum, Camera) {
	camera := Camera_Look_At({0, 0, 0}, {0, 0, -1}, 90, 1, 1, 100)
	return Frustum_From_View_Projection(camera.view_projection), camera
}

@(test)
test_spheres_inside_outside_and_straddling :: proc(t: ^testing.T) {
	frustum, _ := test_frustum()
	testing.expect(t, Frustum_Intersects_Sphere(frustum, {0, 0, -50}, 1))
	testing.expect(t, !Frustum_Intersects_Sphere(frustum, {0, 0, 50}, 1)) // Behind the camera.
	testing.expect(t, !Frustum_Intersects_Sphere(frustum, {0, 0, -150}, 1)) // Beyond the far plane.
	testing.expect(t, !Frustum_Intersects_Sphere(frustum, {200, 0, -50}, 1)) // Far to the right.
	testing.expect(t, Frustum_Intersects_Sphere(frustum, {0, 0, -100.5}, 1)) // Straddles the far plane.
	testing.expect(t, Frustum_Intersects_Sphere(frustum, {52, 0, -50}, 3)) // Straddles the right plane (edge at x = 50).
}

@(test)
test_boxes_inside_outside_and_straddling :: proc(t: ^testing.T) {
	frustum, _ := test_frustum()
	testing.expect(t, Frustum_Intersects_Aabb(frustum, {-1, -1, -11}, {1, 1, -9}))
	testing.expect(t, Frustum_Intersects_Aabb(frustum, {-1, -1, -1}, {1, 1, 1})) // Contains the camera.
	testing.expect(t, !Frustum_Intersects_Aabb(frustum, {-300, -5, -60}, {-200, 5, -40})) // Entirely left.
	testing.expect(t, Frustum_Intersects_Aabb(frustum, {40, -1, -50}, {60, 1, -40})) // Straddles the right plane.
	testing.expect(t, Frustum_Intersects_Aabb(frustum, {-1000, -1000, -1000}, {1000, 1000, 1000})) // Contains everything.
	testing.expect(t, !Frustum_Intersects_Aabb(frustum, {-5, -5, 20}, {5, 5, 30})) // Behind.
}

// Conservative: no false negatives. Any point truly inside the frustum must pass, however small the box around it.
@(test)
test_points_inside_the_frustum_are_never_culled :: proc(t: ^testing.T) {
	frustum, camera := test_frustum()
	inverse := linalg.inverse(camera.view_projection)
	for index in 0 ..< 1000 {
		ndc := [4]f32{
			f32(index * 7 % 199) / 99.5 - 1,
			f32(index * 13 % 197) / 98.5 - 1,
			f32(index * 29 % 193) / 96.5 - 1,
			1,
		}
		ndc *= 0.98
		ndc.w = 1
		world := inverse * ndc
		point := world.xyz / world.w
		testing.expect(t, Frustum_Intersects_Aabb(frustum, point - 0.01, point + 0.01))
		testing.expect(t, Frustum_Intersects_Sphere(frustum, point, 0.01))
	}
}

// Seam: Interior_Index_At. A point is in a room only inside its box in the box's own (turned) axes; the first matching room wins.
@(test)
test_interior_index_finds_the_room_a_point_is_in :: proc(t: ^testing.T) {
	rooms := []Interior_Volume{
		{center = {0, 1, 0}, half_extents = {5, 1, 2}},
		{center = {20, 1, 0}, half_extents = {5, 1, 2}, yaw_radians = math.PI / 2}, // Long along Z once turned.
	}
	testing.expect_value(t, Interior_Index_At(rooms, {4, 1, 1}), 0)
	testing.expect_value(t, Interior_Index_At(rooms, {4, 1, 3}), -1) // Beyond the first room's 2 m depth.
	testing.expect_value(t, Interior_Index_At(rooms, {20, 1, 4}), 1) // 4 m along Z is inside the turned room (half length 5).
	testing.expect_value(t, Interior_Index_At(rooms, {24, 1, 0}), -1) // 4 m along X is outside it (half width 2).
	testing.expect_value(t, Interior_Index_At(rooms, {0, 3, 0}), -1) // Above the ceiling.
	testing.expect_value(t, Interior_Index_At(nil, {0, 0, 0}), -1)
}
