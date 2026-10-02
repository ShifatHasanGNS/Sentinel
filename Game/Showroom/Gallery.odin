package Showroom

import "../../Engine/Procedural"
import "../../Engine/Render"
import "../Materials"
import "core:math"
import la "core:math/linalg"

GALLERY_SPACING_METERS :: 3.0
GALLERY_ROW_SPACING_METERS :: 3.5
MATERIAL_SPHERE_SPACING_METERS :: 2.4
TRIPLANAR_TILES_PER_METER :: 0.5

Gallery_Item :: struct {
	mesh:     Render.Mesh,
	model:    matrix[4, 4]f32,
	material: Materials.Surface_Material,
	uv_scale: [2]f32,
	triplanar: bool,
	illumination_model: Render.Illumination_Model,
}

Gallery_Entry :: struct {
	mesh:      Procedural.Mesh,
	material:  Materials.Surface_Material,
	uv_scale:  [2]f32,
	triplanar: bool,
}

// Row 0: every primitive plain. Row 1: deformers. Row 2: one sphere per material. Row 3: one sphere per illumination model.
Gallery_Create :: proc() -> (items: [dynamic]Gallery_Item) {
	plain := [?]Gallery_Entry{
		{Procedural.Box_Create({1.5, 1.5, 1.5}), .Concrete, {1, 1}, false},
		{Procedural.Sphere_Create(0.9, 32, 16), .Rusted_Metal, {4, 2}, false},
		{Procedural.Cylinder_Create(0.7, 1.6, 32), .Rusted_Metal, {4, 1}, false},
		{Procedural.Cone_Create(0.8, 1.6, 32), .Canvas, {4, 2}, false},
		{Procedural.Capsule_Create(0.5, 0.8, 32, 12), .Woodland_Camo, {4, 2}, false},
		{Procedural.Torus_Create(0.8, 0.3, 40, 20), .Rusted_Metal, {6, 2}, false},
		{Procedural.Wedge_Create({1.5, 1.5, 1.5}), .Concrete, {1, 1}, false},
	}
	deformed := [?]Gallery_Entry{
		{deformed_mesh(Procedural.Sphere_Create(0.9, 64, 32), {Procedural.Noise_Displace{0.25, 1.2, 4, 3}}), .Rock, {}, true},
		{deformed_mesh(Procedural.Cylinder_Create(0.7, 1.8, 32, 12), {Procedural.Taper{1, 0.4}}), .Canvas, {4, 2}, false},
		{deformed_mesh(Procedural.Box_Create({1.2, 1.8, 1.2}, {8, 16, 8}), {Procedural.Twist{math.PI}}), .Woodland_Camo, {}, true},
		{deformed_mesh(Procedural.Capsule_Create(0.35, 1.6, 24, 8, 16), {Procedural.Bend{0.6}}), .Grass, {4, 4}, false},
		{deformed_mesh(Procedural.Cylinder_Create(0.5, 1.8, 32, 16), {Procedural.Bulge{0.6}}), .Rusted_Metal, {4, 2}, false},
		{deformed_mesh(Procedural.Box_Create({1.4, 1.4, 1.4}, {16, 16, 16}), {Procedural.Noise_Displace{0.12, 2, 3, 7}}), .Rock, {}, true},
		{deformed_mesh(Procedural.Torus_Create(0.8, 0.3, 48, 24), {Procedural.Noise_Displace{0.1, 3, 3, 9}}), .Dirt, {}, true},
	}
	add_row(&items, plain[:], 0)
	add_row(&items, deformed[:], GALLERY_ROW_SPACING_METERS)
	add_material_spheres(&items, 2 * GALLERY_ROW_SPACING_METERS)
	add_model_spheres(&items, 3 * GALLERY_ROW_SPACING_METERS)
	return items
}

Gallery_Destroy :: proc(items: ^[dynamic]Gallery_Item) {
	for &item in items do Render.Mesh_Destroy(&item.mesh)
	delete(items^)
}

@(private = "file")
deformed_mesh :: proc(mesh: Procedural.Mesh, deformers: []Procedural.Deformer) -> Procedural.Mesh {
	mesh := mesh
	Procedural.Mesh_Deform(&mesh, deformers)
	return mesh
}

@(private = "file")
add_row :: proc(items: ^[dynamic]Gallery_Item, entries: []Gallery_Entry, z_meters: f32) {
	for &entry, index in entries {
		x_meters := (f32(index) - f32(len(entries) - 1) / 2) * GALLERY_SPACING_METERS
		append(items, Gallery_Item{Render.Mesh_Upload(entry.mesh), la.matrix4_translate_f32({x_meters, 1, z_meters}), entry.material, entry.uv_scale, entry.triplanar, .Cook_Torrance})
		Procedural.Mesh_Destroy(&entry.mesh)
	}
}

@(private = "file")
add_material_spheres :: proc(items: ^[dynamic]Gallery_Item, z_meters: f32) {
	count := len(Materials.Surface_Material)
	for material, index in Materials.Surface_Material {
		sphere := Procedural.Sphere_Create(1, 48, 24)
		x_meters := (f32(index) - f32(count - 1) / 2) * MATERIAL_SPHERE_SPACING_METERS
		append(items, Gallery_Item{Render.Mesh_Upload(sphere), la.matrix4_translate_f32({x_meters, 1, z_meters}), material, {4, 2}, false, .Cook_Torrance})
		Procedural.Mesh_Destroy(&sphere)
	}
}

@(private = "file")
add_model_spheres :: proc(items: ^[dynamic]Gallery_Item, z_meters: f32) {
	count := len(Render.Illumination_Model)
	for model, index in Render.Illumination_Model {
		sphere := Procedural.Sphere_Create(1, 48, 24)
		x_meters := (f32(index) - f32(count - 1) / 2) * MATERIAL_SPHERE_SPACING_METERS
		append(items, Gallery_Item{Render.Mesh_Upload(sphere), la.matrix4_translate_f32({x_meters, 1, z_meters}), .Painted_Metal, {4, 2}, false, model})
		Procedural.Mesh_Destroy(&sphere)
	}
}
