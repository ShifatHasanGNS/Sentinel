package World

import "../Procedural"
import "core:math"
import la "core:math/linalg"

// A solid box turned about +Y: exact for walls and objects at any heading, where an axis-aligned box would swell at the corners
// and block empty air. Turning a local point by yaw: x' = x cos + z sin, z' = -x sin + z cos (the placement convention).
Solid :: struct {
	center:       [3]f32,
	half_extents: [3]f32,
	yaw_radians:  f32,
	disabled:     bool, // A door that is open: kept in the list so its index stays valid, but ignored.
}

Box_Solid :: proc(lowest, highest: [3]f32) -> Solid {
	return Solid{center = (lowest + highest) / 2, half_extents = (highest - lowest) / 2}
}

// A box given in an object's own frame (its ground point at the origin), placed at `position` with the object's heading.
Solid_From_Object_Box :: proc(box: Procedural.Collision_Box, position: [3]f32, yaw_radians: f32) -> Solid {
	local_center := (box.lowest + box.highest) / 2
	turned := rotate_about_y(local_center, yaw_radians)
	return Solid{center = position + turned, half_extents = (box.highest - box.lowest) / 2, yaw_radians = yaw_radians}
}

rotate_about_y :: proc(point: [3]f32, yaw_radians: f32) -> [3]f32 {
	sine, cosine := math.sin(yaw_radians), math.cos(yaw_radians)
	return {point.x * cosine + point.z * sine, point.y, -point.x * sine + point.z * cosine}
}

// The point in the solid's own axes (the inverse rotation), relative to its center.
to_local :: proc(solid: Solid, point: [3]f32) -> [3]f32 {
	return rotate_about_y(point - solid.center, -solid.yaw_radians)
}

// Ray against the solid: turn the ray into the solid's axes, use the slab test there, and turn the normal back.
Ray_Solid :: proc(origin, direction: [3]f32, solid: Solid) -> Ray_Hit {
	local_origin := to_local(solid, origin)
	local_direction := rotate_about_y(direction, -solid.yaw_radians)
	hit := Ray_Box(local_origin, local_direction, Procedural.Collision_Box{-solid.half_extents, solid.half_extents})
	if !hit.hit do return {}
	return Ray_Hit{true, hit.distance, origin + direction * hit.distance, la.normalize(rotate_about_y(hit.normal, solid.yaw_radians))}
}
