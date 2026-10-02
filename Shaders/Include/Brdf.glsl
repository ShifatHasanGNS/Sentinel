// Illumination models. brdf_evaluate returns f(l, v), the reflected radiance per unit incident irradiance; the caller multiplies
// by light radiance and light_cosine. Every model is zero for a viewer or light below the surface (subsurface lets light wrap).

const float PI = 3.14159265;
const int MODEL_LAMBERT = 0;
const int MODEL_PHONG = 1;
const int MODEL_BLINN_PHONG = 2;
const int MODEL_OREN_NAYAR = 3;
const int MODEL_COOK_TORRANCE = 4;
const int MODEL_SUBSURFACE = 5;
const float SUBSURFACE_WRAP = 0.5;

float shininess_from_roughness(float roughness) {
	return max(2.0 / (roughness * roughness + 1e-4) - 2.0, 1.0);
}

// Normalised Phong lobe (n + 2) / 2pi, so the specular term integrates to its colour.
vec3 specular_phong(vec3 specular_color, float roughness, vec3 normal, vec3 view, vec3 light) {
	float exponent = shininess_from_roughness(roughness);
	float reflected = max(dot(reflect(-light, normal), view), 0.0);
	return specular_color * (exponent + 2.0) / (2.0 * PI) * pow(reflected, exponent);
}

// Blinn-Phong uses the half vector; normalisation (n + 8) / 8pi is the usual close fit.
vec3 specular_blinn_phong(vec3 specular_color, float roughness, float n_dot_h) {
	float exponent = shininess_from_roughness(roughness);
	return specular_color * (exponent + 8.0) / (8.0 * PI) * pow(n_dot_h, exponent);
}

// Oren-Nayar rough diffuse: facets scatter light back toward the source, flattening the falloff. sigma = roughness.
vec3 diffuse_oren_nayar(vec3 diffuse_color, float roughness, vec3 normal, vec3 view, vec3 light, float n_dot_l, float n_dot_v) {
	float sigma2 = roughness * roughness;
	float a = 1.0 - 0.5 * sigma2 / (sigma2 + 0.33);
	float b = 0.45 * sigma2 / (sigma2 + 0.09);
	vec3 light_plane = light - normal * n_dot_l;
	vec3 view_plane = view - normal * n_dot_v;
	float azimuth_cosine = dot(light_plane, view_plane) / max(length(light_plane) * length(view_plane), 1e-5);
	float sin_alpha = sqrt(1.0 - min(n_dot_l, n_dot_v) * min(n_dot_l, n_dot_v));
	float tan_beta = sqrt(1.0 - max(n_dot_l, n_dot_v) * max(n_dot_l, n_dot_v)) / max(max(n_dot_l, n_dot_v), 1e-4);
	return diffuse_color / PI * (a + b * max(azimuth_cosine, 0.0) * sin_alpha * tan_beta);
}

vec3 fresnel_schlick(vec3 specular_color, float cosine) {
	return specular_color + (1.0 - specular_color) * pow(1.0 - cosine, 5.0);
}

// Cook-Torrance microfacet specular: D (GGX normal distribution) * V (height-correlated Smith visibility, = G / 4 n.l n.v)
// * F (Schlick Fresnel at the half vector). Diffuse is scaled by (1 - F(n.l)) (1 - F(n.v)): light reflected at the surface
// is not also scattered inside. Fresnel at the half vector would be wrong here: at grazing view the specular lobe sees large F
// while most of the diffuse integral sees small F, and the sum exceeds 1. The product form stays symmetric in l and v.
vec3 microfacet_cook_torrance(vec3 diffuse_color, vec3 specular_color, float roughness, float n_dot_l, float n_dot_v, float n_dot_h, float v_dot_h) {
	float alpha = max(roughness * roughness, 0.002);
	float alpha2 = alpha * alpha;
	float denominator = n_dot_h * n_dot_h * (alpha2 - 1.0) + 1.0;
	float distribution = alpha2 / (PI * denominator * denominator);
	float visibility = 0.5 / (n_dot_l * sqrt(n_dot_v * n_dot_v * (1.0 - alpha2) + alpha2) + n_dot_v * sqrt(n_dot_l * n_dot_l * (1.0 - alpha2) + alpha2));
	vec3 fresnel = fresnel_schlick(specular_color, v_dot_h);
	vec3 diffuse_weight = (1.0 - fresnel_schlick(specular_color, n_dot_l)) * (1.0 - fresnel_schlick(specular_color, n_dot_v));
	return diffuse_weight * diffuse_color / PI + distribution * visibility * fresnel;
}

vec3 brdf_evaluate(int model, vec3 albedo, float roughness, float metallic, vec3 normal, vec3 view, vec3 light) {
	float n_dot_l = dot(normal, light);
	float n_dot_v = dot(normal, view);
	if (n_dot_v <= 0.0) return vec3(0.0);
	if (n_dot_l <= 0.0 && model != MODEL_SUBSURFACE) return vec3(0.0);
	if (model == MODEL_SUBSURFACE) metallic = 0.0;
	vec3 specular_color = mix(vec3(0.04), albedo, metallic);
	vec3 diffuse_color = albedo * (1.0 - metallic);
	if (n_dot_l <= 0.0) return diffuse_color / PI; // Subsurface light wrapping past the terminator: diffuse only.
	vec3 halfway = normalize(light + view);
	float n_dot_h = max(dot(normal, halfway), 0.0);
	float v_dot_h = max(dot(view, halfway), 0.0);
	float diffuse_scale = 1.0 - max(specular_color.r, max(specular_color.g, specular_color.b));
	switch (model) {
	case MODEL_LAMBERT:
		return diffuse_color / PI;
	case MODEL_PHONG:
		return diffuse_color * diffuse_scale / PI + specular_phong(specular_color, roughness, normal, view, light);
	case MODEL_BLINN_PHONG:
		return diffuse_color * diffuse_scale / PI + specular_blinn_phong(specular_color, roughness, n_dot_h);
	case MODEL_OREN_NAYAR:
		return diffuse_oren_nayar(diffuse_color, roughness, normal, view, light, n_dot_l, n_dot_v);
	default:
		return microfacet_cook_torrance(diffuse_color, specular_color, roughness, n_dot_l, n_dot_v, n_dot_h, v_dot_h);
	}
}

// Subsurface scattering lets light reach pixels slightly past the terminator: wrap the cosine by SUBSURFACE_WRAP.
float light_cosine(int model, vec3 normal, vec3 light) {
	float n_dot_l = dot(normal, light);
	if (model == MODEL_SUBSURFACE) return clamp((n_dot_l + SUBSURFACE_WRAP) / (1.0 + SUBSURFACE_WRAP), 0.0, 1.0);
	return max(n_dot_l, 0.0);
}
