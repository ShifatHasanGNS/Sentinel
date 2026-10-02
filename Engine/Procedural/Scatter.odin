package Procedural

import "core:math"
import "core:math/linalg"

// Where trees, rocks and the like may stand: gentle slopes only, and never on the plateau reserved for the base.
Scatter_Rules :: struct {
	seed:                    u32,
	attempts_per_chunk:      int,
	min_normal_y:            f32, // Surface must be at least this level (1 = flat, 0 = vertical).
	exclusion_radius_meters: f32, // Distance from the plateau centre inside which nothing is placed.
	scale_range:             [2]f32,
}

Scatter_Point :: struct {
	position:    [3]f32,
	yaw_radians: f32,
	scale:       f32,
	variant:     f32, // Stable roll in [0, 1) for choosing what to place here (tree, rock, bush).
}

// Candidate positions come from hashing (chunk, attempt, seed), so a chunk's layout never depends on load order or neighbours.
Scatter_Chunk :: proc(terrain: Terrain, rules: Scatter_Rules, chunk: [2]i32, chunk_size_meters: f32) -> (points: [dynamic]Scatter_Point) {
	origin := [2]f32{f32(chunk.x), f32(chunk.y)} * chunk_size_meters
	for attempt in 0 ..< rules.attempts_per_chunk {
		hash := Hash_Lattice_3(chunk.x, chunk.y, i32(attempt), rules.seed)
		x := origin.x + Hash_To_Unit_Float(hash) * chunk_size_meters
		z := origin.y + Hash_To_Unit_Float(Hash_U32(hash)) * chunk_size_meters
		if linalg.length([2]f32{x, z} - terrain.plateau_center) < rules.exclusion_radius_meters do continue
		if surface_normal_y(terrain, x, z) < rules.min_normal_y do continue
		yaw := Hash_To_Unit_Float(Hash_U32(hash ~ 0x9E3779B9)) * 2 * math.PI
		scale := math.lerp(rules.scale_range.x, rules.scale_range.y, Hash_To_Unit_Float(Hash_U32(hash ~ 0x85EBCA6B)))
		variant := Hash_To_Unit_Float(Hash_U32(hash ~ 0xC2B2AE35))
		append(&points, Scatter_Point{{x, Terrain_Height(terrain, x, z), z}, yaw, scale, variant})
	}
	return points
}

@(private = "file")
surface_normal_y :: proc(terrain: Terrain, x, z: f32) -> f32 {
	step: f32 = 0.5
	slope_x := (Terrain_Height(terrain, x + step, z) - Terrain_Height(terrain, x - step, z)) / (2 * step)
	slope_z := (Terrain_Height(terrain, x, z + step) - Terrain_Height(terrain, x, z - step)) / (2 * step)
	return linalg.normalize([3]f32{-slope_x, 1, -slope_z}).y
}
