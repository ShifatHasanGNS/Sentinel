package Base

import "../Catalogue"
import "../../Engine/Procedural"
import "../../Engine/Render"
import la "core:math/linalg"

// What the renderer draws for one material group of one object kind: an instanced mesh with one instance per placement.
Group_Render :: struct {
	mesh:     Render.Mesh,
	material: i32,
	emission: [3]f32,
}

// The base ready to draw: for each kind that is placed, its groups instanced across all its placements.
Base_Scene :: struct {
	layout: Layout,
	groups: [Catalogue.Object_Kind][dynamic]Group_Render,
	shadow: [Catalogue.Object_Kind]Maybe(Render.Mesh), // Structure only, sharing the first group's instances.
}

// ground_height_meters is the plateau surface the objects stand on.
Base_Scene_Create :: proc(layout: Layout, ground_height_meters: f32) -> (scene: Base_Scene) {
	scene.layout = layout
	for kind in Catalogue.Object_Kind {
		instances := make([dynamic]Render.Instance, context.temp_allocator)
		placed_model := proc(placement: Placement, ground: f32) -> matrix[4, 4]f32 {
			return la.matrix4_translate_f32({placement.x, ground, placement.z}) * la.matrix4_rotate_f32(la.to_radians(placement.yaw_degrees), {0, 1, 0})
		}
		for placement in layout.placements {
			if placement.kind == kind do append(&instances, Render.Instance{model = placed_model(placement, ground_height_meters)})
		}
		if len(instances) == 0 do continue
		assembly := Catalogue.Catalogue_Build(kind)
		defer Procedural.Assembly_Destroy(&assembly)
		for group in assembly.groups {
			mesh := Render.Mesh_Upload_Instanced(group.mesh, len(instances))
			for &instance in instances do instance.material_layer = f32(group.material)
			Render.Mesh_Set_Instances(&mesh, instances[:])
			append(&scene.groups[kind], Group_Render{mesh, group.material, group.emission})
		}
		scene.shadow[kind] = upload_shadow(kind, &scene.groups[kind][0].mesh)
	}
	return scene
}

Base_Scene_Destroy :: proc(scene: ^Base_Scene) {
	for &shadow in scene.shadow {
		if mesh, present := shadow.?; present {
			Render.Mesh_Destroy(&mesh)
		}
	}
	for &kind_groups in scene.groups {
		for &group in kind_groups do Render.Mesh_Destroy(&group.mesh)
		delete(kind_groups)
	}
	Layout_Destroy(&scene.layout)
}

// Draw items for every group; the instances carry transform and material, the item carries emission (scaled: lit windows and lamps
// barely glow in daylight, where their light is lost against the sun).
Base_Scene_Items :: proc(scene: ^Base_Scene, emission_scale: f32 = 1, allocator := context.temp_allocator) -> (items: [dynamic]Render.Draw_Item) {
	items = make([dynamic]Render.Draw_Item, allocator)
	for &kind_groups in scene.groups {
		for &group in kind_groups {
			append(&items, Render.Draw_Item{mesh = &group.mesh, model = la.MATRIX4F32_IDENTITY, uv_scale = {1, 1}, triplanar = true, illumination_model = .Cook_Torrance, emission = group.emission * emission_scale})
		}
	}
	return items
}

// Shadow casters: the structural meshes of every placed kind.
Base_Scene_Shadow_Items :: proc(scene: ^Base_Scene, allocator := context.temp_allocator) -> (items: [dynamic]Render.Draw_Item) {
	items = make([dynamic]Render.Draw_Item, allocator)
	for &shadow in scene.shadow {
		if mesh, present := &shadow.?; present do append(&items, Render.Draw_Item{mesh = mesh, model = la.MATRIX4F32_IDENTITY})
	}
	return items
}

@(private = "file")
upload_shadow :: proc(kind: Catalogue.Object_Kind, owner: ^Render.Mesh) -> Render.Mesh {
	assembly := Catalogue.Catalogue_Build_Shadow(kind)
	defer Procedural.Assembly_Destroy(&assembly)
	merged: Procedural.Mesh
	defer Procedural.Mesh_Destroy(&merged)
	for group in assembly.groups do Procedural.Mesh_Append(&merged, group.mesh, la.MATRIX4F32_IDENTITY)
	return Render.Mesh_Upload_Instanced_Sharing(merged, owner)
}
