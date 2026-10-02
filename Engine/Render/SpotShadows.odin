package Render

import "core:math"
import la "core:math/linalg"

SPOT_SHADOWS_MAX :: 4
SPOT_SHADOW_SIZE :: 1024
SPOT_SHADOW_NEAR_METERS :: 0.4
SPOT_SHADOW_MARGIN_DEGREES :: 6.0

// Which spot lights get a depth map this frame: the nearest few that ask for one. Everything else lights without shadows.
Spot_Shadow_Set :: struct {
	light_index: [SPOT_SHADOWS_MAX]int, // Index into Frame.local_lights, or -1 for an unused slot.
	matrices:    [SPOT_SHADOWS_MAX]matrix[4, 4]f32,
	count:       int,
}

Spot_Shadows_Choose :: proc(lights: []Light, camera_position: [3]f32) -> (set: Spot_Shadow_Set) {
	for &index in set.light_index do index = -1
	distances: [SPOT_SHADOWS_MAX]f32
	for light, index in lights {
		if light.kind != .Spot || !light.casts_shadow do continue
		distance := la.length(light.position - camera_position)
		slot := insertion_slot(set, distances, distance)
		if slot < 0 do continue
		for move := SPOT_SHADOWS_MAX - 1; move > slot; move -= 1 {
			set.light_index[move], distances[move] = set.light_index[move - 1], distances[move - 1]
		}
		set.light_index[slot], distances[slot] = index, distance
	}
	for slot in 0 ..< SPOT_SHADOWS_MAX {
		if set.light_index[slot] < 0 do break
		set.matrices[slot] = Spot_Shadow_Matrix(lights[set.light_index[slot]])
		set.count += 1
	}
	return set
}

// Position among the nearest-first slots, or -1 when the light is farther than every filled slot.
@(private = "file")
insertion_slot :: proc(set: Spot_Shadow_Set, distances: [SPOT_SHADOWS_MAX]f32, distance: f32) -> int {
	for slot in 0 ..< SPOT_SHADOWS_MAX {
		if set.light_index[slot] < 0 || distance < distances[slot] do return slot
	}
	return -1
}

// A perspective frustum from the light along its axis, just wider than the cone so the penumbra edge is inside the map.
// Perspective depth z' = (f + n)/(f - n) - 2fn/((f - n) z) is non-linear, so the compare bias lives in the shader as a world offset.
Spot_Shadow_Matrix :: proc(light: Light) -> matrix[4, 4]f32 {
	assert(light.kind == .Spot && light.range_meters > SPOT_SHADOW_NEAR_METERS, "Spot_Shadow_Matrix: needs a spot light with range")
	field_of_view := math.to_radians(2 * light.outer_angle_degrees + SPOT_SHADOW_MARGIN_DEGREES)
	projection := la.matrix4_perspective_f32(field_of_view, 1, SPOT_SHADOW_NEAR_METERS, light.range_meters)
	reference: [3]f32 = {0, 1, 0} if abs(light.direction.y) < 0.99 else {1, 0, 0}
	return projection * la.matrix4_look_at_f32(light.position, light.position + light.direction, reference)
}

// World size of one shadow texel per meter of distance from the light (for the shader's normal offset).
Spot_Shadow_Texel_Per_Meter :: proc(light: Light) -> f32 {
	half_field_of_view := math.to_radians(light.outer_angle_degrees + SPOT_SHADOW_MARGIN_DEGREES / 2)
	return 2 * math.tan(half_field_of_view) / SPOT_SHADOW_SIZE
}
