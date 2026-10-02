// What a texture recipe produces for one texel, plus the parameters every recipe receives.

struct Surface {
	vec3 albedo;
	float height;
	float roughness;
	float metallic;
	float ambient_occlusion;
};

uniform float u_Seed;
uniform float u_CellsPerTile;
uniform vec3 u_ColorA;
uniform vec3 u_ColorB;
uniform vec3 u_ColorC;
uniform float u_Detail;
