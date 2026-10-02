package Render

import "../GPU"
import "core:fmt"
import "core:math"
import la "core:math/linalg"

// Values match the LIGHT_* constants in Shaders/Include/Lighting.glsl.
Light_Kind :: enum i32 {
	Directional,
	Point,
	Spot,
	Area,
}

// Colour is linear RGB. intensity: irradiance for directional lights, radiant intensity for the rest.
Light :: struct {
	kind:                Light_Kind,
	color:               [3]f32,
	intensity:           f32,
	position:            [3]f32,
	direction:           [3]f32, // Directional: travel direction. Spot: cone axis.
	range_meters:        f32,
	inner_angle_degrees: f32,
	outer_angle_degrees: f32,
	half_extent_u:       [3]f32, // Area lights only; cross(u, v) is the emission normal.
	half_extent_v:       [3]f32,
}

Light_Directional :: proc(travel_direction, color: [3]f32, intensity: f32) -> Light {
	return Light{kind = .Directional, color = color, intensity = intensity, direction = la.normalize(travel_direction)}
}

Light_Point :: proc(position, color: [3]f32, intensity, range_meters: f32) -> Light {
	return Light{kind = .Point, color = color, intensity = intensity, position = position, range_meters = range_meters}
}

Light_Spot :: proc(position, axis, color: [3]f32, intensity, range_meters, inner_angle_degrees, outer_angle_degrees: f32) -> Light {
	assert(inner_angle_degrees < outer_angle_degrees, "Light_Spot: inner angle must be below outer angle")
	return Light{kind = .Spot, color = color, intensity = intensity, position = position, direction = la.normalize(axis), range_meters = range_meters, inner_angle_degrees = inner_angle_degrees, outer_angle_degrees = outer_angle_degrees}
}

// A width x height rectangle at position emitting toward `facing`.
Light_Area :: proc(position, facing, color: [3]f32, width_meters, height_meters, intensity, range_meters: f32) -> Light {
	facing_unit := la.normalize(facing)
	reference: [3]f32 = {0, 1, 0} if abs(facing_unit.y) < 0.99 else {1, 0, 0}
	right := la.normalize(la.cross(reference, facing_unit))
	up := la.cross(facing_unit, right)
	return Light{kind = .Area, color = color, intensity = intensity, position = position, range_meters = range_meters, half_extent_u = right * (width_meters / 2), half_extent_v = up * (height_meters / 2)}
}

// Sets every member of a GLSL `Light` struct uniform. Names are built per call; lights are few and this runs per light, not per pixel.
Light_Set_Uniforms :: proc(shader: ^GPU.Shader, uniform_name: string, light: Light) {
	member :: proc(uniform_name, field: string) -> string {
		return fmt.tprintf("%s.%s", uniform_name, field)
	}
	GPU.Shader_Set(shader, member(uniform_name, "type"), i32(light.kind))
	GPU.Shader_Set(shader, member(uniform_name, "color"), light.color)
	GPU.Shader_Set(shader, member(uniform_name, "intensity"), light.intensity)
	GPU.Shader_Set(shader, member(uniform_name, "position"), light.position)
	GPU.Shader_Set(shader, member(uniform_name, "direction"), light.direction)
	GPU.Shader_Set(shader, member(uniform_name, "range"), light.range_meters)
	GPU.Shader_Set(shader, member(uniform_name, "cos_inner"), math.cos(math.to_radians(light.inner_angle_degrees)))
	GPU.Shader_Set(shader, member(uniform_name, "cos_outer"), math.cos(math.to_radians(light.outer_angle_degrees)))
	GPU.Shader_Set(shader, member(uniform_name, "axis_u"), light.half_extent_u)
	GPU.Shader_Set(shader, member(uniform_name, "axis_v"), light.half_extent_v)
}
