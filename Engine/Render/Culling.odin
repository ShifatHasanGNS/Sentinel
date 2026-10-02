package Render

import la "core:math/linalg"

// Six inward-facing planes (a, b, c, d): a point p is inside when dot((a, b, c), p) + d >= 0 for all of them.
Frustum :: struct {
	planes: [6][4]f32,
}

// Gribb-Hartmann: with clip = M p and -w <= x, y, z <= w inside, each plane is the sum or difference of M's fourth row and one other row.
Frustum_From_View_Projection :: proc(view_projection: matrix[4, 4]f32) -> (frustum: Frustum) {
	row :: proc(m: matrix[4, 4]f32, index: int) -> [4]f32 {
		return {m[index, 0], m[index, 1], m[index, 2], m[index, 3]}
	}
	w := row(view_projection, 3)
	frustum.planes = {
		w + row(view_projection, 0), // Left.
		w - row(view_projection, 0), // Right.
		w + row(view_projection, 1), // Bottom.
		w - row(view_projection, 1), // Top.
		w + row(view_projection, 2), // Near.
		w - row(view_projection, 2), // Far.
	}
	for &plane in frustum.planes do plane /= la.length(plane.xyz)
	return
}

Frustum_Intersects_Sphere :: proc(frustum: Frustum, center: [3]f32, radius: f32) -> bool {
	for plane in frustum.planes {
		if la.dot(plane.xyz, center) + plane[3] < -radius do return false
	}
	return true
}

// Tests the box corner furthest along each plane normal: if even that corner is outside, the whole box is. Conservative at corners.
Frustum_Intersects_Aabb :: proc(frustum: Frustum, lowest, highest: [3]f32) -> bool {
	for plane in frustum.planes {
		corner := [3]f32{
			highest.x if plane.x >= 0 else lowest.x,
			highest.y if plane.y >= 0 else lowest.y,
			highest.z if plane.z >= 0 else lowest.z,
		}
		if la.dot(plane.xyz, corner) + plane[3] < 0 do return false
	}
	return true
}
