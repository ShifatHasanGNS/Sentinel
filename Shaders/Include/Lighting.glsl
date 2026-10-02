// Light sources. Include after Brdf.glsl. Colour is linear RGB; intensity scales it:
// directional = irradiance on a surface facing the light, point/spot/area = radiant intensity along the emission axis.
// For an area light, position is the rectangle centre, axis_u and axis_v are half-extent vectors, and the emission normal is cross(axis_u, axis_v).

const int LIGHT_DIRECTIONAL = 0;
const int LIGHT_POINT = 1;
const int LIGHT_SPOT = 2;
const int LIGHT_AREA = 3;
const int AREA_SAMPLES_PER_AXIS = 4;

struct Light {
	int type;
	vec3 color;
	float intensity;
	vec3 position;
	vec3 direction; // Directional: the way the light travels. Spot: the cone axis.
	float range;
	float cos_inner;
	float cos_outer;
	vec3 axis_u;
	vec3 axis_v;
};

// Inverse-square falloff times a smooth window (Karis 2013): (1 - (d/range)^4)^2 reaches exactly 0 at range with zero slope,
// so a light's volume can be bounded without a visible edge. The +1 keeps the value finite at the light itself.
float attenuation_windowed(float distance_to_light, float range) {
	float ratio = distance_to_light / range;
	float window = clamp(1.0 - ratio * ratio * ratio * ratio, 0.0, 1.0);
	return window * window / (distance_to_light * distance_to_light + 1.0);
}

// 1 inside the inner cone, 0 outside the outer cone, squared smooth ramp between them.
float spot_cone_factor(float cos_angle, float cos_inner, float cos_outer) {
	float ramp = clamp((cos_angle - cos_outer) / max(cos_inner - cos_outer, 1e-4), 0.0, 1.0);
	return ramp * ramp;
}

vec3 shade_point_like(Light light, int model, vec3 position, vec3 normal, vec3 view, vec3 albedo, float roughness, float metallic) {
	vec3 to_light = -light.direction;
	float falloff = 1.0;
	if (light.type != LIGHT_DIRECTIONAL) {
		vec3 offset = light.position - position;
		float distance_to_light = length(offset);
		to_light = offset / distance_to_light;
		falloff = attenuation_windowed(distance_to_light, light.range);
		if (light.type == LIGHT_SPOT) falloff *= spot_cone_factor(dot(-to_light, light.direction), light.cos_inner, light.cos_outer);
	}
	vec3 radiance = light.color * light.intensity * falloff;
	return brdf_evaluate(model, albedo, roughness, metallic, normal, view, to_light) * radiance * light_cosine(model, normal, to_light);
}

// A rectangular Lambertian emitter, integrated as an N x N grid of point emitters. Each carries 1/N^2 of the intensity
// and emits as cos(angle from the emitter normal), so on axis from afar it matches a point light of the same intensity.
vec3 shade_area_light(Light light, int model, vec3 position, vec3 normal, vec3 view, vec3 albedo, float roughness, float metallic) {
	vec3 emitter_normal = normalize(cross(light.axis_u, light.axis_v));
	vec3 total = vec3(0.0);
	for (int row = 0; row < AREA_SAMPLES_PER_AXIS; row++) {
		for (int column = 0; column < AREA_SAMPLES_PER_AXIS; column++) {
			vec2 offset = (vec2(column, row) + 0.5) / float(AREA_SAMPLES_PER_AXIS) * 2.0 - 1.0;
			vec3 sample_position = light.position + light.axis_u * offset.x + light.axis_v * offset.y;
			vec3 to_sample = sample_position - position;
			float distance_to_sample = length(to_sample);
			vec3 to_light = to_sample / distance_to_sample;
			float emission_cosine = dot(-to_light, emitter_normal);
			if (emission_cosine <= 0.0) continue;
			float falloff = attenuation_windowed(distance_to_sample, light.range) * emission_cosine;
			vec3 radiance = light.color * light.intensity * falloff / float(AREA_SAMPLES_PER_AXIS * AREA_SAMPLES_PER_AXIS);
			total += brdf_evaluate(model, albedo, roughness, metallic, normal, view, to_light) * radiance * light_cosine(model, normal, to_light);
		}
	}
	return total;
}

vec3 shade_light(Light light, int model, vec3 position, vec3 normal, vec3 view, vec3 albedo, float roughness, float metallic) {
	if (light.type == LIGHT_AREA) return shade_area_light(light, model, position, normal, view, albedo, roughness, metallic);
	return shade_point_like(light, model, position, normal, view, albedo, roughness, metallic);
}
