#version 410 core
#include "Surface.glsl"
Surface recipe_surface(vec2 uv) {
	Surface surface;
	surface.albedo = vec3(0.5);
	surface.height = uv.x;
	surface.roughness = 0.25;
	surface.metallic = 0.75;
	surface.ambient_occlusion = 1.0;
	return surface;
}
#include "BakeMain.glsl"
