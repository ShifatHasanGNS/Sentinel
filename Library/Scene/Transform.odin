package Scene

import la "core:math/linalg"

import geo "../Geometry"
import sd "../Engine/Shader"

// Sentinel value for Node.Parent and Find_Node's "not found" return.
NO_PARENT :: -1

Transform :: struct {
	Position: la.Vector3f32,
	Rotation: la.Vector3f32, // radians: X = pitch, Y = yaw, Z = roll
	Scale:    la.Vector3f32,
}

Identity_Transform :: proc() -> Transform {
	return Transform{Position = {0, 0, 0}, Rotation = {0, 0, 0}, Scale = {1, 1, 1}}
}

// translate * rotate * scale; rotate = yaw * pitch * roll.
Local_Matrix :: proc(t: Transform) -> la.Matrix4f32 {
	translate := la.matrix4_translate(t.Position)

	yaw := la.matrix4_rotate(t.Rotation.y, la.Vector3f32{0, 1, 0})
	pitch := la.matrix4_rotate(t.Rotation.x, la.Vector3f32{1, 0, 0})
	roll := la.matrix4_rotate(t.Rotation.z, la.Vector3f32{0, 0, 1})
	rotate := la.mul(yaw, la.mul(pitch, roll))

	scale := la.matrix4_scale(t.Scale)

	return la.mul(translate, la.mul(rotate, scale))
}

Material :: struct {
	BaseColor:        la.Vector3f32,
	SpecularStrength: f32,
	Shininess:        f32,
	EmissionColor:    la.Vector3f32,
	Reflective:       bool,
}

Default_Material :: proc(base_color: la.Vector3f32) -> Material {
	return Material{BaseColor = base_color, SpecularStrength = 0.25, Shininess = 16, EmissionColor = {0, 0, 0}}
}

Node :: struct {
	Name:     string,
	Parent:   int,
	Local:    Transform,
	Mesh:     geo.Mesh,
	Material: Material,
}

Hierarchy :: struct {
	Nodes: [dynamic]Node,
}

Destroy :: proc(h: ^Hierarchy) {
	for &node in h.Nodes {
		geo.Destroy(&node.Mesh)
	}
	delete(h.Nodes)
}

// Returns the new node's index; a parent must already exist at a lower index.
Add_Node :: proc(h: ^Hierarchy, name: string, parent: int, local: Transform, mesh: geo.Mesh, material: Material) -> int {
	assert(parent == NO_PARENT || (parent >= 0 && parent < len(h.Nodes)), "Add_Node: parent index out of range")
	append(&h.Nodes, Node{Name = name, Parent = parent, Local = local, Mesh = mesh, Material = material})
	return len(h.Nodes) - 1
}

// One top-down pass: world = parent_world * local. Caller owns/deletes the result.
Compute_World_Matrices :: proc(h: ^Hierarchy) -> [dynamic]la.Matrix4f32 {
	world := make([dynamic]la.Matrix4f32, 0, len(h.Nodes))

	for node, i in h.Nodes {
		local := Local_Matrix(node.Local)
		if node.Parent == NO_PARENT {
			append(&world, local)
		} else {
			assert(node.Parent < i, "Compute_World_Matrices: a parent must be added before its children")
			append(&world, la.mul(world[node.Parent], local))
		}
	}

	return world
}

World_Point :: proc(world_matrix: la.Matrix4f32, local_point: la.Vector3f32) -> la.Vector3f32 {
	p := la.mul(world_matrix, la.Vector4f32{local_point.x, local_point.y, local_point.z, 1})
	return la.Vector3f32{p.x, p.y, p.z}
}

World_Position :: proc(world_matrix: la.Matrix4f32) -> la.Vector3f32 {
	return World_Point(world_matrix, la.Vector3f32{0, 0, 0})
}

// Ignores translation (w = 0) — for direction vectors, not points.
World_Direction :: proc(world_matrix: la.Matrix4f32, local_direction: la.Vector3f32) -> la.Vector3f32 {
	d := la.mul(world_matrix, la.Vector4f32{local_direction.x, local_direction.y, local_direction.z, 0})
	return la.Vector3f32{d.x, d.y, d.z}
}

// Inverse-transpose of the upper-left 3x3, for correct lighting under non-uniform scale.
Normal_Matrix :: proc(world_matrix: la.Matrix4f32) -> la.Matrix3f32 {
	return la.matrix3_from_matrix4(la.matrix4_inverse_transpose(world_matrix))
}

// Linear scan; fine at this project's node count.
Find_Node :: proc(h: ^Hierarchy, name: string) -> int {
	for node, i in h.Nodes {
		if node.Name == name do return i
	}
	return NO_PARENT
}

// Zero-mesh nodes (pure pivots) are silently skipped.
Draw_Node :: proc(shader: ^sd.Shader, view, projection, model: la.Matrix4f32, mesh: ^geo.Mesh, material: Material) {
	if len(mesh.Indices) == 0 do return

	normal_matrix := Normal_Matrix(model)
	mvp := la.mul(projection, la.mul(view, model))
	model_matrix := model

	sd.SetUniform(shader, "u_MVP", &mvp)
	sd.SetUniform(shader, "u_Model", &model_matrix)
	sd.SetUniform(shader, "u_NormalMatrix", &normal_matrix)
	sd.SetUniform(shader, "u_BaseColor", material.BaseColor.r, material.BaseColor.g, material.BaseColor.b)
	sd.SetUniform(shader, "u_SpecularStrength", material.SpecularStrength)
	sd.SetUniform(shader, "u_Shininess", material.Shininess)
	sd.SetUniform(shader, "u_EmissionColor", material.EmissionColor.r, material.EmissionColor.g, material.EmissionColor.b)
	reflective_value: i32 = 0
	if material.Reflective do reflective_value = 1
	sd.SetUniform(shader, "u_IsReflectiveSurface", reflective_value)
	geo.Draw(mesh, shader)
}
