// Cascaded shadow map lookup. Requires CASCADE_COUNT (defined by the host) and the uniforms below, set by Shadow_Map_Bind.

uniform sampler2DArrayShadow u_ShadowMap;
uniform mat4 u_ShadowMatrices[CASCADE_COUNT];
uniform float u_CascadeFar[CASCADE_COUNT];
uniform float u_CascadeTexel[CASCADE_COUNT];
uniform float u_ShadowMapSize;

const float SHADOW_DEPTH_BIAS = 0.0005;

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
	float lit = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 tap = coordinates.xy + vec2(x, y) / u_ShadowMapSize;
			lit += texture(u_ShadowMap, vec4(tap, float(cascade), coordinates.z - SHADOW_DEPTH_BIAS));
		}
	}
	return lit / 9.0;
}
