#version 410 core
#stage vertex
layout(location = 0) in vec3 a_Position;
layout(location = 4) in vec4 a_ModelColumn0;
layout(location = 5) in vec4 a_ModelColumn1;
layout(location = 6) in vec4 a_ModelColumn2;
layout(location = 7) in vec4 a_ModelColumn3;
layout(location = 8) in vec4 a_InstanceData;
uniform mat4 u_ViewProjection;
flat out float v_layer;
void main() {
	mat4 model = mat4(a_ModelColumn0, a_ModelColumn1, a_ModelColumn2, a_ModelColumn3);
	v_layer = a_InstanceData.x;
	gl_Position = u_ViewProjection * model * vec4(a_Position, 1.0);
}
#stage fragment
flat in float v_layer;
out vec4 color;
void main() {
	color = vec4(v_layer / 10.0, 1.0, 0.0, 1.0);
}
