#version 410 core
#include "Triplanar.glsl"
#stage vertex
layout(location = 0) in vec3 a_Position;
layout(location = 1) in vec3 a_Normal;
layout(location = 2) in vec4 a_Tangent;
layout(location = 3) in vec2 a_Uv;
uniform mat4 u_Model;
uniform mat4 u_ViewProjection;
out vec3 v_world_position;
out vec3 v_world_normal;
out vec4 v_world_tangent;
out vec2 v_uv;
void main() {
	vec4 world_position = u_Model * vec4(a_Position, 1.0);
	v_world_position = world_position.xyz;
	v_world_normal = mat3(u_Model) * a_Normal;
	v_world_tangent = vec4(mat3(u_Model) * a_Tangent.xyz, a_Tangent.w);
	v_uv = a_Uv;
	gl_Position = u_ViewProjection * world_position;
}
#stage fragment
in vec3 v_world_position;
in vec3 v_world_normal;
in vec4 v_world_tangent;
in vec2 v_uv;
out vec4 color;
uniform sampler2DArray u_AlbedoArray;
uniform sampler2DArray u_NormalArray;
uniform sampler2DArray u_OrmArray;
uniform float u_Layer;
uniform vec2 u_UvScale;
uniform float u_TriplanarScale;
uniform bool u_Triplanar;
uniform vec3 u_LightDirection;
uniform vec3 u_CameraPosition;

void main() {
	vec3 geometric_normal = normalize(v_world_normal);
	vec3 albedo, orm, normal;
	if (u_Triplanar) {
		vec3 blend = triplanar_blend(geometric_normal);
		vec3 position = v_world_position * u_TriplanarScale;
		albedo = triplanar_sample(u_AlbedoArray, u_Layer, position, blend).rgb;
		orm = triplanar_sample(u_OrmArray, u_Layer, position, blend).rgb;
		normal = triplanar_normal(u_NormalArray, u_Layer, position, geometric_normal, blend);
	} else {
		vec3 uv = vec3(v_uv * u_UvScale, u_Layer);
		albedo = texture(u_AlbedoArray, uv).rgb;
		orm = texture(u_OrmArray, uv).rgb;
		vec3 tangent_normal = texture(u_NormalArray, uv).xyz * 2.0 - 1.0;
		vec3 tangent = normalize(v_world_tangent.xyz - geometric_normal * dot(geometric_normal, v_world_tangent.xyz));
		vec3 bitangent = cross(geometric_normal, tangent) * v_world_tangent.w;
		normal = normalize(mat3(tangent, bitangent, geometric_normal) * tangent_normal);
	}
	// Placeholder shading until the deferred renderer lands: Blinn-Phong with roughness-derived shininess.
	float roughness = max(orm.r, 0.05);
	float metallic = orm.g;
	vec3 light = normalize(u_LightDirection);
	vec3 view = normalize(u_CameraPosition - v_world_position);
	float diffuse = max(dot(normal, light), 0.0);
	float shininess = 2.0 / (roughness * roughness) - 2.0;
	float specular = pow(max(dot(normal, normalize(light + view)), 0.0), shininess) * diffuse;
	vec3 diffuse_color = albedo * (1.0 - metallic);
	vec3 specular_color = mix(vec3(0.04), albedo, metallic);
	vec3 linear = diffuse_color * (0.2 * orm.b + 0.9 * diffuse) + specular_color * specular;
	color = vec4(pow(linear, vec3(1.0 / 2.2)), 1.0);
}
