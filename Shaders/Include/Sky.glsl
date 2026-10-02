// The sky. Include after Atmosphere.glsl and Noise.glsl (hash_u32).
// sky_radiance: what the eye sees (atmosphere scattering, sun and moon discs, stars). sky_gradient and sky_ambient: a cheap
// gradient from CPU-supplied colours, used for lighting where evaluating the atmosphere per pixel would cost too much.

uniform vec3 u_SkyZenith;
uniform vec3 u_SkyHorizon;
uniform vec3 u_SkyGround;
uniform vec3 u_SunColor;
uniform vec3 u_ToSun;
uniform float u_SunIntensity;
uniform vec3 u_ToMoon;
uniform vec3 u_MoonColor;
uniform float u_MoonIntensity;

vec3 sky_gradient(vec3 direction) {
	float elevation = direction.y;
	vec3 sky = mix(u_SkyHorizon, u_SkyZenith, pow(clamp(elevation, 0.0, 1.0), 0.5));
	return elevation >= 0.0 ? sky : mix(u_SkyHorizon, u_SkyGround, clamp(-elevation * 4.0, 0.0, 1.0));
}

// Cosine-weighted sky irradiance divided by pi: a hemisphere gradient (zenith above, ground below).
vec3 sky_ambient(vec3 normal) {
	float up = normal.y * 0.5 + 0.5;
	return mix(u_SkyGround, mix(u_SkyHorizon, u_SkyZenith, 0.5), up);
}

// Sparse stars: hash a coarse direction cell; a small fraction of cells hold a star, brightness varying by hash.
float star_field(vec3 direction) {
	ivec3 cell = ivec3(floor(direction * 220.0));
	uint hash = hash_u32(uint(cell.x) ^ hash_u32(uint(cell.y) ^ hash_u32(uint(cell.z))));
	float chance = float(hash >> 8u) / 16777216.0;
	vec3 center = (vec3(cell) + 0.5) / 220.0;
	float closeness = smoothstep(0.0016, 0.0, distance(direction, normalize(center))); // Radius under half a cell, so stars stay round.
	return chance > 0.996 ? closeness * (0.5 + 6.0 * float(hash & 255u) / 255.0) : 0.0;
}

vec3 sky_radiance(vec3 direction) {
	// Below the horizon the view ray would hit the planet; continue the horizon haze instead, dimmed like distant land.
	vec3 haze_direction = normalize(vec3(direction.x, max(direction.y, 0.0), direction.z));
	vec3 scattered = atmosphere_radiance(haze_direction, u_ToSun, u_SunIntensity);
	// Single scattering loses the blue along the long horizon path; real skies fill it back in by multiple scattering. Blend in the
	// gradient colours as that fill. Below the horizon the haze dims like distant land.
	vec3 sky = mix(scattered, sky_gradient(direction), 0.35) * mix(1.0, 0.6, smoothstep(0.0, -0.2, direction.y));
	float night = smoothstep(0.05, -0.2, u_ToSun.y);
	float above_ground = smoothstep(-0.02, 0.05, direction.y);
	sky += vec3(star_field(direction)) * night * above_ground;
	float toward_sun = dot(direction, u_ToSun);
	sky += u_SunColor * smoothstep(0.99985, 0.99997, toward_sun) * 40.0 * above_ground;
	float toward_moon = dot(direction, u_ToMoon);
	sky += u_MoonColor * smoothstep(0.99975, 0.99985, toward_moon) * u_MoonIntensity * 8.0 * above_ground;
	return sky;
}
