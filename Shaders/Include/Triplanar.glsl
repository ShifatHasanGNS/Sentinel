// Triplanar mapping: project the texture along each world axis and blend by how much the surface faces that axis,
// so deformed or UV-less surfaces never stretch. The weights |n|^4 sharpen the transition between projections.
// Projections whose weight is negligible are skipped: on a near-flat surface two of the three drop out, cutting texture reads.
// Skipping makes texture reads non-uniform, so the sampler uses explicit derivatives (textureGrad) taken by the caller in
// uniform control flow: position_dx = dFdx(position), position_dy = dFdy(position).

const float TRIPLANAR_MIN_WEIGHT = 0.03;

vec3 triplanar_blend(vec3 world_normal) {
	vec3 weights = pow(abs(world_normal), vec3(4.0));
	return weights / (weights.x + weights.y + weights.z);
}

vec4 triplanar_sample(sampler2DArray textures, float layer, vec3 position, vec3 position_dx, vec3 position_dy, vec3 blend) {
	vec4 sum = vec4(0.0);
	float used = 0.0;
	if (blend.x > TRIPLANAR_MIN_WEIGHT) {
		sum += textureGrad(textures, vec3(position.zy, layer), position_dx.zy, position_dy.zy) * blend.x;
		used += blend.x;
	}
	if (blend.y > TRIPLANAR_MIN_WEIGHT) {
		sum += textureGrad(textures, vec3(position.xz, layer), position_dx.xz, position_dy.xz) * blend.y;
		used += blend.y;
	}
	if (blend.z > TRIPLANAR_MIN_WEIGHT) {
		sum += textureGrad(textures, vec3(position.xy, layer), position_dx.xy, position_dy.xy) * blend.z;
		used += blend.z;
	}
	return sum / used;
}

// UDN blend (Golus): add each projection's tangent-space xy to the matching components of the geometric normal.
vec3 triplanar_normal(sampler2DArray normals, float layer, vec3 position, vec3 position_dx, vec3 position_dy, vec3 world_normal, vec3 blend) {
	vec3 sum = vec3(0.0);
	float used = 0.0;
	if (blend.x > TRIPLANAR_MIN_WEIGHT) {
		vec3 from_x = textureGrad(normals, vec3(position.zy, layer), position_dx.zy, position_dy.zy).xyz * 2.0 - 1.0;
		sum += vec3(from_x.xy + world_normal.zy, world_normal.x).zyx * blend.x;
		used += blend.x;
	}
	if (blend.y > TRIPLANAR_MIN_WEIGHT) {
		vec3 from_y = textureGrad(normals, vec3(position.xz, layer), position_dx.xz, position_dy.xz).xyz * 2.0 - 1.0;
		sum += vec3(from_y.xy + world_normal.xz, world_normal.y).xzy * blend.y;
		used += blend.y;
	}
	if (blend.z > TRIPLANAR_MIN_WEIGHT) {
		vec3 from_z = textureGrad(normals, vec3(position.xy, layer), position_dx.xy, position_dy.xy).xyz * 2.0 - 1.0;
		sum += vec3(from_z.xy + world_normal.xy, world_normal.z).xyz * blend.z;
		used += blend.z;
	}
	return normalize(sum / used);
}
