// Reads the G-buffer written by Geometry.glsl. Include after Gbuffer.glsl. Position is rebuilt from depth.

uniform sampler2D u_GAlbedo;   // rgb = albedo, a = illumination model / 255
uniform sampler2D u_GNormal;   // rg = octahedral world normal, b = roughness, a = metallic
uniform sampler2D u_GEmission; // rgb = emission, a = ambient occlusion
uniform sampler2D u_GDepth;
uniform mat4 u_InverseViewProjection;
uniform vec3 u_CameraPosition;

struct Gbuffer_Sample {
	vec3 albedo;
	int model;
	vec3 normal;
	float roughness;
	float metallic;
	vec3 emission;
	float ambient_occlusion;
	float depth;
	vec3 position;
};

vec3 world_position_from_depth(vec2 uv, float depth) {
	vec4 clip = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
	vec4 world = u_InverseViewProjection * clip;
	return world.xyz / world.w;
}

Gbuffer_Sample gbuffer_read(vec2 uv) {
	vec4 albedo_model = texture(u_GAlbedo, uv);
	vec4 normal_surface = texture(u_GNormal, uv);
	vec4 emission_occlusion = texture(u_GEmission, uv);
	Gbuffer_Sample sample_;
	sample_.albedo = albedo_model.rgb;
	sample_.model = int(albedo_model.a * 255.0 + 0.5);
	sample_.normal = oct_decode(normal_surface.rg);
	sample_.roughness = normal_surface.b;
	sample_.metallic = normal_surface.a;
	sample_.emission = emission_occlusion.rgb;
	sample_.ambient_occlusion = emission_occlusion.a;
	sample_.depth = texture(u_GDepth, uv).r;
	sample_.position = world_position_from_depth(uv, sample_.depth);
	return sample_;
}
