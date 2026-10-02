package Render

import "../Procedural"

Draw_Item :: struct {
	mesh:               ^Mesh,
	model:              matrix[4, 4]f32,
	material_layer:     i32,
	uv_scale:           [2]f32,
	triplanar:          bool,
	illumination_model: Illumination_Model,
	emission:           [3]f32, // Linear radiance added regardless of lighting (lamps, glowing parts).
	terrain:            bool, // Blend materials by slope and height instead of using material_layer.
}

Sky :: struct {
	zenith:    [3]f32,
	horizon:   [3]f32,
	ground:    [3]f32,
	sun_color: [3]f32,
	to_sun:    [3]f32, // Unit vector from the scene toward the sun.
	sun_intensity:  f32, // Scale of the atmosphere's scattered light.
	to_moon:        [3]f32,
	moon_color:     [3]f32,
	moon_intensity: f32,
}

// Which material layers the terrain blends and where the base plateau is (dirt around it).
Terrain_Shading :: struct {
	grass_layer:           i32,
	dirt_layer:            i32,
	rock_layer:            i32,
	sand_layer:            i32,
	plateau_center:        [2]f32,
	plateau_radius_meters: f32,
	plateau_blend_meters:  f32,
}

// Everything the renderer needs for one frame. Slices and pointers must outlive the call.
Frame :: struct {
	camera:            Camera,
	items:             []Draw_Item,
	shadow_items:      []Draw_Item, // Shadow casters; when empty, items cast.
	terrain_shading:   Terrain_Shading,
	sun:               Light, // The one directional light.
	local_lights:      []Light, // Point, spot and area lights.
	sky:               Sky,
	materials:         ^Procedural.Texture_Set,
	sun_shadows:       bool,
	shadow_distance_meters: f32,
	exposure:          f32,
	vignette_strength: f32,
	ssao_radius_meters: f32, // 0 disables screen-space ambient occlusion.
	shaft_strength:    f32, // 0 disables light shafts; scales the sun colour added along sky-visible rays.
	bloom_strength:    f32, // 0 disables bloom; ~0.05 is a soft glow.
}
