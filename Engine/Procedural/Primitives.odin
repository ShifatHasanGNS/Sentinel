package Procedural

import "core:math"
import "core:math/linalg"

Box_Create :: proc(size: [3]f32, segments := [3]int{1, 1, 1}) -> (mesh: Mesh) {
	assert(size.x > 0 && size.y > 0 && size.z > 0, "Box_Create: size must be positive")
	assert(segments.x >= 1 && segments.y >= 1 && segments.z >= 1, "Box_Create: needs at least 1 segment per axis")
	half := size / 2
	// (normal, u axis, v axis) with cross(u, v) = normal, so each grid is counter-clockwise seen from outside.
	faces := [6][3][3]f32{
		{{1, 0, 0}, {0, 1, 0}, {0, 0, 1}},
		{{-1, 0, 0}, {0, 0, 1}, {0, 1, 0}},
		{{0, 1, 0}, {0, 0, 1}, {1, 0, 0}},
		{{0, -1, 0}, {1, 0, 0}, {0, 0, 1}},
		{{0, 0, 1}, {1, 0, 0}, {0, 1, 0}},
		{{0, 0, -1}, {0, 1, 0}, {1, 0, 0}},
	}
	for face in faces {
		normal, u_axis, v_axis := face[0], face[1], face[2]
		columns, rows := segments_along(u_axis, segments), segments_along(v_axis, segments)
		center := normal * extent_along(normal, half)
		first := u32(len(mesh.vertices))
		for row in 0 ..= rows {
			for column in 0 ..= columns {
				fraction := [2]f32{f32(column) / f32(columns), f32(row) / f32(rows)}
				offset := fraction * 2 - 1
				position := center + u_axis * (offset.x * extent_along(u_axis, half)) + v_axis * (offset.y * extent_along(v_axis, half))
				append(&mesh.vertices, Vertex{position, normal, {u_axis.x, u_axis.y, u_axis.z, 1}, fraction})
			}
		}
		append_grid_indices(&mesh, first, columns, rows, true)
	}
	return mesh
}

@(private = "file")
segments_along :: proc(axis: [3]f32, segments: [3]int) -> int {
	return int(abs(axis.x)) * segments.x + int(abs(axis.y)) * segments.y + int(abs(axis.z)) * segments.z
}

@(private = "file")
extent_along :: proc(axis, half: [3]f32) -> f32 {
	return abs(axis.x) * half.x + abs(axis.y) * half.y + abs(axis.z) * half.z
}

// u runs around the +Y axis (counter-clockwise seen from above), v from the south pole (0) to the north pole (1).
Sphere_Create :: proc(radius: f32, segments, rings: int) -> (mesh: Mesh) {
	assert(radius > 0, "Sphere_Create: radius must be positive")
	assert(segments >= 3 && rings >= 2, "Sphere_Create: needs segments >= 3 and rings >= 2")
	for ring in 0 ..= rings {
		v := f32(ring) / f32(rings)
		latitude := v * math.PI - math.PI / 2
		for segment in 0 ..= segments {
			u := f32(segment) / f32(segments)
			longitude := u * 2 * math.PI
			normal := [3]f32{math.cos(latitude) * math.cos(longitude), math.sin(latitude), math.cos(latitude) * math.sin(longitude)}
			tangent := [4]f32{-math.sin(longitude), 0, math.cos(longitude), -1}
			append(&mesh.vertices, Vertex{normal * radius, normal, tangent, {u, v}})
		}
	}
	append_grid_indices(&mesh, 0, segments, rings)
	return mesh
}

// Triangles for a (columns+1) x (rows+1) vertex grid. By default its (u, v) frame is left-handed seen from outside
// (cross(u, v) points inward); pass u_cross_v_is_outward for the opposite handedness.
@(private = "file")
append_grid_indices :: proc(mesh: ^Mesh, first_vertex: u32, columns, rows: int, u_cross_v_is_outward := false) {
	stride := u32(columns + 1)
	for row in 0 ..< u32(rows) {
		for column in 0 ..< u32(columns) {
			corner := first_vertex + row * stride + column
			if u_cross_v_is_outward {
				append(&mesh.indices, corner, corner + 1, corner + stride + 1, corner, corner + stride + 1, corner + stride)
			} else {
				append(&mesh.indices, corner, corner + stride, corner + stride + 1, corner, corner + stride + 1, corner + 1)
			}
		}
	}
}

// Axis +Y, centred on the origin. Side u runs counter-clockwise seen from above; caps are planar discs.
Cylinder_Create :: proc(radius, height: f32, segments: int, height_segments := 1) -> (mesh: Mesh) {
	assert(radius > 0 && height > 0, "Cylinder_Create: radius and height must be positive")
	assert(segments >= 3 && height_segments >= 1, "Cylinder_Create: needs segments >= 3 and height_segments >= 1")
	for ring in 0 ..= height_segments {
		v := f32(ring) / f32(height_segments)
		for segment in 0 ..= segments {
			u := f32(segment) / f32(segments)
			longitude := u * 2 * math.PI
			normal := [3]f32{math.cos(longitude), 0, math.sin(longitude)}
			position := normal * radius + {0, (v - 0.5) * height, 0}
			append(&mesh.vertices, Vertex{position, normal, {-math.sin(longitude), 0, math.cos(longitude), -1}, {u, v}})
		}
	}
	append_grid_indices(&mesh, 0, segments, height_segments)
	append_disc_cap(&mesh, radius, height / 2, true, segments)
	append_disc_cap(&mesh, radius, -height / 2, false, segments)
	return mesh
}

// Planar disc facing +Y (facing_up) or -Y, texture-mapped as the inscribed circle of the unit square.
@(private = "file")
append_disc_cap :: proc(mesh: ^Mesh, radius, y: f32, facing_up: bool, segments: int) {
	normal_y: f32 = 1 if facing_up else -1
	v_sign: f32 = -1 if facing_up else 1 // Keeps bitangent = cross(normal, +X) pointing along increasing v.
	center := u32(len(mesh.vertices))
	append(&mesh.vertices, Vertex{{0, y, 0}, {0, normal_y, 0}, {1, 0, 0, 1}, {0.5, 0.5}})
	for segment in 0 ..= segments {
		longitude := f32(segment) / f32(segments) * 2 * math.PI
		offset := [2]f32{math.cos(longitude), math.sin(longitude)}
		append(&mesh.vertices, Vertex{{offset.x * radius, y, offset.y * radius}, {0, normal_y, 0}, {1, 0, 0, 1}, {0.5 + 0.5 * offset.x, 0.5 + v_sign * 0.5 * offset.y}})
	}
	for segment in 0 ..< u32(segments) {
		ring := center + 1 + segment
		if facing_up {
			append(&mesh.indices, center, ring + 1, ring)
		} else {
			append(&mesh.indices, center, ring, ring + 1)
		}
	}
}

// Axis +Y, base at -height/2, apex at +height/2. The side normal is perpendicular to the slant: (height cos, radius, height sin) normalised.
Cone_Create :: proc(radius, height: f32, segments: int) -> (mesh: Mesh) {
	assert(radius > 0 && height > 0, "Cone_Create: radius and height must be positive")
	assert(segments >= 3, "Cone_Create: needs segments >= 3")
	for ring_radius, ring in ([2]f32{radius, 0}) {
		for segment in 0 ..= segments {
			u := f32(segment) / f32(segments)
			longitude := u * 2 * math.PI
			outward := [3]f32{math.cos(longitude), 0, math.sin(longitude)}
			normal := linalg.normalize(outward * height + {0, radius, 0})
			position := outward * ring_radius + {0, height * (f32(ring) - 0.5), 0}
			append(&mesh.vertices, Vertex{position, normal, {-math.sin(longitude), 0, math.cos(longitude), -1}, {u, f32(ring)}})
		}
	}
	append_grid_indices(&mesh, 0, segments, 1)
	append_disc_cap(&mesh, radius, -height / 2, false, segments)
	return mesh
}

// A cylinder shaft of shaft_height capped by two hemispheres; v advances with arc length from the south tip to the north tip.
Capsule_Create :: proc(radius, shaft_height: f32, segments, rings_per_hemisphere: int, shaft_segments := 1) -> (mesh: Mesh) {
	assert(radius > 0 && shaft_height >= 0, "Capsule_Create: radius must be positive and shaft_height non-negative")
	assert(segments >= 3 && rings_per_hemisphere >= 1 && shaft_segments >= 1, "Capsule_Create: needs segments >= 3, rings_per_hemisphere >= 1, shaft_segments >= 1")
	row_count := 2 * rings_per_hemisphere + shaft_segments
	for row in 0 ..= row_count {
		ring := capsule_ring(row, radius, shaft_height, rings_per_hemisphere, shaft_segments)
		for segment in 0 ..= segments {
			u := f32(segment) / f32(segments)
			longitude := u * 2 * math.PI
			normal := [3]f32{math.cos(ring.latitude) * math.cos(longitude), math.sin(ring.latitude), math.cos(ring.latitude) * math.sin(longitude)}
			position := normal * radius + {0, ring.center_height, 0}
			append(&mesh.vertices, Vertex{position, normal, {-math.sin(longitude), 0, math.cos(longitude), -1}, {u, ring.v}})
		}
	}
	append_grid_indices(&mesh, 0, segments, row_count)
	return mesh
}

@(private = "file")
Capsule_Ring :: struct {
	latitude:      f32,
	center_height: f32,
	v:             f32,
}

// Rows run south tip -> south equator -> shaft rings -> north equator -> north tip; v is arc length over total arc length.
@(private = "file")
capsule_ring :: proc(row: int, radius, shaft_height: f32, rings_per_hemisphere, shaft_segments: int) -> Capsule_Ring {
	arc_total := math.PI * radius + shaft_height
	south_rows := rings_per_hemisphere
	north_start := rings_per_hemisphere + shaft_segments
	switch {
	case row <= south_rows:
		latitude := -math.PI / 2 * (1 - f32(row) / f32(rings_per_hemisphere))
		return {latitude, -shaft_height / 2, radius * (latitude + math.PI / 2) / arc_total}
	case row < north_start:
		along_shaft := f32(row - south_rows) / f32(shaft_segments)
		return {0, (along_shaft - 0.5) * shaft_height, (radius * math.PI / 2 + shaft_height * along_shaft) / arc_total}
	case:
		latitude := math.PI / 2 * f32(row - north_start) / f32(rings_per_hemisphere)
		return {latitude, shaft_height / 2, (radius * math.PI / 2 + shaft_height + radius * latitude) / arc_total}
	}
}

// Axis +Y. u runs around the main ring, v around the tube starting on the outer equator.
Torus_Create :: proc(radius_major, radius_minor: f32, segments_major, segments_minor: int) -> (mesh: Mesh) {
	assert(radius_minor > 0 && radius_major > radius_minor, "Torus_Create: needs radius_major > radius_minor > 0")
	assert(segments_major >= 3 && segments_minor >= 3, "Torus_Create: needs at least 3 segments each way")
	for ring in 0 ..= segments_minor {
		v := f32(ring) / f32(segments_minor)
		tube_angle := v * 2 * math.PI
		for segment in 0 ..= segments_major {
			u := f32(segment) / f32(segments_major)
			longitude := u * 2 * math.PI
			outward := [3]f32{math.cos(longitude), 0, math.sin(longitude)}
			normal := outward * math.cos(tube_angle) + {0, math.sin(tube_angle), 0}
			position := outward * radius_major + normal * radius_minor
			append(&mesh.vertices, Vertex{position, normal, {-math.sin(longitude), 0, math.cos(longitude), -1}, {u, v}})
		}
	}
	append_grid_indices(&mesh, 0, segments_major, segments_minor)
	return mesh
}

// A ramp: full height at the back (-Z), sloping to zero height at the front (+Z), centred on the origin.
Wedge_Create :: proc(size: [3]f32) -> (mesh: Mesh) {
	assert(size.x > 0 && size.y > 0 && size.z > 0, "Wedge_Create: size must be positive")
	half := size / 2
	back_bottom_left, back_bottom_right := [3]f32{-half.x, -half.y, -half.z}, [3]f32{half.x, -half.y, -half.z}
	back_top_left, back_top_right := [3]f32{-half.x, half.y, -half.z}, [3]f32{half.x, half.y, -half.z}
	front_bottom_left, front_bottom_right := [3]f32{-half.x, -half.y, half.z}, [3]f32{half.x, -half.y, half.z}
	append_flat_polygon(&mesh, {back_bottom_left, back_bottom_right, front_bottom_right, front_bottom_left}, {1, 0, 0}) // Floor.
	append_flat_polygon(&mesh, {back_bottom_right, back_bottom_left, back_top_left, back_top_right}, {-1, 0, 0}) // Back wall.
	append_flat_polygon(&mesh, {front_bottom_left, front_bottom_right, back_top_right, back_top_left}, {1, 0, 0}) // Slope.
	append_flat_polygon(&mesh, {back_bottom_right, back_top_right, front_bottom_right}, {0, 0, 1}) // +X side.
	append_flat_polygon(&mesh, {back_bottom_left, front_bottom_left, back_top_left}, {0, 0, -1}) // -X side.
	return mesh
}

// One flat face with corners listed counter-clockwise seen from outside. The normal follows from the winding;
// uv is the planar projection onto (tangent, bitangent), rescaled so the face fills [0, 1] in both directions.
@(private = "file")
append_flat_polygon :: proc(mesh: ^Mesh, corners: [][3]f32, tangent: [3]f32) {
	normal := linalg.normalize(linalg.cross(corners[1] - corners[0], corners[2] - corners[0]))
	bitangent := linalg.cross(normal, tangent)
	lowest, highest := [2]f32{max(f32), max(f32)}, [2]f32{min(f32), min(f32)}
	for corner in corners {
		projected := [2]f32{linalg.dot(corner, tangent), linalg.dot(corner, bitangent)}
		lowest = {min(lowest.x, projected.x), min(lowest.y, projected.y)}
		highest = {max(highest.x, projected.x), max(highest.y, projected.y)}
	}
	first := u32(len(mesh.vertices))
	for corner in corners {
		projected := [2]f32{linalg.dot(corner, tangent), linalg.dot(corner, bitangent)}
		append(&mesh.vertices, Vertex{corner, normal, {tangent.x, tangent.y, tangent.z, 1}, (projected - lowest) / (highest - lowest)})
	}
	for corner in 1 ..< u32(len(corners) - 1) do append(&mesh.indices, first, first + corner, first + corner + 1)
}
