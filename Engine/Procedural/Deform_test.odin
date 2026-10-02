package Procedural

import "core:math"
import "core:math/linalg"
import "core:testing"

clone_mesh :: proc(mesh: Mesh) -> (copy: Mesh) {
	for vertex in mesh.vertices do append(&copy.vertices, vertex)
	for index in mesh.indices do append(&copy.indices, index)
	return
}

@(test)
test_noise_displacement_with_zero_amplitude_changes_nothing :: proc(t: ^testing.T) {
	original := Sphere_Create(1, 16, 8)
	defer Mesh_Destroy(&original)
	deformed := clone_mesh(original)
	defer Mesh_Destroy(&deformed)
	Mesh_Deform(&deformed, {Noise_Displace{amplitude = 0, frequency = 3, octaves = 3, seed = 1}})
	for vertex, index in original.vertices {
		testing.expect(t, linalg.length(vertex.position - deformed.vertices[index].position) < 1e-6)
		testing.expect(t, linalg.length(vertex.normal - deformed.vertices[index].normal) < 1e-3)
	}
}

@(test)
test_noise_displacement_is_bounded_deterministic_and_seed_dependent :: proc(t: ^testing.T) {
	original := Sphere_Create(1, 24, 12)
	defer Mesh_Destroy(&original)
	first, second, other_seed := clone_mesh(original), clone_mesh(original), clone_mesh(original)
	defer Mesh_Destroy(&first)
	defer Mesh_Destroy(&second)
	defer Mesh_Destroy(&other_seed)
	amplitude: f32 = 0.2
	Mesh_Deform(&first, {Noise_Displace{amplitude, 2, 3, 5}})
	Mesh_Deform(&second, {Noise_Displace{amplitude, 2, 3, 5}})
	Mesh_Deform(&other_seed, {Noise_Displace{amplitude, 2, 3, 6}})
	moved, differs := false, false
	for vertex, index in original.vertices {
		displacement := linalg.length(first.vertices[index].position - vertex.position)
		testing.expect(t, displacement <= amplitude + 1e-5)
		testing.expect_value(t, first.vertices[index].position, second.vertices[index].position)
		if displacement > 0.01 do moved = true
		if first.vertices[index].position != other_seed.vertices[index].position do differs = true
	}
	testing.expect(t, moved && differs)
	testing.expect_value(t, len(first.indices), len(original.indices))
}

// Interior vertices of a dense mesh: the analytic normal must agree with the average of the surrounding deformed faces.
@(test)
test_displaced_normals_agree_with_the_deformed_faces :: proc(t: ^testing.T) {
	mesh := Sphere_Create(1, 96, 48)
	defer Mesh_Destroy(&mesh)
	Mesh_Deform(&mesh, {Noise_Displace{0.08, 1.5, 2, 11}})
	face_sum := make([][3]f32, len(mesh.vertices))
	defer delete(face_sum)
	for first := 0; first + 2 < len(mesh.indices); first += 3 {
		a, b, c := mesh.indices[first], mesh.indices[first + 1], mesh.indices[first + 2]
		area_normal := linalg.cross(mesh.vertices[b].position - mesh.vertices[a].position, mesh.vertices[c].position - mesh.vertices[a].position)
		face_sum[a] += area_normal
		face_sum[b] += area_normal
		face_sum[c] += area_normal
	}
	for vertex, index in mesh.vertices {
		poleward := abs(vertex.position.y) > 0.9
		if poleward || linalg.length(face_sum[index]) < 1e-6 do continue
		testing.expect(t, linalg.dot(vertex.normal, linalg.normalize(face_sum[index])) > 0.97)
		testing.expect(t, abs(linalg.length(vertex.normal) - 1) < 1e-4)
		testing.expect(t, abs(linalg.dot(vertex.normal, vertex.tangent.xyz)) < 1e-3)
	}
}

@(test)
test_taper_scales_the_top_and_tilts_the_side_normals :: proc(t: ^testing.T) {
	mesh := Cylinder_Create(1, 2, 32)
	defer Mesh_Destroy(&mesh)
	Mesh_Deform(&mesh, {Taper{scale_at_bottom = 1, scale_at_top = 0.5}})
	for vertex in mesh.vertices {
		horizontal := linalg.length([2]f32{vertex.position.x, vertex.position.z})
		if vertex.normal.x == 0 && vertex.normal.z == 0 do continue // Cap normals.
		expected_radius := 1 - 0.5 * (vertex.position.y + 1) / 2
		testing.expect(t, abs(horizontal - expected_radius) < 1e-4)
		testing.expect(t, abs(vertex.normal.y - 0.5 / math.sqrt(f32(4.25))) < 2e-3) // Side slopes 0.5 inward over height 2.
	}
}

@(test)
test_twist_rotates_each_height_about_the_axis :: proc(t: ^testing.T) {
	original := Cylinder_Create(1, 2, 16)
	defer Mesh_Destroy(&original)
	twisted := clone_mesh(original)
	defer Mesh_Destroy(&twisted)
	total: f32 = math.PI / 2
	Mesh_Deform(&twisted, {Twist{radians_total = total}})
	for vertex, index in original.vertices {
		fraction := (vertex.position.y + 1) / 2
		expected := linalg.matrix3_rotate_f32(total * fraction, {0, 1, 0}) * vertex.position
		testing.expect(t, linalg.length(twisted.vertices[index].position - expected) < 1e-4)
	}
}

@(test)
test_bend_wraps_the_height_axis_onto_a_circle :: proc(t: ^testing.T) {
	original := Box_Create({0.4, 4, 0.4})
	defer Mesh_Destroy(&original)
	bent := clone_mesh(original)
	defer Mesh_Destroy(&bent)
	curvature: f32 = 0.5
	Mesh_Deform(&bent, {Bend{curvature = curvature}})
	radius := 1 / curvature
	for vertex, index in original.vertices {
		moved := bent.vertices[index].position
		distance_from_circle_center := linalg.length([2]f32{moved.x - radius, moved.y})
		testing.expect(t, abs(distance_from_circle_center - (radius - vertex.position.x)) < 2e-4)
		testing.expect_value(t, moved.z, vertex.position.z)
	}
}

@(test)
test_bulge_widens_the_middle_and_leaves_the_ends :: proc(t: ^testing.T) {
	mesh := Sphere_Create(1, 32, 16)
	defer Mesh_Destroy(&mesh)
	Mesh_Deform(&mesh, {Bulge{amount = 0.5}})
	lowest, highest := Mesh_Bounds(mesh)
	testing.expect(t, abs(highest.x - 1.5) < 1e-4) // Equator: radius 1 scaled by 1 + 0.5.
	testing.expect(t, abs(highest.y - 1) < 1e-5 && abs(lowest.y + 1) < 1e-5)
	for vertex in mesh.vertices {
		if abs(vertex.position.y) > 0.999 do testing.expect(t, abs(vertex.position.x) < 1e-3 && abs(vertex.position.z) < 1e-3)
		testing.expect(t, abs(linalg.length(vertex.normal) - 1) < 1e-4)
	}
}
