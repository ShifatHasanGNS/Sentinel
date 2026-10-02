package Render

import "../GPU"
import "../Procedural"

// One placement of an instanced mesh. Five vec4s: the model matrix columns, then (material layer, padding).
Instance :: struct {
	model:          matrix[4, 4]f32,
	material_layer: f32,
	padding:        [3]f32,
}

Mesh :: struct {
	vertex_buffer:     GPU.Buffer,
	index_buffer:      GPU.Buffer,
	vertex_array:      GPU.Vertex_Array,
	instanced:         bool,
	instance_buffer:   GPU.Buffer,
	instance_count:    ^i32, // Heap-allocated and shared with shadow proxies; a pointer to a sibling struct would dangle when structs are copied.
	instance_capacity: int,
	owns_instances:    bool,
}

// Matches Procedural.Vertex: position, normal, tangent (xyz + handedness), uv.
Mesh_Upload :: proc(source: Procedural.Mesh) -> (mesh: Mesh) {
	mesh.vertex_buffer = GPU.Buffer_Create(.Vertex, source.vertices[:])
	mesh.index_buffer = GPU.Buffer_Create(.Index, source.indices[:])
	attributes := vertex_attributes()
	streams := [1]GPU.Vertex_Stream{{&mesh.vertex_buffer, attributes[:]}}
	mesh.vertex_array = GPU.Vertex_Array_Create(streams[:], &mesh.index_buffer, i32(len(source.indices)))
	return mesh
}

// A mesh drawn many times in one call: instance data lives in a second stream (locations 4 to 8, advancing per instance).
Mesh_Upload_Instanced :: proc(source: Procedural.Mesh, capacity: int) -> (mesh: Mesh) {
	assert(capacity > 0, "Mesh_Upload_Instanced: capacity must be positive")
	mesh.vertex_buffer = GPU.Buffer_Create(.Vertex, source.vertices[:])
	mesh.index_buffer = GPU.Buffer_Create(.Index, source.indices[:])
	mesh.instance_buffer = GPU.Buffer_Create_Empty(.Vertex, capacity * size_of(Instance), .Dynamic)
	attributes := vertex_attributes()
	instance_attributes: [5]GPU.Vertex_Attribute
	for &attribute in instance_attributes do attribute = {4, .Float32, false, 1}
	streams := [2]GPU.Vertex_Stream{{&mesh.vertex_buffer, attributes[:]}, {&mesh.instance_buffer, instance_attributes[:]}}
	mesh.vertex_array = GPU.Vertex_Array_Create(streams[:], &mesh.index_buffer, i32(len(source.indices)))
	mesh.instanced = true
	mesh.instance_capacity = capacity
	mesh.instance_count = new(i32)
	mesh.owns_instances = true
	return mesh
}

// A second mesh (typically a cheaper shadow proxy) that draws exactly the instances of `owner`, with no copy of the data.
// The owner must outlive it, but may be moved: only the heap-allocated count and the GL buffer are shared.
Mesh_Upload_Instanced_Sharing :: proc(source: Procedural.Mesh, owner: ^Mesh) -> (mesh: Mesh) {
	assert(owner.instanced && owner.owns_instances, "Mesh_Upload_Instanced_Sharing: owner must own its instances")
	mesh.vertex_buffer = GPU.Buffer_Create(.Vertex, source.vertices[:])
	mesh.index_buffer = GPU.Buffer_Create(.Index, source.indices[:])
	attributes := vertex_attributes()
	instance_attributes: [5]GPU.Vertex_Attribute
	for &attribute in instance_attributes do attribute = {4, .Float32, false, 1}
	streams := [2]GPU.Vertex_Stream{{&mesh.vertex_buffer, attributes[:]}, {&owner.instance_buffer, instance_attributes[:]}}
	mesh.vertex_array = GPU.Vertex_Array_Create(streams[:], &mesh.index_buffer, i32(len(source.indices)))
	mesh.instanced = true
	mesh.instance_count = owner.instance_count
	return mesh
}

Mesh_Set_Instances :: proc(mesh: ^Mesh, instances: []Instance) {
	assert(mesh.owns_instances, "Mesh_Set_Instances: mesh does not own instances")
	assert(len(instances) <= mesh.instance_capacity, "Mesh_Set_Instances: more instances than capacity")
	mesh.instance_count^ = i32(len(instances))
	if len(instances) > 0 do GPU.Buffer_Write(&mesh.instance_buffer, instances)
}

Mesh_Draw :: proc(mesh: ^Mesh) {
	count: i32 = 1
	if mesh.instanced do count = mesh.instance_count^
	if count == 0 do return
	GPU.Vertex_Array_Draw(&mesh.vertex_array, count)
}

Mesh_Destroy :: proc(mesh: ^Mesh) {
	GPU.Vertex_Array_Destroy(&mesh.vertex_array)
	GPU.Buffer_Destroy(&mesh.vertex_buffer)
	GPU.Buffer_Destroy(&mesh.index_buffer)
	if mesh.owns_instances {
		GPU.Buffer_Destroy(&mesh.instance_buffer)
		free(mesh.instance_count)
	}
}

@(private = "file")
vertex_attributes :: proc() -> [4]GPU.Vertex_Attribute {
	return {{3, .Float32, false, 0}, {3, .Float32, false, 0}, {4, .Float32, false, 0}, {2, .Float32, false, 0}}
}
