package Catalogue

import "../../Engine/Procedural"

Door_Style :: enum {
	Plank, // A wooden door.
	Sheet, // A painted or rusted metal sheet door.
	Mesh_Gate, // A frame filled with bars.
}

// A hinged door in an object's own frame (+Z is the front, y = 0 the ground). The leaf closes along the wall from the hinge
// toward +X (side = 1) or -X (side = -1) and swings outward, toward +Z. Doors with the same group move together (a gate's two leaves).
Door_Spec :: struct {
	hinge:  [3]f32,
	width:  f32,
	height: f32,
	side:   f32,
	group:  int,
	style:  Door_Style,
}

// The middle of the opening in the wall.
Door_Center_X :: proc(door: Door_Spec) -> f32 {
	return door.hinge.x + door.side * door.width / 2
}

@(rodata)
BARRACKS_DOORS := [2]Door_Spec{
	{hinge = {-7.65, 0.3, 3}, width = 1.3, height = 2.1, side = 1, style = .Plank},
	{hinge = {6.35, 0.3, 3}, width = 1.3, height = 2.1, side = 1, group = 1, style = .Plank},
}
@(rodata)
HEADQUARTERS_DOORS := [1]Door_Spec{{hinge = {-1, 0.3, 5}, width = 2, height = 2.3, side = 1, style = .Plank}}
@(rodata)
MESS_HALL_DOORS := [1]Door_Spec{{hinge = {4.7, 0.3, 4}, width = 1.6, height = 2.1, side = 1, style = .Plank}}
@(rodata)
GENERATOR_SHED_DOORS := [1]Door_Spec{{hinge = {-1.35, 0.1, 1.5}, width = 1.1, height = 1.95, side = 1, style = .Sheet}} // Hinge y is the floor slab's top: a body standing on it is 0.1 m higher.
@(rodata)
GUARD_POST_DOORS := [1]Door_Spec{{hinge = {-1.35, 0.1, 1.5}, width = 0.95, height = 2, side = 1, style = .Plank}}
@(rodata)
BUNKER_DOORS := [1]Door_Spec{{hinge = {1.4, 0.1, 3}, width = 1.2, height = 2, side = 1, style = .Sheet}}
@(rodata)
GATE_DOORS := [2]Door_Spec{
	{hinge = {-3.95, 0, 0}, width = 3.8, height = 2.9, side = 1, style = .Mesh_Gate},
	{hinge = {3.95, 0, 0}, width = 3.8, height = 2.9, side = -1, style = .Mesh_Gate},
}

// Every door an object kind has; empty for most.
Catalogue_Doors :: proc(kind: Object_Kind) -> []Door_Spec {
	#partial switch kind {
	case .Barracks: return BARRACKS_DOORS[:]
	case .Headquarters: return HEADQUARTERS_DOORS[:]
	case .Mess_Hall: return MESS_HALL_DOORS[:]
	case .Generator_Shed: return GENERATOR_SHED_DOORS[:]
	case .Guard_Post: return GUARD_POST_DOORS[:]
	case .Bunker: return BUNKER_DOORS[:]
	case .Gate: return GATE_DOORS[:]
	}
	return nil
}

// The door leaf in its own hinge frame: the hinge at the origin, the leaf along `side` * x, standing from y = 0 to the height.
Door_Leaf_Build :: proc(door: Door_Spec) -> Procedural.Assembly {
	parts := make(Parts)
	defer delete(parts)
	reach := door.side * door.width / 2
	switch door.style {
	case .Plank:
		add_box(&parts, {door.width - 0.04, door.height, 0.06}, {reach, door.height / 2, 0}, .Wood, false)
		add_box(&parts, {0.1, 0.05, 0.1}, {door.side * (door.width - 0.15), door.height * 0.48, 0.06}, .Rusted_Metal, false)
	case .Sheet:
		add_box(&parts, {door.width - 0.04, door.height, 0.05}, {reach, door.height / 2, 0}, .Rusted_Metal, false)
		add_box(&parts, {0.1, 0.05, 0.1}, {door.side * (door.width - 0.15), door.height * 0.48, 0.06}, .Painted_Metal, false)
	case .Mesh_Gate:
		add_box(&parts, {door.width, 0.12, 0.1}, {reach, door.height - 0.06, 0}, .Rusted_Metal, false)
		add_box(&parts, {door.width, 0.12, 0.1}, {reach, 0.3, 0}, .Rusted_Metal, false)
		bars := int(door.width / 0.3)
		for index in 0 ..< bars do add_box(&parts, {0.05, door.height - 0.4, 0.05}, {door.side * (0.15 + f32(index) * 0.3), door.height / 2 + 0.05, 0}, .Rusted_Metal, false)
	}
	return Procedural.Assembly_Build(parts[:])
}

// The closed leaf's solid volume in the object's frame: an invisible slab the width and height of the opening.
Door_Closed_Box :: proc(door: Door_Spec) -> Procedural.Collision_Box {
	x0, x1 := door.hinge.x, door.hinge.x + door.side * door.width
	return {{min(x0, x1), door.hinge.y, door.hinge.z - 0.07}, {max(x0, x1), door.hinge.y + door.height, door.hinge.z + 0.07}}
}
