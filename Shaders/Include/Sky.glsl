// Analytic sky: zenith-to-horizon gradient, ground below the horizon, and a sun disc with a soft glow.
// Placeholder until the atmosphere (Rayleigh + Mie scattering) replaces it.

uniform vec3 u_SkyZenith;
uniform vec3 u_SkyHorizon;
uniform vec3 u_SkyGround;
uniform vec3 u_SunColor;
uniform vec3 u_ToSun;

vec3 sky_radiance(vec3 direction) {
	float elevation = direction.y;
	vec3 sky = mix(u_SkyHorizon, u_SkyZenith, pow(clamp(elevation, 0.0, 1.0), 0.5));
	vec3 base = elevation >= 0.0 ? sky : mix(u_SkyHorizon, u_SkyGround, clamp(-elevation * 4.0, 0.0, 1.0));
	float toward_sun = max(dot(direction, u_ToSun), 0.0);
	float disc = smoothstep(0.9995, 0.9999, toward_sun);
	float glow = pow(toward_sun, 64.0) * 0.3;
	return base + u_SunColor * (disc * 20.0 + glow);
}

// Cosine-weighted sky irradiance divided by pi: a hemisphere gradient (zenith above, ground below).
vec3 sky_ambient(vec3 normal) {
	float up = normal.y * 0.5 + 0.5;
	return mix(u_SkyGround, mix(u_SkyHorizon, u_SkyZenith, 0.5), up);
}
