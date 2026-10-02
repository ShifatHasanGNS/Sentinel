// Octahedral normal encoding (Cigolle et al. 2014): project the unit sphere onto the octahedron |x|+|y|+|z| = 1,
// fold the lower half outward, and keep two components in [-1, 1]. Uniform precision, no singular direction.

vec2 sign_not_zero(vec2 value) {
	return vec2(value.x >= 0.0 ? 1.0 : -1.0, value.y >= 0.0 ? 1.0 : -1.0);
}

vec2 oct_encode(vec3 normal) {
	vec2 projected = normal.xy / (abs(normal.x) + abs(normal.y) + abs(normal.z));
	return normal.z <= 0.0 ? (1.0 - abs(projected.yx)) * sign_not_zero(projected) : projected;
}

vec3 oct_decode(vec2 encoded) {
	vec3 normal = vec3(encoded, 1.0 - abs(encoded.x) - abs(encoded.y));
	if (normal.z < 0.0) normal.xy = (1.0 - abs(normal.yx)) * sign_not_zero(normal.xy);
	return normalize(normal);
}
