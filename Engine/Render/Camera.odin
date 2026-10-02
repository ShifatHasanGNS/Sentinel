package Render

import "core:math"
import la "core:math/linalg"

Camera :: struct {
	position:        [3]f32,
	forward:         [3]f32,
	view:            matrix[4, 4]f32,
	projection:      matrix[4, 4]f32,
	view_projection: matrix[4, 4]f32,
	near_meters:     f32,
	far_meters:      f32,
}

Camera_Look_At :: proc(position, target: [3]f32, fov_degrees, aspect, near_meters, far_meters: f32) -> Camera {
	assert(aspect > 0 && near_meters > 0 && far_meters > near_meters, "Camera_Look_At: invalid projection")
	projection := la.matrix4_perspective_f32(math.to_radians(fov_degrees), aspect, near_meters, far_meters)
	view := la.matrix4_look_at_f32(position, target, {0, 1, 0})
	return Camera{position, la.normalize(target - position), view, projection, projection * view, near_meters, far_meters}
}

// Field of view for a magnification: the image width scales as tan(fov / 2), so a zoom of k divides tan(fov / 2) by k.
Zoomed_Field_Of_View_Degrees :: proc(base_degrees, zoom: f32) -> f32 {
	assert(zoom > 0 && base_degrees > 0 && base_degrees < 180, "Zoomed_Field_Of_View_Degrees: invalid arguments")
	return 2 * math.to_degrees(math.atan(math.tan(math.to_radians(base_degrees) / 2) / zoom))
}
