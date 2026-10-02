#version 410 core
#stage vertex
layout(location = 0) in vec3 a_Position;
uniform mat4 u_LightViewProjection;
uniform mat4 u_Model;
void main() {
	gl_Position = u_LightViewProjection * u_Model * vec4(a_Position, 1.0);
}
#stage fragment
void main() {
}
