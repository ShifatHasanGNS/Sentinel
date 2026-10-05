package Characters

import "../../Engine/Procedural"
import "../../Engine/Render"
import "../Materials"
import "../Weapons"
import la "core:math/linalg"

// Segments plus the weapon: the things drawn per soldier.
SLOT_COUNT :: len(Segment) + 1
WEAPON_SLOT :: len(Segment)

Slot_Group :: struct {
	mesh:     Render.Mesh,
	material: i32,
	emission: [3]f32,
}

// One instanced mesh per variant, body part and material; every character is one instance of each. A hundred soldiers cost the
// same number of draws as one.
Character_Renderer :: struct {
	groups: [Soldier_Variant][SLOT_COUNT][dynamic]Slot_Group,
}

Character_Renderer_Create :: proc(capacity_per_variant: int) -> (renderer: Character_Renderer) {
	for variant in Soldier_Variant {
		for segment in Segment {
			assembly := Soldier_Segment_Assembly(variant, segment)
			upload_groups(&renderer.groups[variant][int(segment)], assembly, capacity_per_variant)
		}
		weapon := Weapons.Weapon_Build(Soldier_Weapon(variant))
		upload_groups(&renderer.groups[variant][WEAPON_SLOT], weapon, capacity_per_variant)
	}
	return renderer
}

Character_Renderer_Destroy :: proc(renderer: ^Character_Renderer) {
	for &variant_slots in renderer.groups {
		for &slot in variant_slots {
			for &group in slot do Render.Mesh_Destroy(&group.mesh)
			delete(slot)
		}
	}
}

// Poses every character, writes their transforms into the instance buffers, and returns the draw items for the groups in use.
Character_Renderer_Items :: proc(renderer: ^Character_Renderer, characters: []Character, allocator := context.temp_allocator) -> (items: [dynamic]Render.Draw_Item) {
	items = make([dynamic]Render.Draw_Item, allocator)
	poses := make([]Pose, len(characters), allocator)
	for character, index in characters do poses[index] = Character_Pose(character)
	for variant in Soldier_Variant {
		for slot in 0 ..< SLOT_COUNT {
			instances := make([dynamic]Render.Instance, allocator)
			for character, index in characters {
				if character.variant != variant || (slot == WEAPON_SLOT && character.hide_weapon) do continue
				model := Weapon_Matrix(poses[index]) if slot == WEAPON_SLOT else Segment_Matrix(poses[index], Segment(slot))
				append(&instances, Render.Instance{model = model})
			}
			if len(instances) == 0 do continue
			for &group in renderer.groups[variant][slot] {
				for &instance in instances do instance.material_layer = f32(group.material)
				Render.Mesh_Set_Instances(&group.mesh, instances[:])
				append(&items, Render.Draw_Item{mesh = &group.mesh, model = la.MATRIX4F32_IDENTITY, uv_scale = {1, 1}, triplanar = true, illumination_model = illumination_for(group.material), emission = group.emission})
			}
		}
	}
	return items
}

@(private = "file")
upload_groups :: proc(slot: ^[dynamic]Slot_Group, assembly: Procedural.Assembly, capacity: int) {
	assembly := assembly
	defer Procedural.Assembly_Destroy(&assembly)
	for group in assembly.groups {
		append(slot, Slot_Group{Render.Mesh_Upload_Instanced(group.mesh, capacity), group.material, group.emission})
	}
}

// Cloth is rough and matte (Oren-Nayar); skin keeps a subsurface wrap; everything else is a microfacet surface.
@(private = "file")
illumination_for :: proc(material: i32) -> Render.Illumination_Model {
	switch Materials.Surface_Material(material) {
	case .Skin: return .Subsurface
	case .Canvas, .Fabric_Desert, .Fabric_Dark, .Woodland_Camo, .Grass, .Leaves, .Needles: return .Oren_Nayar
	case .Concrete, .Rusted_Metal, .Sand, .Dirt, .Rock, .Painted_Metal, .Asphalt, .Wood, .Rubber, .Glass, .Olive_Paint, .Gunmetal, .Bark, .Birch_Bark: return .Cook_Torrance
	}
	return .Cook_Torrance
}
