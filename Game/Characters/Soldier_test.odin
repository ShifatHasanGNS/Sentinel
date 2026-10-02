package Characters

import "../../Engine/Procedural"
import "../Weapons"
import "core:math"
import "core:math/linalg"
import "core:slice"
import "core:testing"

// Which bone each segment's mesh must cover, so a limb mesh actually sits on its limb.
segment_bones := [Segment][2]Joint{
	.Torso = {.Pelvis, .Chest},
	.Head = {.Neck, .Head},
	.Upper_Arm_Left = {.Shoulder_Left, .Elbow_Left},
	.Upper_Arm_Right = {.Shoulder_Right, .Elbow_Right},
	.Forearm_Left = {.Elbow_Left, .Hand_Left},
	.Forearm_Right = {.Elbow_Right, .Hand_Right},
	.Thigh_Left = {.Hip_Left, .Knee_Left},
	.Thigh_Right = {.Hip_Right, .Knee_Right},
	.Shin_Left = {.Knee_Left, .Ankle_Left},
	.Shin_Right = {.Knee_Right, .Ankle_Right},
	.Foot_Left = {.Ankle_Left, .Ankle_Left},
	.Foot_Right = {.Ankle_Right, .Ankle_Right},
}

@(test)
test_every_segment_of_every_variant_is_a_valid_mesh :: proc(t: ^testing.T) {
	for variant in Soldier_Variant {
		for segment in Segment {
			assembly := Soldier_Segment_Assembly(variant, segment)
			defer Procedural.Assembly_Destroy(&assembly)
			testing.expectf(t, len(assembly.groups) > 0, "%v %v: empty", variant, segment)
			for group in assembly.groups {
				problem := Procedural.Mesh_Find_Problem(group.mesh)
				testing.expectf(t, problem == "", "%v %v: %s", variant, segment, problem)
			}
		}
	}
}

@(test)
test_a_soldier_has_human_proportions_and_stands_on_the_ground :: proc(t: ^testing.T) {
	for variant in Soldier_Variant {
		mesh := Soldier_Mesh_At_Pose(variant, Rest_Pose({0, 0, 0}, 0), false)
		defer Procedural.Mesh_Destroy(&mesh)
		lowest, highest := Procedural.Mesh_Bounds(mesh)
		size := highest - lowest
		testing.expectf(t, size.y > 1.65 && size.y < 1.95, "%v is %.2f m tall", variant, size.y)
		testing.expectf(t, size.x > 0.4 && size.x < 0.65, "%v is %.2f m wide", variant, size.x)
		testing.expectf(t, size.z > 0.18 && size.z < 0.65, "%v is %.2f m deep", variant, size.z) // Boots out front and a pack behind: about half a metre.
		testing.expectf(t, abs(lowest.y) < 0.03, "%v soles are at %.3f m", variant, lowest.y)
	}
}

@(test)
test_the_variants_differ_in_what_they_wear :: proc(t: ^testing.T) {
	signatures: [Soldier_Variant][dynamic]i32
	defer for &signature in signatures do delete(signature)
	for variant in Soldier_Variant {
		vertices: i32
		for segment in Segment {
			assembly := Soldier_Segment_Assembly(variant, segment)
			defer Procedural.Assembly_Destroy(&assembly)
			for group in assembly.groups {
				vertices += i32(len(group.mesh.vertices))
				append(&signatures[variant], group.material)
			}
		}
		slice.sort(signatures[variant][:])
		append(&signatures[variant], vertices)
	}
	for first in Soldier_Variant {
		for second in Soldier_Variant {
			if first >= second do continue
			testing.expectf(t, !slice.equal(signatures[first][:], signatures[second][:]), "%v and %v look identical", first, second)
		}
	}
}

// Each segment's mesh, placed by its frame, must cover the middle of its bone, in the rest pose and while walking and aiming.
@(test)
test_segments_sit_on_their_bones_in_every_pose :: proc(t: ^testing.T) {
	poses := [3]Pose{
		Rest_Pose({1, 2, 3}, 0.5),
		Pose_Solve(Pose_Input{position = {1, 2, 3}, heading_radians = 0.5, speed = 3, gait_phase = 0.3}),
		Pose_Solve(Pose_Input{position = {1, 2, 3}, heading_radians = 0.5, aiming = true, aim_direction = linalg.normalize([3]f32{0.4, 0.1, 0.9}), crouch = 0.5}),
	}
	for pose in poses {
		for segment in Segment {
			assembly := Soldier_Segment_Assembly(.Rifleman, segment)
			defer Procedural.Assembly_Destroy(&assembly)
			placed: Procedural.Mesh
			defer Procedural.Mesh_Destroy(&placed)
			for group in assembly.groups do Procedural.Mesh_Append(&placed, group.mesh, Segment_Matrix(pose, segment))
			lowest, highest := Procedural.Mesh_Bounds(placed)
			bone := segment_bones[segment]
			middle := (pose.joints[bone[0]] + pose.joints[bone[1]]) / 2
			for axis in 0 ..< 3 do testing.expectf(t, middle[axis] >= lowest[axis] - 0.02 && middle[axis] <= highest[axis] + 0.02, "%v is off its bone on axis %d", segment, axis)
		}
	}
}

@(test)
test_segment_frames_are_rigid :: proc(t: ^testing.T) {
	pose := Pose_Solve(Pose_Input{position = {1, 0, 2}, heading_radians = 2.1, speed = 4, gait_phase = 0.7, aiming = true, aim_direction = {0.3, 0, 0.95}})
	for segment in Segment {
		frame := Segment_Matrix(pose, segment)
		x, y, z := [3]f32{frame[0, 0], frame[1, 0], frame[2, 0]}, [3]f32{frame[0, 1], frame[1, 1], frame[2, 1]}, [3]f32{frame[0, 2], frame[1, 2], frame[2, 2]}
		testing.expect(t, abs(linalg.length(x) - 1) < 1e-4 && abs(linalg.length(y) - 1) < 1e-4 && abs(linalg.length(z) - 1) < 1e-4)
		testing.expect(t, abs(linalg.dot(x, y)) < 1e-4 && abs(linalg.dot(y, z)) < 1e-4 && abs(linalg.dot(x, z)) < 1e-4)
		testing.expect(t, linalg.dot(linalg.cross(x, y), z) > 0.999) // Right-handed: no mirroring.
	}
}

@(test)
test_the_weapon_sits_in_the_right_hand_and_points_along_the_aim :: proc(t: ^testing.T) {
	aim := linalg.normalize([3]f32{0.4, 0.2, 0.9})
	pose := Pose_Solve(Pose_Input{position = {0, 0, 0}, heading_radians = 0.4, aiming = true, aim_direction = aim})
	for variant in Soldier_Variant {
		kind := Soldier_Weapon(variant)
		assembly := Weapons.Weapon_Build(kind)
		defer Procedural.Assembly_Destroy(&assembly)
		placed: Procedural.Mesh
		defer Procedural.Mesh_Destroy(&placed)
		for group in assembly.groups do Procedural.Mesh_Append(&placed, group.mesh, Weapon_Matrix(pose))
		lowest, highest := Procedural.Mesh_Bounds(placed)
		hand := pose.joints[.Hand_Right]
		for axis in 0 ..< 3 do testing.expectf(t, hand[axis] >= lowest[axis] - 0.08 && hand[axis] <= highest[axis] + 0.08, "%v: weapon is not at the hand on axis %d", variant, axis)
		farthest: f32
		for vertex in placed.vertices do farthest = max(farthest, linalg.dot(vertex.position - hand, aim))
		min_reach: f32 = 0.15 if kind == .Pistol || kind == .Grenade else 0.5
		testing.expectf(t, farthest > min_reach, "%v: the weapon does not point along the aim", variant)
	}
}
