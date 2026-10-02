#version 410 core
#include "Tonemap.glsl"
#include "Fullscreen.glsl"
#stage fragment
in vec2 v_uv;
out vec4 color;
void main() {
	float exposure = gl_FragCoord.x < 1.0 ? 0.0 : exp2(mix(-10.0, 14.0, gl_FragCoord.x / 64.0));
	color = vec4(tonemap_aces(vec3(exposure)), exposure);
}
