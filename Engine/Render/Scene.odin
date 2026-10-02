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
}

Sky :: struct {
	zenith:    [3]f32,
	horizon:   [3]f32,
	ground:    [3]f32,
	sun_color: [3]f32,
	to_sun:    [3]f32, // Unit vector from the scene toward the sun.
}

// Everything the renderer needs for one frame. Slices and pointers must outlive the call.
Frame :: struct {
	camera:            Camera,
	items:             []Draw_Item,
	sun:               Light, // The one directional light.
	local_lights:      []Light, // Point, spot and area lights.
	sky:               Sky,
	materials:         ^Procedural.Texture_Set,
	sun_shadows:       bool,
	shadow_distance_meters: f32,
	exposure:          f32,
	vignette_strength: f32,
}
