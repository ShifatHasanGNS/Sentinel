// Terrain material weights from slope and height: rock on steep ground, sand in the lowlands, dirt around the base plateau,
// grass elsewhere. Layers are indices into the material arrays; weights always sum to 1.

uniform bool u_Terrain;
uniform vec4 u_TerrainLayers;   // grass, dirt, rock, sand
uniform vec2 u_PlateauCenter;
uniform vec2 u_PlateauRange;    // radius, blend width

vec4 terrain_weights(vec3 normal, vec3 position) {
	float steepness = 1.0 - normal.y;
	float rock = smoothstep(0.18, 0.40, steepness);
	float sand = (1.0 - rock) * smoothstep(2.0, -4.0, position.y);
	float plateau_distance = distance(position.xz, u_PlateauCenter);
	float dirt = (1.0 - rock) * (1.0 - smoothstep(u_PlateauRange.x, u_PlateauRange.x + 0.6 * u_PlateauRange.y, plateau_distance));
	float grass = max(1.0 - rock - sand - dirt, 0.0);
	vec4 weights = vec4(grass, dirt, rock, sand);
	return weights / (weights.x + weights.y + weights.z + weights.w);
}
