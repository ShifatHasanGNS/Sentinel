package Procedural

import "core:math"
import "core:math/linalg"

// Rolling hills from fbm, flattened to a plateau around plateau_center (where a base can be built) and blended back to hills
// over plateau_blend_meters. Heights stay within amplitude_meters of base_height_meters.
Terrain :: struct {
	seed:                  u32,
	base_height_meters:    f32,
	amplitude_meters:      f32,
	frequency_per_meter:   f32,
	octaves:               int,
	plateau_center:        [2]f32,
	plateau_radius_meters: f32,
	plateau_blend_meters:  f32,
}

Terrain_Height :: proc(terrain: Terrain, x, z: f32) -> f32 {
	distance_from_plateau := linalg.length([2]f32{x, z} - terrain.plateau_center)
	// smoothstep is C1, so the plateau meets the hills without a visible crease.
	hills_weight := math.smoothstep(terrain.plateau_radius_meters, terrain.plateau_radius_meters + terrain.plateau_blend_meters, distance_from_plateau)
	noise := Noise_Fbm_3({x * terrain.frequency_per_meter, 0, z * terrain.frequency_per_meter}, terrain.seed, terrain.octaves)
	return terrain.base_height_meters + terrain.amplitude_meters * noise * hills_weight
}

// A chunk_size x chunk_size square at chunk * chunk_size, sampled on a (cells + 1)^2 grid; uv covers [0, 1] per chunk.
// Normals come from central differences of the height function itself, so shared edges of neighbouring chunks agree exactly.
// Heights are sampled once on a grid with a one-cell border, so each vertex's neighbours are lookups, not re-evaluations.
Terrain_Chunk_Mesh :: proc(terrain: Terrain, chunk: [2]i32, chunk_size_meters: f32, cells: int) -> (mesh: Mesh) {
	assert(chunk_size_meters > 0 && cells >= 1, "Terrain_Chunk_Mesh: invalid size")
	cell := chunk_size_meters / f32(cells)
	origin := [2]f32{f32(chunk.x), f32(chunk.y)} * chunk_size_meters
	border_stride := cells + 3
	heights := make([]f32, border_stride * border_stride, context.temp_allocator)
	for row in 0 ..< border_stride {
		for column in 0 ..< border_stride {
			heights[row * border_stride + column] = Terrain_Height(terrain, origin.x + f32(column - 1) * cell, origin.y + f32(row - 1) * cell)
		}
	}
	height_at :: proc(heights: []f32, stride, column, row: int) -> f32 {
		return heights[(row + 1) * stride + (column + 1)]
	}
	for row in 0 ..= cells {
		for column in 0 ..= cells {
			slope_x := (height_at(heights, border_stride, column + 1, row) - height_at(heights, border_stride, column - 1, row)) / (2 * cell)
			slope_z := (height_at(heights, border_stride, column, row + 1) - height_at(heights, border_stride, column, row - 1)) / (2 * cell)
			normal := linalg.normalize([3]f32{-slope_x, 1, -slope_z})
			tangent := linalg.normalize([3]f32{1, slope_x, 0})
			uv := [2]f32{f32(column), f32(row)} / f32(cells)
			position := [3]f32{origin.x + f32(column) * cell, height_at(heights, border_stride, column, row), origin.y + f32(row) * cell}
			append(&mesh.vertices, Vertex{position, normal, {tangent.x, tangent.y, tangent.z, -1}, uv})
		}
	}
	stride := u32(cells + 1)
	for row in 0 ..< u32(cells) {
		for column in 0 ..< u32(cells) {
			corner := row * stride + column
			append(&mesh.indices, corner, corner + stride, corner + 1, corner + 1, corner + stride, corner + stride + 1)
		}
	}
	return mesh
}
