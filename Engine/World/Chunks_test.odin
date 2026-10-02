package World

import "core:testing"

@(test)
test_chunk_of_position_rounds_toward_negative_infinity :: proc(t: ^testing.T) {
	testing.expect_value(t, Chunk_Of_Position(0, 0, 64), Chunk_Coordinate{0, 0})
	testing.expect_value(t, Chunk_Of_Position(63.9, 64, 64), Chunk_Coordinate{0, 1})
	testing.expect_value(t, Chunk_Of_Position(-0.1, -64.1, 64), Chunk_Coordinate{-1, -2})
}

@(test)
test_first_update_loads_the_square_nearest_first :: proc(t: ^testing.T) {
	stream: Chunk_Stream
	defer Chunk_Stream_Destroy(&stream)
	to_load, to_unload := make([dynamic]Chunk_Coordinate), make([dynamic]Chunk_Coordinate)
	defer delete(to_load)
	defer delete(to_unload)
	Chunk_Stream_Update(&stream, 10, 10, 64, 2, 3, &to_load, &to_unload)
	testing.expect_value(t, len(to_load), 25)
	testing.expect_value(t, len(to_unload), 0)
	testing.expect_value(t, to_load[0], Chunk_Coordinate{0, 0})
	for index in 1 ..< len(to_load) {
		previous, current := to_load[index - 1], to_load[index]
		testing.expect(t, max(abs(previous.x), abs(previous.y)) <= max(abs(current.x), abs(current.y)))
	}
}

@(test)
test_standing_still_changes_nothing :: proc(t: ^testing.T) {
	stream: Chunk_Stream
	defer Chunk_Stream_Destroy(&stream)
	to_load, to_unload := make([dynamic]Chunk_Coordinate), make([dynamic]Chunk_Coordinate)
	defer delete(to_load)
	defer delete(to_unload)
	Chunk_Stream_Update(&stream, 10, 10, 64, 2, 3, &to_load, &to_unload)
	Chunk_Stream_Update(&stream, 12, 8, 64, 2, 3, &to_load, &to_unload)
	testing.expect_value(t, len(to_load), 0)
	testing.expect_value(t, len(to_unload), 0)
}

// The unload radius is wider than the load radius, so a chunk is not dropped the moment the player steps back over a border.
@(test)
test_moving_loads_ahead_and_unloads_only_beyond_the_hysteresis_radius :: proc(t: ^testing.T) {
	stream: Chunk_Stream
	defer Chunk_Stream_Destroy(&stream)
	to_load, to_unload := make([dynamic]Chunk_Coordinate), make([dynamic]Chunk_Coordinate)
	defer delete(to_load)
	defer delete(to_unload)
	Chunk_Stream_Update(&stream, 10, 10, 64, 2, 3, &to_load, &to_unload)
	Chunk_Stream_Update(&stream, 74, 10, 64, 2, 3, &to_load, &to_unload) // One chunk east.
	testing.expect_value(t, len(to_load), 5)
	testing.expect_value(t, len(to_unload), 0)
	Chunk_Stream_Update(&stream, 202, 10, 64, 2, 3, &to_load, &to_unload) // Three chunks east of the start.
	testing.expect(t, len(to_unload) > 0)
	for chunk in to_unload do testing.expect(t, abs(chunk.x - 3) > 3 || abs(chunk.y) > 3)
	for chunk in to_load do testing.expect(t, abs(chunk.x - 3) <= 2 && abs(chunk.y) <= 2)
	testing.expect_value(t, len(stream.loaded), 25 + 5 + len(to_load) - len(to_unload))
}
