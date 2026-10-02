// Large-scale variation that breaks up texture tiling and tells the eye how old and exposed a surface is. Include after Noise.glsl.
// All of it is a function of world position, so neighbouring objects of one material are not copies of each other.

const float DETAIL_SCALE = 5.3;
const float DETAIL_STRENGTH = 0.6;

// Non-periodic fbm: a period far larger than any position we sample keeps the lattice from wrapping.
float world_fbm(vec2 position, int octaves, uint seed) {
	return fbm(position / 4096.0, 4096, octaves, seed); // fbm takes tile coordinates (it multiplies by the period), so divide it out: one lattice cell per unit.
}

// albedo and orm (occlusion in b, roughness in r, metal in g as stored) are modified in place.
//  mottling: +-18% brightness at 8 m scale, +-8% at 1.5 m;
//  dust: upward faces fade toward pale dust;
//  grime: rain-splashed dirt in the lowest 0.9 m of a wall, darker and rougher, breaking up with noise;
//  streaks: vertical rain stains under edges, stretched noise along y.
void weather_surface(vec3 world_position, vec3 normal, float ground_level, inout vec3 albedo, inout vec3 orm) {
	float coarse = world_fbm(world_position.xz * 0.125 + world_position.y * 0.07, 2, 91u);
	float medium = world_fbm(world_position.xz * 0.6 + world_position.y * 0.5, 2, 93u);
	albedo *= 1.0 + 0.18 * coarse + 0.08 * medium;
	float height = world_position.y - ground_level;
	float up = smoothstep(0.55, 0.95, normal.y);
	float dust_amount = up * (0.25 + 0.2 * medium);
	albedo = mix(albedo, vec3(0.42, 0.36, 0.28) * (0.9 + 0.2 * coarse), clamp(dust_amount, 0.0, 0.45));
	float wall = 1.0 - smoothstep(0.35, 0.8, abs(normal.y));
	float splash = (1.0 - smoothstep(0.1, 0.9 + 0.5 * medium, height)) * wall;
	albedo = mix(albedo, albedo * vec3(0.55, 0.48, 0.4), clamp(splash * 0.8, 0.0, 0.8));
	orm.r = mix(orm.r, 0.95, clamp(splash, 0.0, 0.7));
	float streak_noise = world_fbm(vec2((world_position.x + world_position.z) * 3.2, world_position.y * 0.18), 2, 97u);
	float streaks = smoothstep(0.25, 0.7, streak_noise) * wall * smoothstep(0.5, 3.0, height);
	albedo *= 1.0 - 0.22 * streaks;
	orm.b *= 1.0 - 0.15 * splash;
}

// Terrain breaks up differently from walls: broad patches of drier and darker ground (60 m and 12 m scale) hide the repeating tile,
// and small bare patches show through the grass. Only albedo changes; the textures already carry the fine detail.
void mottle_terrain(vec3 world_position, inout vec3 albedo) {
	float broad = world_fbm(world_position.xz * 0.016, 3, 191u);
	float patches = world_fbm(world_position.xz * 0.08, 3, 193u);
	albedo *= 1.0 + 0.22 * broad + 0.12 * patches;
	albedo = mix(albedo, albedo * vec3(1.15, 1.0, 0.8), clamp(0.5 + broad, 0.0, 1.0) * 0.3);
}
