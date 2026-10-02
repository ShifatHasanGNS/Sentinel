// ACES filmic curve, Narkowicz's fit: maps HDR radiance [0, inf) to display range [0, 1] with a toe and a shoulder.

vec3 tonemap_aces(vec3 radiance) {
	vec3 mapped = (radiance * (2.51 * radiance + 0.03)) / (radiance * (2.43 * radiance + 0.59) + 0.14);
	return clamp(mapped, 0.0, 1.0);
}
