// Terrain material weights from slope and height: rock on steep ground, sand in the lowlands, dirt around the base plateau,
// grass elsewhere. Layers are indices into the material arrays; weights always sum to 1.

uniform bool u_Terrain;
uniform vec4 u_TerrainLayers;   // grass, dirt, rock, sand
uniform vec2 u_PlateauCenter;
uniform vec2 u_PlateauRange;    // radius, blend width

// Boundaries between layers wander: a slow noise field shifts each threshold, so a slope turns to rock in patches and the dirt
// around the base frays into the grass instead of ending on a clean circle.
vec4 terrain_weights(vec3 normal, vec3 position) {
	float wander = gradient_noise(position.xz * 0.045, 1 << 20, 701u);
	float fine_wander = gradient_noise(position.xz * 0.21, 1 << 20, 709u);
	float steepness = 1.0 - normal.y + 0.05 * wander;
	float rock = smoothstep(0.18, 0.40, steepness);
	float sand = (1.0 - rock) * smoothstep(2.0, -4.0, position.y + 1.5 * wander);
	float plateau_distance = distance(position.xz, u_PlateauCenter) + 9.0 * wander + 3.0 * fine_wander;
	// Bare ground only where the base stands: it ends a little beyond the fence, and grass takes over (a lawn around the compound).
	float dirt = (1.0 - rock) * (1.0 - smoothstep(0.72 * u_PlateauRange.x, 0.9 * u_PlateauRange.x, plateau_distance));
	float grass = max(1.0 - rock - sand - dirt, 0.0);
	vec4 weights = vec4(grass, dirt, rock, sand);
	return weights / (weights.x + weights.y + weights.z + weights.w);
}
