package Sandbox

import "../../Engine/Procedural"
import "../../Engine/Render"

CHUNK_SIZE_METERS :: 64.0
CHUNK_CELLS :: 32

// A square of terrain with the props scattered on it.
Chunk :: struct {
	mesh:    Render.Mesh,
	lowest:  [3]f32,
	highest: [3]f32,
	scatter: [dynamic]Procedural.Scatter_Point,
}

Chunk_Build :: proc(terrain: Procedural.Terrain, rules: Procedural.Scatter_Rules, coordinate: [2]i32) -> (chunk: Chunk) {
	cpu_mesh := Procedural.Terrain_Chunk_Mesh(terrain, coordinate, CHUNK_SIZE_METERS, CHUNK_CELLS)
	defer Procedural.Mesh_Destroy(&cpu_mesh)
	chunk.lowest, chunk.highest = Procedural.Mesh_Bounds(cpu_mesh)
	chunk.mesh = Render.Mesh_Upload(cpu_mesh)
	chunk.scatter = Procedural.Scatter_Chunk(terrain, rules, coordinate, CHUNK_SIZE_METERS)
	return chunk
}

Chunk_Destroy :: proc(chunk: ^Chunk) {
	Render.Mesh_Destroy(&chunk.mesh)
	delete(chunk.scatter)
}
