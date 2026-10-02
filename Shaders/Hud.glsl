#version 410 core
#stage vertex
layout(location = 0) in vec2 a_Position;
layout(location = 1) in vec4 a_Color;
uniform vec2 u_ScreenSize;
out vec4 v_color;
// Pixel coordinates, origin top-left, to clip space.
void main() {
	gl_Position = vec4(a_Position.x / u_ScreenSize.x * 2.0 - 1.0, 1.0 - a_Position.y / u_ScreenSize.y * 2.0, 0.0, 1.0);
	v_color = a_Color;
}
#stage fragment
in vec4 v_color;
out vec4 color;
void main() {
	color = v_color;
}
