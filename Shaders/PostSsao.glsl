#version 410 core
#include "Noise.glsl"
#include "Gbuffer.glsl"
#include "GbufferRead.glsl"
#include "Fullscreen.glsl"
#stage fragment
in vec2 v_uv;
out vec4 color;

#ifdef BLUR
uniform sampler2D u_Ao;
uniform vec2 u_TexelSize;

// The sampling pattern repeats every 4 pixels, so a 4x4 box average cancels it exactly.
void main() {
	float sum = 0.0;
	for (int y = -2; y < 2; y++) {
		for (int x = -2; x < 2; x++) sum += texture(u_Ao, v_uv + (vec2(x, y) + 0.5) * u_TexelSize).r;
	}
	color = vec4(vec3(sum / 16.0), 1.0);
}
#else
uniform mat4 u_ViewProjection;
uniform float u_Radius;
const int SAMPLE_COUNT = 12;

float hash_pixel(ivec2 pixel) {
	return fract(52.9829189 * fract(dot(vec2(pixel), vec2(0.06711056, 0.00583715))));
}

// Hemisphere ambient occlusion in world space. For each sample point S = P + r * k inside the hemisphere above the surface
// (k is cosine-distributed, shorter vectors are more likely), project S, read the visible surface at that pixel and count S as
// blocked when the visible surface is closer to the camera. A range term fades the contribution when the occluder is much
// nearer than S (a different object far in front), which would otherwise darken silhouettes.
void main() {
	Gbuffer_Sample surface = gbuffer_read(v_uv);
	if (surface.depth >= 1.0) {
		color = vec4(1.0);
		return;
	}
	ivec2 pixel = ivec2(gl_FragCoord.xy) & 3;
	float angle = 6.2831853 * hash_pixel(pixel + 4 * (pixel.yx & 1));
	vec3 tangent = normalize(abs(surface.normal.y) < 0.99 ? cross(surface.normal, vec3(0, 1, 0)) : vec3(1, 0, 0));
	vec3 bitangent = cross(surface.normal, tangent);
	float camera_distance = length(surface.position - u_CameraPosition);
	float occlusion = 0.0;
	for (int i = 0; i < SAMPLE_COUNT; i++) {
		float u = (float(i) + 0.5) / float(SAMPLE_COUNT);
		float phi = 2.3999632 * float(i) + angle; // Golden angle spiral.
		float sine = sqrt(u);
		vec3 direction = vec3(cos(phi) * sine, sin(phi) * sine, sqrt(1.0 - u));
		float scale = mix(0.15, 1.0, u * u);
		vec3 sample_position = surface.position + (tangent * direction.x + bitangent * direction.y + surface.normal * direction.z) * u_Radius * scale;
		vec4 clip = u_ViewProjection * vec4(sample_position, 1.0);
		vec2 uv = clip.xy / clip.w * 0.5 + 0.5;
		float visible_depth = texture(u_GDepth, uv).r;
		if (visible_depth >= 1.0) continue;
		float visible_distance = length(world_position_from_depth(uv, visible_depth) - u_CameraPosition);
		float sample_distance = length(sample_position - u_CameraPosition);
		float range = smoothstep(0.0, 1.0, u_Radius / max(abs(camera_distance - visible_distance), 1e-4));
		occlusion += (visible_distance < sample_distance - 0.03 ? 1.0 : 0.0) * range;
	}
	color = vec4(vec3(1.0 - occlusion / float(SAMPLE_COUNT)), 1.0);
}
#endif
