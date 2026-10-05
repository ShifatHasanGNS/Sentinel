package Render

import "core:math"

import "../Procedural"

Bounds :: struct {
	lowest:  [3]f32,
	highest: [3]f32,
}

Draw_Item :: struct {
	mesh:               ^Mesh,
	model:              matrix[4, 4]f32,
	material_layer:     i32,
	uv_scale:           [2]f32,
	triplanar:          bool,
	illumination_model: Illumination_Model,
	emission:           [3]f32, // Linear radiance added regardless of lighting (lamps, glowing parts).
	terrain:            bool, // Blend materials by slope and height instead of using material_layer.
	bounds:             Maybe(Bounds), // World-space box, when known: lets the shadow pass skip the item for cascades that cannot see it.
	transparency:       f32, // 0 opaque .. 1 invisible. Drawn by screen-door dithering, since a deferred G-buffer holds one surface per pixel.
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
	cloud_offset_meters: [2]f32, // How far the wind has carried the cloud layers; the sky shader scrolls its noise by it.
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
	ground_level_meters: f32, // Where walls meet the ground, for weathering (splash and grime stay below ~1 m of it).
	particles:         []Particle, // Smoke and fire billboards, drawn after lighting.
	interiors:         []Interior_Volume, // Roofed rooms: sky light does not reach inside them.
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

// A roofed room as a box turned about +Y. Sky ambient and sky reflection are scaled down inside it (see Shaders/DeferredBase.glsl);
// direct lights still work, so the lamps in the room are what light it.
Interior_Volume :: struct {
	center:       [3]f32,
	half_extents: [3]f32,
	yaw_radians:  f32,
}

INTERIORS_MAX :: 24
INTERIOR_SLACK_METERS :: 0.08 // Matches Interior.glsl: surfaces on a room's faces count as inside it.

// The room containing the point, or -1 outside every room (the same test the shaders make, in the box's own axes).
Interior_Index_At :: proc(interiors: []Interior_Volume, point: [3]f32) -> int {
	for volume, index in interiors[:min(len(interiors), INTERIORS_MAX)] {
		offset := point - volume.center
		sine, cosine := math.sin(volume.yaw_radians), math.cos(volume.yaw_radians)
		local := [3]f32{offset.x * cosine - offset.z * sine, offset.y, offset.x * sine + offset.z * cosine}
		if abs(local.x) < volume.half_extents.x + INTERIOR_SLACK_METERS && abs(local.y) < volume.half_extents.y + INTERIOR_SLACK_METERS && abs(local.z) < volume.half_extents.z + INTERIOR_SLACK_METERS do return index
	}
	return -1
}
