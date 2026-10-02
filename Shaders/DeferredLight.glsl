#version 410 core
#include "Gbuffer.glsl"
#include "Brdf.glsl"
#include "Lighting.glsl"
#include "GbufferRead.glsl"
#stage vertex
layout(location = 0) in vec3 a_Position;
uniform mat4 u_Model;
uniform mat4 u_ViewProjection;
void main() {
	gl_Position = u_ViewProjection * u_Model * vec4(a_Position, 1.0);
}
#stage fragment
out vec4 color;
uniform Light u_Light;
uniform vec2 u_ScreenSize;

// Drawn once per local light over a proxy sphere of radius `range`, additively blended onto the lit scene.
void main() {
	Gbuffer_Sample surface = gbuffer_read(gl_FragCoord.xy / u_ScreenSize);
	if (surface.depth >= 1.0) discard;
	vec3 view = normalize(u_CameraPosition - surface.position);
	color = vec4(shade_light(u_Light, surface.model, surface.position, surface.normal, view, surface.albedo, surface.roughness, surface.metallic), 1.0);
}
