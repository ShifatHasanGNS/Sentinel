package Render

import "core:math"
import la "core:math/linalg"

CASCADE_COUNT :: 3
CASCADE_CASTER_MARGIN_METERS :: 60 // How far toward the light a shadow caster may stand and still be captured.
CASCADE_RADIUS_STEP_METERS :: 1.0 / 16

Cascade :: struct {
	view_projection:    matrix[4, 4]f32,
	far_distance:       f32, // View-space distance where this cascade ends.
	texel_world_meters: f32,
}

Cascade_Set :: [CASCADE_COUNT]Cascade

// Practical split scheme (Zhang et al. 2006): lambda blends uniform splits (even coverage) with logarithmic splits
// (constant texel-to-pixel ratio). Returns where each cascade ends; the first begins at the near plane.
Cascade_Splits :: proc(near, far, lambda: f32) -> (splits: [CASCADE_COUNT]f32) {
	for index in 0 ..< CASCADE_COUNT {
		fraction := f32(index + 1) / CASCADE_COUNT
		uniform := near + (far - near) * fraction
		logarithmic := near * math.pow(far / near, fraction)
		splits[index] = math.lerp(uniform, logarithmic, lambda)
	}
	splits[CASCADE_COUNT - 1] = far
	return
}

// The eight world-space corners of the camera frustum between two view-space distances: near plane first, then far.
Frustum_Slice_Corners :: proc(camera: Camera, near_distance, far_distance: f32) -> (corners: [8][3]f32) {
	tangent_x, tangent_y := 1 / camera.projection[0, 0], 1 / camera.projection[1, 1]
	camera_to_world := la.inverse(camera.view)
	for index in 0 ..< 8 {
		distance := near_distance if index < 4 else far_distance
		sign_x: f32 = 1 if index & 1 != 0 else -1
		sign_y: f32 = 1 if index & 2 != 0 else -1
		world := camera_to_world * [4]f32{sign_x * distance * tangent_x, sign_y * distance * tangent_y, -distance, 1}
		corners[index] = world.xyz
	}
	return
}

Shadow_Cascades_Fit :: proc(camera: Camera, light_direction: [3]f32, shadow_distance, lambda: f32, map_size: i32) -> (cascades: Cascade_Set) {
	assert(map_size > 2 && shadow_distance > camera.near_meters, "Shadow_Cascades_Fit: invalid map size or distance")
	splits := Cascade_Splits(camera.near_meters, min(shadow_distance, camera.far_meters), lambda)
	rotation := light_rotation(light_direction)
	previous := camera.near_meters
	for index in 0 ..< CASCADE_COUNT {
		cascades[index] = fit_cascade(Frustum_Slice_Corners(camera, previous, splits[index]), rotation, splits[index], map_size)
		previous = splits[index]
	}
	return
}

// Fits an orthographic box around the bounding sphere of a frustum slice. A sphere (not a tight box) keeps the size
// constant as the camera turns, and moving the box centre in whole texels keeps shadow edges from crawling.
@(private = "file")
fit_cascade :: proc(corners: [8][3]f32, rotation: matrix[3, 3]f32, far_distance: f32, map_size: i32) -> Cascade {
	center: [3]f32
	for corner in corners do center += corner / 8
	radius: f32
	for corner in corners do radius = max(radius, la.length(corner - center))
	radius = math.ceil(radius / CASCADE_RADIUS_STEP_METERS) * CASCADE_RADIUS_STEP_METERS
	// One spare texel on each side absorbs the snapping shift: half_size - radius = texel.
	half_size := radius * f32(map_size) / f32(map_size - 2)
	texel := 2 * half_size / f32(map_size)
	center_in_light := rotation * center
	snapped := [3]f32{math.floor(center_in_light.x / texel) * texel, math.floor(center_in_light.y / texel) * texel, center_in_light.z}
	translation := -snapped
	view := matrix[4, 4]f32{
		rotation[0, 0], rotation[0, 1], rotation[0, 2], translation.x,
		rotation[1, 0], rotation[1, 1], rotation[1, 2], translation.y,
		rotation[2, 0], rotation[2, 1], rotation[2, 2], translation.z,
		0, 0, 0, 1,
	}
	projection := la.matrix_ortho3d_f32(-half_size, half_size, -half_size, half_size, -(radius + CASCADE_CASTER_MARGIN_METERS), radius)
	return Cascade{projection * view, far_distance, texel}
}

// World to light-view rotation: x right, y up, z backward (against the light's travel direction).
@(private = "file")
light_rotation :: proc(light_direction: [3]f32) -> matrix[3, 3]f32 {
	forward := la.normalize(light_direction)
	reference: [3]f32 = {0, 1, 0} if abs(forward.y) < 0.99 else {1, 0, 0}
	right := la.normalize(la.cross(forward, reference))
	up := la.cross(right, forward)
	return matrix[3, 3]f32{
		right.x, right.y, right.z,
		up.x, up.y, up.z,
		-forward.x, -forward.y, -forward.z,
	}
}
