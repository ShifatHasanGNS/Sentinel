package World

import "core:math"

Chunk_Coordinate :: [2]i32

// The set of chunks currently resident. The caller builds data for to_load and frees data for to_unload after each update.
Chunk_Stream :: struct {
	loaded: map[Chunk_Coordinate]struct{},
}

Chunk_Of_Position :: proc(x, z, chunk_size_meters: f32) -> Chunk_Coordinate {
	return {i32(math.floor(x / chunk_size_meters)), i32(math.floor(z / chunk_size_meters))}
}

// Loads every chunk within load_radius_chunks of the position (nearest first) and unloads those beyond unload_radius_chunks.
// unload > load is the hysteresis: stepping back over a chunk border does not drop and rebuild chunks.
Chunk_Stream_Update :: proc(stream: ^Chunk_Stream, x, z, chunk_size_meters: f32, load_radius_chunks, unload_radius_chunks: int, to_load, to_unload: ^[dynamic]Chunk_Coordinate) {
	assert(unload_radius_chunks > load_radius_chunks, "Chunk_Stream_Update: unload radius must exceed load radius")
	clear(to_load)
	clear(to_unload)
	center := Chunk_Of_Position(x, z, chunk_size_meters)
	// Ring by ring outward from the centre, so nearer chunks come first without sorting.
	for ring in 0 ..= i32(load_radius_chunks) {
		for offset_z in -ring ..= ring {
			for offset_x in -ring ..= ring {
				if max(abs(offset_x), abs(offset_z)) != ring do continue
				chunk := center + {offset_x, offset_z}
				if chunk in stream.loaded do continue
				append(to_load, chunk)
				stream.loaded[chunk] = {}
			}
		}
	}
	for chunk in stream.loaded {
		if chebyshev_distance(chunk, center) > i32(unload_radius_chunks) do append(to_unload, chunk)
	}
	for chunk in to_unload do delete_key(&stream.loaded, chunk)
}

Chunk_Stream_Destroy :: proc(stream: ^Chunk_Stream) {
	delete(stream.loaded)
	stream^ = {}
}

@(private = "file")
chebyshev_distance :: proc(a, b: Chunk_Coordinate) -> i32 {
	return max(abs(a.x - b.x), abs(a.y - b.y))
}
