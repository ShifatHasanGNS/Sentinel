#version 410 core
#include "IncludeShared.glsl"
#include "IncludeShared.glsl"
#stage vertex
void main() { gl_Position = vec4(SHARED_VALUE); }
#stage fragment
out vec4 color;
void main() { color = vec4(SHARED_VALUE); }
