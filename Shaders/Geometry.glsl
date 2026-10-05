#version 410 core
#include "Gbuffer.glsl"
#include "Triplanar.glsl"
#include "Noise.glsl"
#include "TerrainBlend.glsl"
#include "Weathering.glsl"
#stage vertex
layout(location = 0) in vec3 a_Position;
layout(location = 1) in vec3 a_Normal;
layout(location = 2) in vec4 a_Tangent;
layout(location = 3) in vec2 a_Uv;
#ifdef INSTANCED
layout(location = 4) in vec4 a_ModelColumn0;
layout(location = 5) in vec4 a_ModelColumn1;
layout(location = 6) in vec4 a_ModelColumn2;
layout(location = 7) in vec4 a_ModelColumn3;
layout(location = 8) in vec4 a_InstanceData;
#else
uniform mat4 u_Model;
uniform float u_Layer;
#endif
uniform mat4 u_ViewProjection;
uniform float u_WindSeconds;
flat out float v_layer;
flat out float v_tint;
out vec3 v_world_position;
out vec3 v_world_normal;
out vec4 v_world_tangent;
out vec2 v_uv;
// Wind on a tree: a slow gust travels across the land (a sine of position and time), the whole tree leans with it by the square
// of its height (a cantilever bends little at the root and most at the tip), and leaves flutter on top of that.
vec2 wind_offset(vec3 world_position, float local_height, float sway) {
	float gust = 0.5 + 0.5 * sin(u_WindSeconds * 1.3 + world_position.x * 0.05 + world_position.z * 0.03);
	float bend = clamp(local_height / 9.0, 0.0, 1.0);
	bend *= bend;
	vec2 lean = vec2(1.0, 0.35) * (0.04 + 0.1 * gust) * bend;
	float flutter_amount = clamp(sway - 1.0, 0.0, 1.0) * 0.03;
	vec2 flutter = vec2(sin(u_WindSeconds * 5.3 + world_position.x * 1.7 + world_position.y), cos(u_WindSeconds * 4.7 + world_position.z * 1.9 + world_position.y * 1.3)) * flutter_amount;
	return lean * min(sway, 1.0) * 2.0 + flutter;
}

void main() {
#ifdef INSTANCED
	mat4 model = mat4(a_ModelColumn0, a_ModelColumn1, a_ModelColumn2, a_ModelColumn3);
	v_layer = a_InstanceData.x;
	v_tint = a_InstanceData.y;
	float sway = a_InstanceData.z;
#else
	mat4 model = u_Model;
	v_layer = u_Layer;
	v_tint = 0.0;
	float sway = 0.0;
#endif
	vec4 world_position = model * vec4(a_Position, 1.0);
	if (sway > 0.0) world_position.xz += wind_offset(world_position.xyz, a_Position.y, sway);
	v_world_position = world_position.xyz;
	v_world_normal = mat3(model) * a_Normal;
	v_world_tangent = vec4(mat3(model) * a_Tangent.xyz, a_Tangent.w);
	v_uv = a_Uv;
	gl_Position = u_ViewProjection * world_position;
}
#stage fragment
#ifndef INSTANCED
uniform mat4 u_Model;
#endif
flat in float v_layer;
flat in float v_tint;
in vec3 v_world_position;
in vec3 v_world_normal;
in vec4 v_world_tangent;
in vec2 v_uv;
layout(location = 0) out vec4 o_Albedo;
layout(location = 1) out vec4 o_Normal;
layout(location = 2) out vec4 o_Emission;
uniform sampler2DArray u_AlbedoArray;
uniform sampler2DArray u_NormalArray;
uniform sampler2DArray u_OrmArray;
uniform vec2 u_UvScale;
uniform float u_TriplanarScale;
uniform bool u_Triplanar;
uniform int u_IlluminationModel;
uniform vec3 u_Emission;
uniform float u_GroundLevel;
uniform float u_Transparency;

// Screen-door transparency: a 4x4 ordered (Bayer) threshold per pixel drops that fraction of fragments. FXAA and SSAO blur the
// pattern, so a puff reads as thinning smoke even though the G-buffer stores one opaque surface per pixel.
float bayer_threshold(vec2 pixel) {
	const float pattern[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	ivec2 cell = ivec2(pixel) & 3;
	return (pattern[cell.y * 4 + cell.x] + 0.5) / 16.0;
}
uniform vec3 u_CameraPosition;
const float DETAIL_DISTANCE_METERS = 25.0; // Fine detail and weathering are for close surfaces: farther away they are sub-pixel.
const float WEATHER_DISTANCE_METERS = 80.0;

void main() {
#ifndef INSTANCED
	// Each item shifts the pattern by its own offset (from where it is), so overlapping puffs fill each other's holes instead of
	// stacking identical screens.
	vec2 shift = floor(fract(vec2(u_Model[3].x * 0.731 + u_Model[3].y * 0.297, u_Model[3].z * 0.613 + u_Model[3].y * 0.419)) * 4.0);
	if (u_Transparency > 0.0 && bayer_threshold(gl_FragCoord.xy + shift) < u_Transparency) discard;
#endif
	vec3 geometric_normal = normalize(v_world_normal);
	vec3 triplanar_position = v_world_position * u_TriplanarScale;
	vec3 position_dx = dFdx(triplanar_position); // Taken here, in uniform control flow, for the textureGrad calls below.
	vec3 position_dy = dFdy(triplanar_position);
	vec3 albedo, orm, normal;
	if (u_Terrain) {
		vec3 blend = triplanar_blend(geometric_normal);
		vec3 position = triplanar_position;
		vec4 weights = terrain_weights(geometric_normal, v_world_position);
		albedo = vec3(0.0);
		orm = vec3(0.0);
		vec3 normal_sum = vec3(0.0);
		for (int index = 0; index < 4; index++) {
			if (weights[index] < 0.01) continue;
			float terrain_layer = u_TerrainLayers[index];
			albedo += weights[index] * triplanar_sample(u_AlbedoArray, terrain_layer, position, position_dx, position_dy, blend).rgb;
			orm += weights[index] * triplanar_sample(u_OrmArray, terrain_layer, position, position_dx, position_dy, blend).rgb;
			normal_sum += weights[index] * triplanar_normal(u_NormalArray, terrain_layer, position, position_dx, position_dy, geometric_normal, blend);
		}
		normal = normalize(normal_sum);
		if (distance(v_world_position, u_CameraPosition) < 250.0) mottle_terrain(v_world_position, albedo);
	} else if (u_Triplanar) {
		vec3 blend = triplanar_blend(geometric_normal);
		vec3 position = triplanar_position;
		albedo = triplanar_sample(u_AlbedoArray, v_layer, position, position_dx, position_dy, blend).rgb;
		orm = triplanar_sample(u_OrmArray, v_layer, position, position_dx, position_dy, blend).rgb;
		normal = triplanar_normal(u_NormalArray, v_layer, position, position_dx, position_dy, geometric_normal, blend);
	} else {
		vec3 uv = vec3(v_uv * u_UvScale, v_layer);
		albedo = texture(u_AlbedoArray, uv).rgb;
		orm = texture(u_OrmArray, uv).rgb;
		vec3 tangent_normal = texture(u_NormalArray, uv).xyz * 2.0 - 1.0;
		vec3 tangent = normalize(v_world_tangent.xyz - geometric_normal * dot(geometric_normal, v_world_tangent.xyz));
		vec3 bitangent = cross(geometric_normal, tangent) * v_world_tangent.w;
		normal = normalize(mat3(tangent, bitangent, geometric_normal) * tangent_normal);
	}
	if (!u_Terrain) {
		if (u_Triplanar && orm.r > 0.6 && distance(v_world_position, u_CameraPosition) < DETAIL_DISTANCE_METERS) {
			// A second, finer layer of the same material's bumps: the tile never reads as one repeated pattern up close.
			vec3 fine_position = triplanar_position * DETAIL_SCALE;
			vec3 fine = triplanar_normal(u_NormalArray, v_layer, fine_position, position_dx * DETAIL_SCALE, position_dy * DETAIL_SCALE, geometric_normal, triplanar_blend(geometric_normal));
			normal = normalize(normal + (fine - geometric_normal) * DETAIL_STRENGTH);
		}
		if (orm.r > 0.3 && distance(v_world_position, u_CameraPosition) < WEATHER_DISTANCE_METERS) weather_surface(v_world_position, geometric_normal, u_GroundLevel, albedo, orm); // Glass stays clean.
	}
	albedo *= vec3(1.0 + 0.22 * v_tint, 1.0 + 0.08 * v_tint, 1.0 - 0.25 * v_tint); // Per-instance variation: warm and light above zero, cool and dark below.
	o_Albedo = vec4(albedo, float(u_IlluminationModel) / 255.0);
	o_Normal = vec4(oct_encode(normal), max(orm.r, 0.045), orm.g);
	o_Emission = vec4(u_Emission, orm.b);
}
