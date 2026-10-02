package Render

import "core:math"
import la "core:math/linalg"
import "core:testing"

test_camera :: proc(position, target: [3]f32) -> Camera {
	return Camera_Look_At(position, target, 60, 1.5, 0.5, 200)
}

@(test)
test_cascade_splits_blend_uniform_and_logarithmic :: proc(t: ^testing.T) {
	near, far: f32 = 0.5, 100
	uniform := Cascade_Splits(near, far, 0)
	logarithmic := Cascade_Splits(near, far, 1)
	blended := Cascade_Splits(near, far, 0.5)
	for index in 0 ..< CASCADE_COUNT {
		fraction := f32(index + 1) / CASCADE_COUNT
		testing.expect(t, abs(uniform[index] - (near + (far - near) * fraction)) < 1e-3)
		testing.expect(t, abs(logarithmic[index] - near * math.pow(far / near, fraction)) < 1e-3)
		testing.expect(t, abs(blended[index] - (uniform[index] + logarithmic[index]) / 2) < 1e-3)
		testing.expect(t, blended[index] > (blended[index - 1] if index > 0 else near))
	}
	testing.expect(t, abs(blended[CASCADE_COUNT - 1] - far) < 1e-3)
}

@(test)
test_every_slice_corner_lies_inside_its_cascade :: proc(t: ^testing.T) {
	camera := test_camera({0, 5, 0}, {3, 0, -10})
	cascades := Shadow_Cascades_Fit(camera, {-0.4, -1, -0.3}, 80, 0.75, 2048)
	previous := camera.near_meters
	for cascade in cascades {
		for corner in Frustum_Slice_Corners(camera, previous, cascade.far_distance) {
			clip := cascade.view_projection * [4]f32{corner.x, corner.y, corner.z, 1}
			testing.expect(t, abs(clip.x) <= 1 + 1e-4 && abs(clip.y) <= 1 + 1e-4 && clip.z >= -1 && clip.z <= 1)
			testing.expect_value(t, clip.w, 1) // Orthographic.
		}
		previous = cascade.far_distance
	}
}

// The bounding sphere of a frustum slice does not depend on which way the camera faces, so the cascade size, and with it
// the shadow texel density, stays constant while the camera turns. A tight box would resize and make shadow edges swim.
@(test)
test_cascade_size_does_not_change_when_the_camera_turns :: proc(t: ^testing.T) {
	light: [3]f32 = {-0.4, -1, -0.3}
	north := Shadow_Cascades_Fit(test_camera({0, 5, 0}, {0, 0, -10}), light, 80, 0.75, 2048)
	east := Shadow_Cascades_Fit(test_camera({0, 5, 0}, {10, 2, 0}), light, 80, 0.75, 2048)
	for index in 0 ..< CASCADE_COUNT {
		testing.expect(t, abs(north[index].view_projection[0, 0] - east[index].view_projection[0, 0]) < 1e-6)
		testing.expect(t, abs(north[index].texel_world_meters - east[index].texel_world_meters) < 1e-6)
	}
}

// Light-space translation moves in whole shadow texels, so a moving camera never makes shadow edges crawl across texels.
@(test)
test_cascade_translation_is_snapped_to_whole_texels :: proc(t: ^testing.T) {
	size: i32 = 2048
	for offset in 0 ..< 12 {
		position := [3]f32{f32(offset) * 0.037, 5, f32(offset) * -0.021}
		cascades := Shadow_Cascades_Fit(test_camera(position, position + {0, -5, -10}), {-0.4, -1, -0.3}, 80, 0.75, size)
		for cascade in cascades {
			for translation in ([2]f32{cascade.view_projection[0, 3], cascade.view_projection[1, 3]}) {
				texels := translation * f32(size) / 2
				testing.expect(t, abs(texels - math.round(texels)) < 2e-2 * max(1, abs(texels) / 1000))
			}
		}
	}
}
