// Roofed rooms as boxes turned about +Y. Shared by the ambient pass (sky light does not reach rooms) and the light volumes (a lamp
// lights only the room it is in, an outside lamp never lights a room). Boxes are set by Render.Frame.interiors.

const int INTERIORS_MAX = 24;
uniform int u_InteriorCount;
uniform vec4 u_InteriorCenter[INTERIORS_MAX]; // xyz center, w unused
uniform vec2 u_InteriorTurn[INTERIORS_MAX]; // cos and sin of the yaw, computed once on the CPU
uniform vec3 u_InteriorHalf[INTERIORS_MAX];
const float INTERIOR_AMBIENT_FRACTION = 0.5; // Daylight reaching a room through its windows and door, after bouncing off the walls.
const float INTERIOR_EDGE_METERS = 0.06;
const float INTERIOR_SLACK_METERS = 0.08; // The walls, floor and ceiling lie on the box faces; growing the box a little puts their inner surfaces inside it.

// Distance inside box i along its tightest axis (negative outside it), measured in the box's own axes.
float interior_depth(int i, vec3 position) {
	vec3 offset = position - u_InteriorCenter[i].xyz;
	float c = u_InteriorTurn[i].x, s = u_InteriorTurn[i].y;
	vec3 local = vec3(offset.x * c - offset.z * s, offset.y, offset.x * s + offset.z * c);
	vec3 margin = u_InteriorHalf[i] + INTERIOR_SLACK_METERS - abs(local);
	return min(margin.x, min(margin.y, margin.z));
}

// Index of the room containing the point, or -1 outside every room.
int interior_index(vec3 position) {
	for (int i = 0; i < u_InteriorCount; i++) {
		if (interior_depth(i, position) > 0.0) return i;
	}
	return -1;
}

// Ambient scale: a small fraction inside a room, fading in over a few centimeters at the surfaces.
float interior_ambient_scale(vec3 position) {
	float scale = 1.0;
	for (int i = 0; i < u_InteriorCount; i++) {
		float inside = smoothstep(0.0, INTERIOR_EDGE_METERS, interior_depth(i, position));
		scale = min(scale, mix(1.0, INTERIOR_AMBIENT_FRACTION, inside));
	}
	return scale;
}
