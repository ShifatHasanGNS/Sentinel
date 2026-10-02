package Procedural

// PCG output hash: a well-mixed 32-bit integer hash, so lattice values carry no visible grid structure.
Hash_U32 :: proc(value: u32) -> u32 {
	state := value * 747796405 + 2891336453
	word := ((state >> ((state >> 28) + 4)) ~ state) * 277803737
	return (word >> 22) ~ word
}

Hash_Lattice_3 :: proc(x, y, z: i32, seed: u32) -> u32 {
	return Hash_U32(u32(x) ~ Hash_U32(u32(y) ~ Hash_U32(u32(z) ~ seed)))
}

// Maps a hash to [0, 1).
Hash_To_Unit_Float :: proc(hash: u32) -> f32 {
	return f32(hash >> 8) / f32(1 << 24)
}
