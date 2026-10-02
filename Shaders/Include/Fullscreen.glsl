// Vertex stage for fullscreen passes: one oversized triangle from gl_VertexID, uv in [0, 1] over the visible area.
// Include it, then start your own `#stage fragment`.
#stage vertex
out vec2 v_uv;
void main() {
	vec2 corner = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
	v_uv = corner;
	gl_Position = vec4(corner * 2.0 - 1.0, 0.0, 1.0);
}
