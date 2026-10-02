// Cascaded shadow map lookup. Requires CASCADE_COUNT (defined by the host) and the uniforms below, set by Shadow_Map_Bind.

uniform sampler2DArrayShadow u_ShadowMap;
uniform mat4 u_ShadowMatrices[CASCADE_COUNT];
uniform float u_CascadeFar[CASCADE_COUNT];
uniform float u_CascadeTexel[CASCADE_COUNT];
uniform float u_ShadowMapSize;

const float SHADOW_DEPTH_BIAS = 0.0005;
const int SHADOW_TAPS = 8;
const float SHADOW_FILTER_RADIUS_TEXELS = 1.6;

// 1 = fully lit, 0 = fully shadowed. The cascade is picked by view-space distance. The lookup is pushed along the surface
// normal by a texel or two (more when the surface is tilted from the light), which removes acne without detaching shadows
// from their casters the way a large depth bias does. A 3x3 grid of hardware-compared taps softens the edge.
float shadow_factor(vec3 world_position, vec3 normal, vec3 to_light, vec3 camera_position, vec3 camera_forward) {
	float view_depth = dot(world_position - camera_position, camera_forward);
	int cascade = CASCADE_COUNT - 1;
	for (int index = 0; index < CASCADE_COUNT; index++) {
		if (view_depth < u_CascadeFar[index]) {
			cascade = index;
			break;
		}
	}
	float tilt = 1.0 - clamp(dot(normal, to_light), 0.0, 1.0);
	vec3 offset_position = world_position + normal * u_CascadeTexel[cascade] * (1.5 + 2.5 * tilt);
	vec4 light_clip = u_ShadowMatrices[cascade] * vec4(offset_position, 1.0);
	vec3 coordinates = light_clip.xyz * 0.5 + 0.5;
	if (coordinates.x < 0.0 || coordinates.x > 1.0 || coordinates.y < 0.0 || coordinates.y > 1.0 || coordinates.z > 1.0) return 1.0;
	// Percentage-closer filtering over a rotated Vogel disk (golden-angle spiral, equal area per tap). The disk's radius grows with
	// view distance within a cascade, a cheap penumbra widening, and the per-point rotation (hashed from the world position, so it is stable when the camera moves) turns banding into fine noise.
	float rotation = 6.2831853 * fract(52.9829189 * fract(dot(world_position.xz * 61.0 + world_position.y * 37.0, vec2(0.06711056, 0.00583715))));
	float radius_texels = SHADOW_FILTER_RADIUS_TEXELS + 0.6 * float(cascade);
	float lit = 0.0;
	for (int i = 0; i < SHADOW_TAPS; i++) {
		float r = sqrt((float(i) + 0.5) / float(SHADOW_TAPS)) * radius_texels;
		float angle = 2.3999632 * float(i) + rotation;
		vec2 tap = coordinates.xy + vec2(cos(angle), sin(angle)) * r / u_ShadowMapSize;
		lit += texture(u_ShadowMap, vec4(tap, float(cascade), coordinates.z - SHADOW_DEPTH_BIAS));
	}
	return lit / float(SHADOW_TAPS);
}
