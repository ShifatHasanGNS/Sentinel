package Render

import "core:math"
import la "core:math/linalg"

Camera :: struct {
	position:        [3]f32,
	view_projection: matrix[4, 4]f32,
}

Camera_Look_At :: proc(position, target: [3]f32, fov_degrees, aspect, near_meters, far_meters: f32) -> Camera {
	assert(aspect > 0 && near_meters > 0 && far_meters > near_meters, "Camera_Look_At: invalid projection")
	projection := la.matrix4_perspective_f32(math.to_radians(fov_degrees), aspect, near_meters, far_meters)
	view := la.matrix4_look_at_f32(position, target, {0, 1, 0})
	return Camera{position, projection * view}
}
