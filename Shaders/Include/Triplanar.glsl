// Triplanar mapping: project the texture along each world axis and blend by how much the surface faces that axis,
// so deformed or UV-less surfaces never stretch. The weights |n|^4 sharpen the transition between projections.

vec3 triplanar_blend(vec3 world_normal) {
	vec3 weights = pow(abs(world_normal), vec3(4.0));
	return weights / (weights.x + weights.y + weights.z);
}

vec4 triplanar_sample(sampler2DArray textures, float layer, vec3 position, vec3 blend) {
	return texture(textures, vec3(position.zy, layer)) * blend.x
		+ texture(textures, vec3(position.xz, layer)) * blend.y
		+ texture(textures, vec3(position.xy, layer)) * blend.z;
}

// UDN blend (Golus): add each projection's tangent-space xy to the matching components of the geometric normal.
vec3 triplanar_normal(sampler2DArray normals, float layer, vec3 position, vec3 world_normal, vec3 blend) {
	vec3 from_x = texture(normals, vec3(position.zy, layer)).xyz * 2.0 - 1.0;
	vec3 from_y = texture(normals, vec3(position.xz, layer)).xyz * 2.0 - 1.0;
	vec3 from_z = texture(normals, vec3(position.xy, layer)).xyz * 2.0 - 1.0;
	from_x = vec3(from_x.xy + world_normal.zy, world_normal.x);
	from_y = vec3(from_y.xy + world_normal.xz, world_normal.y);
	from_z = vec3(from_z.xy + world_normal.xy, world_normal.z);
	return normalize(from_x.zyx * blend.x + from_y.xzy * blend.y + from_z.xyz * blend.z);
}
