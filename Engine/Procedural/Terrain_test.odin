package Procedural

import "core:math"
import "core:math/linalg"
import "core:testing"

test_terrain :: proc() -> Terrain {
	return Terrain{
		seed = 17,
		base_height_meters = 10,
		amplitude_meters = 20,
		frequency_per_meter = 1.0 / 120,
		octaves = 5,
		plateau_center = {0, 0},
		plateau_radius_meters = 60,
		plateau_blend_meters = 80,
	}
}

@(test)
test_terrain_is_deterministic_and_bounded :: proc(t: ^testing.T) {
	terrain := test_terrain()
	for index in 0 ..< 2000 {
		x, z := f32(index) * 3.7 - 3000, f32(index) * -2.3 + 1500
		height := Terrain_Height(terrain, x, z)
		testing.expect_value(t, height, Terrain_Height(terrain, x, z))
		testing.expect(t, abs(height - terrain.base_height_meters) <= terrain.amplitude_meters)
	}
}

@(test)
test_plateau_is_flat_and_the_land_outside_is_not :: proc(t: ^testing.T) {
	terrain := test_terrain()
	for angle in 0 ..< 36 {
		direction := [2]f32{math.cos(f32(angle) * 0.1745), math.sin(f32(angle) * 0.1745)}
		for radius in ([4]f32{0, 20, 45, 60}) {
			point := direction * radius
			testing.expect_value(t, Terrain_Height(terrain, point.x, point.y), terrain.base_height_meters)
		}
	}
	lowest, highest: f32 = max(f32), min(f32)
	for index in 0 ..< 400 {
		height := Terrain_Height(terrain, 400 + f32(index) * 5, 300 - f32(index) * 3)
		lowest, highest = min(lowest, height), max(highest, height)
	}
	testing.expect(t, highest - lowest > 5)
}

// The blend ring between plateau and hills must have no cliff: the height changes no faster than the steepest slope allowed.
@(test)
test_terrain_height_is_continuous_across_the_plateau_blend :: proc(t: ^testing.T) {
	terrain := test_terrain()
	step: f32 = 0.05
	slope_bound := terrain.amplitude_meters * (15.5 * terrain.frequency_per_meter + 1.5 / terrain.plateau_blend_meters) * 1.1
	for index in 0 ..< 3000 {
		x, z := f32(index) * 0.11 - 100, f32(index) * 0.07 - 60
		change := abs(Terrain_Height(terrain, x + step, z) - Terrain_Height(terrain, x, z))
		testing.expectf(t, change <= slope_bound * step, "jump %f at (%f, %f)", change, x, z)
	}
}

@(test)
test_chunk_mesh_is_valid_with_the_expected_counts :: proc(t: ^testing.T) {
	mesh := Terrain_Chunk_Mesh(test_terrain(), {3, -2}, 64, 16)
	defer Mesh_Destroy(&mesh)
	expect_valid_mesh(t, mesh, "terrain chunk")
	testing.expect_value(t, len(mesh.vertices), 17 * 17)
	testing.expect_value(t, len(mesh.indices), 16 * 16 * 6)
	terrain := test_terrain()
	for vertex in mesh.vertices {
		testing.expect_value(t, vertex.position.y, Terrain_Height(terrain, vertex.position.x, vertex.position.z))
		testing.expect(t, vertex.position.x >= 3 * 64 && vertex.position.x <= 4 * 64)
		testing.expect(t, vertex.position.z >= -2 * 64 && vertex.position.z <= -1 * 64)
	}
}

// Neighbouring chunks sample the same height function along the shared edge, so there are no cracks and no lighting seams.
@(test)
test_neighbouring_chunks_share_identical_border_vertices :: proc(t: ^testing.T) {
	terrain := test_terrain()
	cells := 16
	west := Terrain_Chunk_Mesh(terrain, {0, 0}, 64, cells)
	defer Mesh_Destroy(&west)
	east := Terrain_Chunk_Mesh(terrain, {1, 0}, 64, cells)
	defer Mesh_Destroy(&east)
	north := Terrain_Chunk_Mesh(terrain, {0, 1}, 64, cells)
	defer Mesh_Destroy(&north)
	stride := cells + 1
	for index in 0 ..= cells {
		testing.expect_value(t, west.vertices[index * stride + cells].position, east.vertices[index * stride].position)
		testing.expect_value(t, west.vertices[index * stride + cells].normal, east.vertices[index * stride].normal)
		testing.expect_value(t, west.vertices[cells * stride + index].position, north.vertices[index].position)
		testing.expect_value(t, west.vertices[cells * stride + index].normal, north.vertices[index].normal)
	}
}

// Independent check: a normal built from slopes measured with a much smaller step must agree with the mesh's normal.
@(test)
test_chunk_normals_match_measured_slopes :: proc(t: ^testing.T) {
	terrain := test_terrain()
	mesh := Terrain_Chunk_Mesh(terrain, {5, 4}, 64, 32)
	defer Mesh_Destroy(&mesh)
	step: f32 = 0.25
	for vertex in mesh.vertices {
		x, z := vertex.position.x, vertex.position.z
		slope_x := (Terrain_Height(terrain, x + step, z) - Terrain_Height(terrain, x - step, z)) / (2 * step)
		slope_z := (Terrain_Height(terrain, x, z + step) - Terrain_Height(terrain, x, z - step)) / (2 * step)
		expected := linalg.normalize([3]f32{-slope_x, 1, -slope_z})
		testing.expect(t, linalg.dot(vertex.normal, expected) > 0.998)
	}
}
