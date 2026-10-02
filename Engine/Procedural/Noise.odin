package Procedural

import "core:math"

// Improved Perlin gradient noise (Perlin 2002): each lattice corner contributes dot(gradient, offset),
// blended with the quintic fade 6t^5 - 15t^4 + 10t^3 whose first and second derivatives vanish at t = 0, 1,
// so the result is C2-continuous across cells. Zero at lattice points, range [-1, 1].
Noise_Gradient_3 :: proc(position: [3]f32, seed: u32) -> f32 {
	cell := [3]i32{i32(math.floor(position.x)), i32(math.floor(position.y)), i32(math.floor(position.z))}
	offset := position - {f32(cell.x), f32(cell.y), f32(cell.z)}
	fade := [3]f32{quintic_fade(offset.x), quintic_fade(offset.y), quintic_fade(offset.z)}
	corner :: proc(cell, step: [3]i32, offset: [3]f32, seed: u32) -> f32 {
		hash := Hash_Lattice_3(cell.x + step.x, cell.y + step.y, cell.z + step.z, seed)
		return edge_gradient_dot(hash, offset - {f32(step.x), f32(step.y), f32(step.z)})
	}
	along_x_00 := math.lerp(corner(cell, {0, 0, 0}, offset, seed), corner(cell, {1, 0, 0}, offset, seed), fade.x)
	along_x_10 := math.lerp(corner(cell, {0, 1, 0}, offset, seed), corner(cell, {1, 1, 0}, offset, seed), fade.x)
	along_x_01 := math.lerp(corner(cell, {0, 0, 1}, offset, seed), corner(cell, {1, 0, 1}, offset, seed), fade.x)
	along_x_11 := math.lerp(corner(cell, {0, 1, 1}, offset, seed), corner(cell, {1, 1, 1}, offset, seed), fade.x)
	return math.lerp(math.lerp(along_x_00, along_x_10, fade.y), math.lerp(along_x_01, along_x_11, fade.y), fade.z)
}

// Fractal Brownian motion: octaves of noise at lacunarity-scaled frequency and gain-scaled amplitude,
// divided by the total amplitude so the result stays within [-1, 1].
Noise_Fbm_3 :: proc(position: [3]f32, seed: u32, octaves: int, lacunarity: f32 = 2, gain: f32 = 0.5) -> f32 {
	assert(octaves >= 1, "Noise_Fbm_3: octaves must be >= 1")
	sum, amplitude_total: f32
	amplitude: f32 = 1
	frequency: f32 = 1
	for octave in 0 ..< octaves {
		sum += amplitude * Noise_Gradient_3(position * frequency, Hash_U32(seed + u32(octave)) if octave > 0 else seed)
		amplitude_total += amplitude
		amplitude *= gain
		frequency *= lacunarity
	}
	return sum / amplitude_total
}

@(private = "file")
quintic_fade :: proc(t: f32) -> f32 {
	return t * t * t * (t * (t * 6 - 15) + 10)
}

// Gradient chosen from the 12 cube-edge directions (Perlin 2002), unrolled so no table is needed.
@(private = "file")
edge_gradient_dot :: proc(hash: u32, offset: [3]f32) -> f32 {
	selector := hash & 15
	u := offset.x if selector < 8 else offset.y
	v: f32
	switch {
	case selector < 4: v = offset.y
	case selector == 12 || selector == 14: v = offset.x
	case: v = offset.z
	}
	return (u if selector & 1 == 0 else -u) + (v if selector & 2 == 0 else -v)
}
