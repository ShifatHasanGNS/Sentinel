// The sky. Include after SkyLut.glsl and Noise.glsl (hash_u32).
// sky_radiance: what the eye sees (atmosphere scattering, sun and moon discs, stars). sky_gradient and sky_ambient: a cheap
// gradient from CPU-supplied colours, used for lighting where evaluating the atmosphere per pixel would cost too much.

uniform vec3 u_SkyZenith;
uniform vec3 u_SkyHorizon;
uniform vec3 u_SkyGround;
uniform vec3 u_SunColor;
uniform vec3 u_ToSun;
uniform sampler2D u_SkyLut; // The atmosphere, evaluated once per frame (see SkyLut.glsl).
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

// A cloud layer: the view ray meets a plane 1500 m up at xz = direction.xz * 1500 / direction.y. Density is fbm on that plane
// (coverage threshold gives clear gaps), and the lighting asks how much cloud lies toward the sun: a point with thick cloud
// between it and the sun is darker (self-shadowing, one extra sample), thin edges glow (silver lining).
float cloud_density(vec2 plane_position) {
	float shape = fbm(plane_position * 0.0006 / 4096.0, 4096, 5, 301u) * 0.5 + 0.5;
	float detail = fbm(plane_position * 0.003 / 4096.0, 4096, 3, 303u) * 0.5 + 0.5;
	return smoothstep(0.4, 0.68, shape * 0.8 + detail * 0.2);
}

vec3 add_clouds(vec3 sky, vec3 direction) {
	if (direction.y < 0.05) return sky;
	vec2 plane_position = direction.xz * 1500.0 / direction.y;
	float density = cloud_density(plane_position);
	if (density < 0.01) return sky;
	float toward_sun_density = cloud_density(plane_position + normalize(u_ToSun.xz + vec2(1e-4)) * 220.0);
	float shade = clamp(1.0 - 0.7 * max(toward_sun_density - density * 0.4, 0.0), 0.3, 1.0);
	float silver = pow(1.0 - density, 3.0) * max(dot(direction, u_ToSun), 0.0);
	float brightness = dot(sky, vec3(0.3, 0.59, 0.11));
	vec3 cloud = (vec3(brightness * 1.6) + u_SunColor * 0.12 * max(u_ToSun.y, 0.0)) * shade + u_SunColor * silver * 0.6;
	float fade = smoothstep(0.05, 0.3, direction.y);
	return mix(sky, cloud, density * 0.85 * fade);
}

vec3 sky_radiance(vec3 direction) {
	// Below the horizon the view ray would hit the planet; continue the horizon haze instead, dimmed like distant land.
	vec3 haze_direction = normalize(vec3(direction.x, max(direction.y, 0.0), direction.z));
	vec3 scattered = sky_lut_sample(u_SkyLut, haze_direction);
	// Single scattering loses the blue along the long horizon path; real skies fill it back in by multiple scattering. Blend in the
	// gradient colours as that fill. Below the horizon the haze dims like distant land.
	vec3 sky = mix(scattered, sky_gradient(direction), 0.35) * mix(1.0, 0.6, smoothstep(0.0, -0.2, direction.y));
	sky = add_clouds(sky, direction);
	float night = smoothstep(0.05, -0.2, u_ToSun.y);
	float above_ground = smoothstep(-0.02, 0.05, direction.y);
	sky += vec3(star_field(direction)) * night * above_ground;
	float toward_sun = dot(direction, u_ToSun);
	sky += u_SunColor * smoothstep(0.99985, 0.99997, toward_sun) * 40.0 * above_ground;
	float toward_moon = dot(direction, u_ToMoon);
	sky += u_MoonColor * smoothstep(0.99975, 0.99985, toward_moon) * u_MoonIntensity * 8.0 * above_ground;
	return sky;
}
