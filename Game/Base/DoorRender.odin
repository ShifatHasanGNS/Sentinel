package Base

import "../Catalogue"
import "../../Engine/Procedural"
import "../../Engine/Render"
import la "core:math/linalg"

Leaf_Group :: struct {
	mesh:     Render.Mesh,
	material: i32,
	emission: [3]f32,
}

// One mesh set per distinct door (kind, size, style), shared by every door that looks like it.
Leaf_Mesh :: struct {
	spec:   Catalogue.Door_Spec,
	groups: [dynamic]Leaf_Group,
}

Door_Renderer :: struct {
	leaves: [dynamic]Leaf_Mesh,
}

Door_Renderer_Create :: proc(doors: []Door) -> (renderer: Door_Renderer) {
	for door in doors {
		if _, found := leaf_index(renderer, door.spec); found do continue
		leaf := Leaf_Mesh{spec = door.spec}
		assembly := Catalogue.Door_Leaf_Build(door.spec)
		defer Procedural.Assembly_Destroy(&assembly)
		for group in assembly.groups do append(&leaf.groups, Leaf_Group{Render.Mesh_Upload(group.mesh), group.material, group.emission})
		append(&renderer.leaves, leaf)
	}
	return renderer
}

Door_Renderer_Destroy :: proc(renderer: ^Door_Renderer) {
	for &leaf in renderer.leaves {
		for &group in leaf.groups do Render.Mesh_Destroy(&group.mesh)
		delete(leaf.groups)
	}
	delete(renderer.leaves)
}

// Draw items for every leaf at its current opening; the same items cast shadows.
Door_Renderer_Items :: proc(renderer: ^Door_Renderer, doors: []Door, allocator := context.temp_allocator) -> (items: [dynamic]Render.Draw_Item) {
	items = make([dynamic]Render.Draw_Item, allocator)
	for door in doors {
		index, found := leaf_index(renderer^, door.spec)
		if !found do continue
		for &group in renderer.leaves[index].groups {
			append(&items, Render.Draw_Item{mesh = &group.mesh, model = Door_Model(door), material_layer = group.material, uv_scale = {1, 1}, triplanar = true, illumination_model = .Cook_Torrance, emission = group.emission})
		}
	}
	return items
}

@(private = "file")
leaf_index :: proc(renderer: Door_Renderer, spec: Catalogue.Door_Spec) -> (index: int, found: bool) {
	for leaf, candidate in renderer.leaves {
		if leaf.spec.width == spec.width && leaf.spec.height == spec.height && leaf.spec.side == spec.side && leaf.spec.style == spec.style do return candidate, true
	}
	return 0, false
}
