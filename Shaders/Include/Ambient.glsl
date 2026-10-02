// Image-based ambient from the analytic sky. Include after Brdf.glsl and Sky.glsl.

// Karis 2014, "Physically Based Shading on Mobile": a fit to the split-sum environment BRDF integral,
// returning (scale, bias) for F0, so specular ambient = prefiltered radiance * (F0 * scale + bias).
vec2 environment_brdf(float roughness, float n_dot_v) {
	const vec4 c0 = vec4(-1.0, -0.0275, -0.572, 0.022);
	const vec4 c1 = vec4(1.0, 0.0425, 1.04, -0.04);
	vec4 r = roughness * c0 + c1;
	float a004 = min(r.x * r.x, exp2(-9.28 * n_dot_v)) * r.x + r.y;
	return vec2(-1.04, 1.04) * a004 + r.zw;
}

vec3 ambient_light(vec3 albedo, float roughness, float metallic, vec3 normal, vec3 view, float ambient_occlusion) {
	vec3 specular_color = mix(vec3(0.04), albedo, metallic);
	vec3 diffuse_color = albedo * (1.0 - metallic);
	float n_dot_v = max(dot(normal, view), 1e-3);
	vec2 scale_bias = environment_brdf(roughness, n_dot_v);
	vec3 diffuse = diffuse_color * (1.0 - specular_color) * sky_ambient(normal);
	// Rough surfaces see a blurred sky: blend the sharp reflection toward the cosine-blurred hemisphere.
	vec3 prefiltered = mix(sky_radiance(reflect(-view, normal)), sky_ambient(normal), roughness * roughness);
	vec3 specular = prefiltered * (specular_color * scale_bias.x + scale_bias.y);
	return (diffuse + specular) * ambient_occlusion;
}
