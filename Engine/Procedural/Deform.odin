package Procedural

import "core:math"
import "core:math/linalg"

// Every deformer acts along the mesh's +Y axis (orient a part with its transform, not here).
Noise_Displace :: struct {
	amplitude: f32, // meters; fbm is in [-1, 1], so no vertex moves farther than this.
	frequency: f32, // cycles per meter of the first octave.
	octaves:   int,
	seed:      u32,
}

Taper :: struct {
	scale_at_bottom: f32,
	scale_at_top:    f32,
}

Twist :: struct {
	radians_total: f32, // rotation about Y accumulated from bottom to top.
}

Bend :: struct {
	curvature: f32, // 1 / radius of the circle the Y axis is wrapped onto, in 1/meters.
}

Bulge :: struct {
	amount: f32, // Fractional widening at mid-height; the ends are unchanged.
}

Deformer :: union {
	Noise_Displace,
	Taper,
	Twist,
	Bend,
	Bulge,
}

@(private = "file")
Position_Map :: struct {
	deformer:    Deformer,
	normal:      [3]f32,
	height_low:  f32,
	height_high: f32,
}

Mesh_Deform :: proc(mesh: ^Mesh, deformers: []Deformer) {
	for deformer in deformers {
		lowest, highest := Mesh_Bounds(mesh^)
		for &vertex in mesh.vertices {
			deform_vertex(&vertex, Position_Map{deformer, vertex.normal, lowest.y, highest.y})
		}
	}
}

// A deformer is a smooth map F from old to new positions. Surface directions then follow its Jacobian J = dF/dp:
// tangents transform as J*t and normals as the inverse transpose J^-T*n, which keeps n perpendicular to the deformed surface.
@(private = "file")
deform_vertex :: proc(vertex: ^Vertex, position_map: Position_Map) {
	jacobian := numerical_jacobian(position_map, vertex.position)
	handedness_sign: f32 = -1 if linalg.determinant(jacobian) < 0 else 1
	tangent := linalg.normalize(jacobian * vertex.tangent.xyz)
	vertex.normal = linalg.normalize(linalg.transpose(linalg.inverse(jacobian)) * vertex.normal)
	vertex.tangent = {tangent.x, tangent.y, tangent.z, vertex.tangent.w * handedness_sign}
	vertex.position = map_position(position_map, vertex.position)
}

// Central differences: error is O(step^2), well above float rounding at this step for meter-scale meshes.
@(private = "file")
numerical_jacobian :: proc(position_map: Position_Map, position: [3]f32) -> matrix[3, 3]f32 {
	step: f32 = 1e-3
	column :: proc(position_map: Position_Map, position, axis: [3]f32, step: f32) -> [3]f32 {
		return (map_position(position_map, position + axis * step) - map_position(position_map, position - axis * step)) / (2 * step)
	}
	x, y, z := column(position_map, position, {1, 0, 0}, step), column(position_map, position, {0, 1, 0}, step), column(position_map, position, {0, 0, 1}, step)
	return matrix[3, 3]f32{
		x.x, y.x, z.x,
		x.y, y.y, z.y,
		x.z, y.z, z.z,
	}
}

@(private = "file")
map_position :: proc(position_map: Position_Map, position: [3]f32) -> [3]f32 {
	span := position_map.height_high - position_map.height_low
	height_fraction: f32 = 0 if span <= 0 else (position.y - position_map.height_low) / span
	switch deformer in position_map.deformer {
	case Noise_Displace:
		noise := Noise_Fbm_3(position * deformer.frequency, deformer.seed, deformer.octaves)
		return position + position_map.normal * (deformer.amplitude * noise)
	case Taper:
		scale := math.lerp(deformer.scale_at_bottom, deformer.scale_at_top, height_fraction)
		return {position.x * scale, position.y, position.z * scale}
	case Twist:
		angle := deformer.radians_total * height_fraction
		return {
			position.x * math.cos(angle) + position.z * math.sin(angle),
			position.y,
			-position.x * math.sin(angle) + position.z * math.cos(angle),
		}
	case Bend:
		if abs(deformer.curvature) < 1e-6 do return position
		radius := 1 / deformer.curvature
		angle := deformer.curvature * position.y
		return {radius - (radius - position.x) * math.cos(angle), (radius - position.x) * math.sin(angle), position.z}
	case Bulge:
		scale := 1 + deformer.amount * math.sin(math.PI * height_fraction)
		return {position.x * scale, position.y, position.z * scale}
	}
	unreachable()
}
