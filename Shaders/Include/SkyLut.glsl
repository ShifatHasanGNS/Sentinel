// Sky look-up table: the atmosphere evaluated once per frame on a (azimuth, elevation) grid, then sampled per pixel.
// Elevation is stored with a square-root mapping, v = 0.5 + 0.5 sign(e) sqrt(|e| / (pi/2)), so texels crowd the horizon
// where the sky changes fastest. Azimuth wraps, so sample with a repeating sampler.

const float SKY_LUT_PI = 3.14159265;

vec2 sky_lut_uv(vec3 direction) {
	float azimuth = atan(direction.z, direction.x);
	float elevation = asin(clamp(direction.y, -1.0, 1.0));
	float u = azimuth / (2.0 * SKY_LUT_PI) + 0.5;
	float v = 0.5 + 0.5 * sign(elevation) * sqrt(abs(elevation) / (0.5 * SKY_LUT_PI));
	return vec2(u, v);
}

vec3 sky_lut_direction(vec2 uv) {
	float azimuth = (uv.x - 0.5) * 2.0 * SKY_LUT_PI;
	float signed_root = uv.y * 2.0 - 1.0;
	float elevation = sign(signed_root) * signed_root * signed_root * 0.5 * SKY_LUT_PI;
	return vec3(cos(elevation) * cos(azimuth), sin(elevation), cos(elevation) * sin(azimuth));
}

// Clamps v half a texel in so bilinear filtering never blends across the poles.
vec3 sky_lut_sample(sampler2D lut, vec3 direction) {
	vec2 uv = sky_lut_uv(direction);
	float half_texel = 0.5 / float(textureSize(lut, 0).y);
	uv.y = clamp(uv.y, half_texel, 1.0 - half_texel);
	return texture(lut, uv).rgb;
}
