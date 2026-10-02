// Periodic noise: every function takes an integer period (cells per tile) and wraps its lattice by it,
// so f(p + period) = f(p) and a texture baked over one tile repeats without a seam.

uint hash_u32(uint value) {
	uint state = value * 747796405u + 2891336453u;
	uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
	return (word >> 22u) ^ word;
}

float hash_to_unit(uint hash) {
	return float(hash >> 8u) / 16777216.0;
}

ivec2 wrap_cell(ivec2 cell, int period) {
	return cell - period * ivec2(floor(vec2(cell) / float(period)));
}

uint hash_cell(ivec2 cell, int period, uint seed) {
	ivec2 wrapped = wrap_cell(cell, period);
	return hash_u32(uint(wrapped.x) ^ hash_u32(uint(wrapped.y) ^ seed));
}

// 2D Perlin noise: random unit gradients on the lattice, blended with the quintic fade 6t^5 - 15t^4 + 10t^3.
// Unit gradients bound the raw value by sqrt(2)/2, so the sqrt(2) factor maps the range to [-1, 1].
float gradient_noise(vec2 position, int period, uint seed) {
	ivec2 cell = ivec2(floor(position));
	vec2 offset = position - vec2(cell);
	vec2 fade = offset * offset * offset * (offset * (offset * 6.0 - 15.0) + 10.0);
	float corner[4];
	for (int index = 0; index < 4; index++) {
		ivec2 step = ivec2(index & 1, index >> 1);
		float angle = hash_to_unit(hash_cell(cell + step, period, seed)) * 6.2831853;
		corner[index] = dot(vec2(cos(angle), sin(angle)), offset - vec2(step));
	}
	return mix(mix(corner[0], corner[1], fade.x), mix(corner[2], corner[3], fade.x), fade.y) * 1.4142136;
}

// Fractal sum over uv in one tile; each octave doubles frequency and period, halves amplitude. Result in [-1, 1].
float fbm(vec2 uv, int period, int octaves, uint seed) {
	float sum = 0.0;
	float amplitude = 1.0;
	float amplitude_total = 0.0;
	for (int octave = 0; octave < octaves; octave++) {
		sum += amplitude * gradient_noise(uv * float(period), period, seed + uint(octave) * 131u);
		amplitude_total += amplitude;
		amplitude *= 0.5;
		period *= 2;
	}
	return sum / amplitude_total;
}

// Worley (cellular) noise: distances to the nearest (x) and second nearest (y) feature point, one random point per cell.
// Points are placed at unwrapped neighbour positions but hashed by wrapped cell, which keeps the pattern periodic.
vec2 worley(vec2 uv, int period, uint seed) {
	vec2 position = uv * float(period);
	ivec2 cell = ivec2(floor(position));
	vec2 nearest = vec2(8.0);
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			ivec2 neighbour = cell + ivec2(dx, dy);
			uint hash = hash_cell(neighbour, period, seed);
			vec2 point = vec2(neighbour) + vec2(hash_to_unit(hash), hash_to_unit(hash_u32(hash)));
			float distance_to_point = distance(position, point);
			if (distance_to_point < nearest.x) {
				nearest.y = nearest.x;
				nearest.x = distance_to_point;
			} else if (distance_to_point < nearest.y) {
				nearest.y = distance_to_point;
			}
		}
	}
	return nearest;
}
