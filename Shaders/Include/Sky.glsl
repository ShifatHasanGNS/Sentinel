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

const float CLOUD_WARP_CELLS = 0.7;
uniform vec2 u_CloudOffset; // Wind drift of the cloud layers, in meters on the cloud plane.

// Cumulus: the view ray meets a plane 1500 m up at xz = direction.xz * 1500 / direction.y. Density is domain-warped fbm there
// (the warp rolls the edges into billows) and the shape layer drifts with the wind while the detail layer drifts a little
// faster, so the clouds slowly change form as they move. A coverage threshold leaves clear gaps.
float cloud_density(vec2 plane_position, int shape_octaves, int detail_octaves) {
	vec2 shape_uv = (plane_position + u_CloudOffset) * 0.0006 / 4096.0;
	vec2 warp = vec2(fbm(shape_uv * 2.0, 4096, 2, 305u), fbm(shape_uv * 2.0 + 0.5, 4096, 2, 307u));
	float shape = fbm(shape_uv + warp * CLOUD_WARP_CELLS / 4096.0, 4096, shape_octaves, 301u) * 0.5 + 0.5; // The warp is in lattice cells; the noise takes tile units.
	float detail = shape;
	if (detail_octaves > 0) {
		vec2 detail_uv = (plane_position + u_CloudOffset * 1.35) * 0.0032 / 4096.0;
		detail = fbm(detail_uv, 4096, detail_octaves, 303u) * 0.5 + 0.5;
	}
	return smoothstep(0.42, 0.7, shape * 0.78 + detail * 0.22);
}

// Cirrus: a thin high sheet (7 km) stretched along the wind into fibres, lit but never self-shadowed.
float cirrus_density(vec3 direction) {
	vec2 plane_position = direction.xz * 7000.0 / direction.y + u_CloudOffset * 1.8;
	vec2 stretched = vec2(plane_position.x * 0.00012, plane_position.y * 0.0007) / 4096.0;
	float fibres = fbm(stretched, 4096, 4, 311u) * 0.5 + 0.5;
	return smoothstep(0.5, 0.82, fibres) * 0.45;
}

// Cloud colour: a grey body from the sky's own brightness, a sunlit rim (silver lining) that vanishes with the sun, and
// moonlight tinting the whole layer at night. The sun term is scaled by how high the sun stands: below the horizon it has
// no colour to give, so night clouds are not orange.
vec3 add_clouds(vec3 sky, vec3 direction) {
	if (direction.y < 0.04) return sky;
	float sun_height = smoothstep(-0.05, 0.25, u_ToSun.y);
	float moon_light = u_MoonIntensity;
	float fade = smoothstep(0.04, 0.3, direction.y);
	vec2 plane_position = direction.xz * 1500.0 / direction.y;
	float density = cloud_density(plane_position, 4, 3);
	float high = cirrus_density(direction);
	float brightness = dot(sky, vec3(0.3, 0.59, 0.11));
	vec3 ambient_light = vec3(brightness * 1.5) + u_MoonColor * moon_light * 0.35;
	vec3 result = mix(sky, ambient_light * 1.1 + u_SunColor * 0.1 * sun_height, high * fade);
	if (density < 0.01) return result;
	float toward_sun_density = cloud_density(plane_position + normalize(u_ToSun.xz + vec2(1e-4)) * 220.0, 2, 0);
	float shade = clamp(1.0 - 0.7 * max(toward_sun_density - density * 0.4, 0.0), 0.3, 1.0);
	float silver = pow(1.0 - density, 3.0) * max(dot(direction, u_ToSun), 0.0) * sun_height;
	float moon_rim = pow(1.0 - density, 3.0) * pow(max(dot(direction, u_ToMoon), 0.0), 3.0);
	vec3 cloud = (ambient_light + u_SunColor * 0.12 * max(u_ToSun.y, 0.0)) * shade + u_SunColor * silver * 0.6 + u_MoonColor * moon_light * moon_rim * 0.8;
	return mix(result, cloud, density * 0.88 * fade);
}

// The smooth part of the sky: atmosphere scattering only. Aerial perspective uses this as its haze colour, because the haze
// direction ignores a pixel's elevation: anything small and bright (a star, the moon) would otherwise paint a whole screen column.
vec3 sky_atmosphere(vec3 direction) {
	// Below the horizon the view ray would hit the planet; continue the horizon haze instead, dimmed like distant land.
	vec3 haze_direction = normalize(vec3(direction.x, max(direction.y, 0.0), direction.z));
	vec3 scattered = sky_lut_sample(u_SkyLut, haze_direction);
	// Single scattering loses the blue along the long horizon path; real skies fill it back in by multiple scattering. Blend in the
	// gradient colours as that fill. Below the horizon the haze dims like distant land.
	return mix(scattered, sky_gradient(direction), 0.35) * mix(1.0, 0.6, smoothstep(0.0, -0.2, direction.y));
}

vec3 sky_radiance(vec3 direction) {
	vec3 sky = sky_atmosphere(direction);
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
