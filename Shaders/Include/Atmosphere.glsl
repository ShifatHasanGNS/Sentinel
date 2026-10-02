// Single-scattering atmosphere (Nishita et al. 1993): march the view ray through the air; at each sample, march toward the sun to
// find how much light survives, then add the light scattered toward the viewer. Rayleigh scattering (air molecules, strongly
// wavelength-dependent: blue sky, red sunsets) and Mie scattering (haze, sharply forward-peaked: the glow around the sun).

const float PLANET_RADIUS = 6371000.0;
const float ATMOSPHERE_HEIGHT = 100000.0;
const float RAYLEIGH_SCALE_HEIGHT = 8000.0;
const float MIE_SCALE_HEIGHT = 1200.0;
const vec3 RAYLEIGH_COEFFICIENT = vec3(5.8e-6, 13.5e-6, 33.1e-6); // Per metre at sea level, for red, green, blue.
const float MIE_COEFFICIENT = 21e-6;
const float MIE_ANISOTROPY = 0.76;
const float VIEWER_HEIGHT = 2.0;
const int VIEW_SAMPLES = 16;
const int LIGHT_SAMPLES = 6;
const float PI_ATMOSPHERE = 3.14159265;

// Distances (near, far) along the ray where it crosses a sphere centred on the planet's centre; far < 0 means a miss.
vec2 ray_sphere_distances(vec3 origin, vec3 direction, float radius) {
	float b = dot(origin, direction);
	float discriminant = b * b - (dot(origin, origin) - radius * radius);
	if (discriminant < 0.0) return vec2(-1.0);
	float root = sqrt(discriminant);
	return vec2(-b - root, -b + root);
}

float rayleigh_phase(float cosine) {
	return 3.0 / (16.0 * PI_ATMOSPHERE) * (1.0 + cosine * cosine);
}

// Cornette-Shanks phase function for Mie scattering with asymmetry g.
float mie_phase(float cosine) {
	float g2 = MIE_ANISOTROPY * MIE_ANISOTROPY;
	return 3.0 / (8.0 * PI_ATMOSPHERE) * ((1.0 - g2) * (1.0 + cosine * cosine)) / ((2.0 + g2) * pow(1.0 + g2 - 2.0 * MIE_ANISOTROPY * cosine, 1.5));
}

vec3 atmosphere_radiance(vec3 direction, vec3 to_sun, float sun_intensity) {
	vec3 origin = vec3(0.0, PLANET_RADIUS + VIEWER_HEIGHT, 0.0);
	float path_length = ray_sphere_distances(origin, direction, PLANET_RADIUS + ATMOSPHERE_HEIGHT).y;
	vec2 ground = ray_sphere_distances(origin, direction, PLANET_RADIUS);
	if (ground.y > 0.0 && ground.x > 0.0) path_length = min(path_length, ground.x); // Looking down: stop at the ground.
	float step_length = path_length / float(VIEW_SAMPLES);
	float optical_depth_rayleigh = 0.0;
	float optical_depth_mie = 0.0;
	vec3 rayleigh_sum = vec3(0.0);
	vec3 mie_sum = vec3(0.0);
	for (int view_index = 0; view_index < VIEW_SAMPLES; view_index++) {
		vec3 position = origin + direction * (float(view_index) + 0.5) * step_length;
		float height = length(position) - PLANET_RADIUS;
		float density_rayleigh = exp(-height / RAYLEIGH_SCALE_HEIGHT) * step_length;
		float density_mie = exp(-height / MIE_SCALE_HEIGHT) * step_length;
		optical_depth_rayleigh += density_rayleigh;
		optical_depth_mie += density_mie;
		vec2 planet_shadow = ray_sphere_distances(position, to_sun, PLANET_RADIUS);
		if (planet_shadow.x > 0.0 && planet_shadow.y > 0.0) continue; // The planet blocks the sun from here.
		float light_step = ray_sphere_distances(position, to_sun, PLANET_RADIUS + ATMOSPHERE_HEIGHT).y / float(LIGHT_SAMPLES);
		float light_depth_rayleigh = 0.0;
		float light_depth_mie = 0.0;
		for (int light_index = 0; light_index < LIGHT_SAMPLES; light_index++) {
			vec3 light_position = position + to_sun * (float(light_index) + 0.5) * light_step;
			float light_height = length(light_position) - PLANET_RADIUS;
			light_depth_rayleigh += exp(-light_height / RAYLEIGH_SCALE_HEIGHT) * light_step;
			light_depth_mie += exp(-light_height / MIE_SCALE_HEIGHT) * light_step;
		}
		// Beer-Lambert transmittance along both legs; Mie extinction is about 1.1x its scattering.
		vec3 attenuation = exp(-(RAYLEIGH_COEFFICIENT * (optical_depth_rayleigh + light_depth_rayleigh) + MIE_COEFFICIENT * 1.1 * (optical_depth_mie + light_depth_mie)));
		rayleigh_sum += density_rayleigh * attenuation;
		mie_sum += density_mie * attenuation;
	}
	float cosine = dot(direction, to_sun);
	return sun_intensity * (rayleigh_sum * RAYLEIGH_COEFFICIENT * rayleigh_phase(cosine) + mie_sum * MIE_COEFFICIENT * mie_phase(cosine));
}
