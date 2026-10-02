package Characters

import "core:math"
import la "core:math/linalg"

// A humanoid as joint positions. Bones are rigid: every pose keeps each bone's length, because limbs are placed by IK and the
// trunk by fixed offsets.
Joint :: enum {
	Pelvis,
	Chest,
	Neck,
	Head,
	Shoulder_Left,
	Shoulder_Right,
	Elbow_Left,
	Elbow_Right,
	Hand_Left,
	Hand_Right,
	Hip_Left,
	Hip_Right,
	Knee_Left,
	Knee_Right,
	Ankle_Left,
	Ankle_Right,
}

TORSO_LENGTH_METERS :: 0.5
NECK_LENGTH_METERS :: 0.08
HEAD_OFFSET_METERS :: 0.14
HEAD_RADIUS_METERS :: 0.12
HIP_HALF_WIDTH_METERS :: 0.09
SHOULDER_HALF_WIDTH_METERS :: 0.19
SHOULDER_DROP_METERS :: 0.05
SHOULDER_BONE_METERS :: 0.19647 // sqrt(half width^2 + drop^2)
UPPER_ARM_METERS :: 0.30
FOREARM_METERS :: 0.27
THIGH_METERS :: 0.45
SHIN_METERS :: 0.45
ANKLE_HEIGHT :: 0.08
STAND_PELVIS_HEIGHT_METERS :: 0.96
LEG_WORKING_REACH_METERS :: 0.87 // Slightly under the 0.9 m the leg can span, so the knee is never locked straight.
CROUCH_DROP_METERS :: 0.3
FOOT_LIFT_METERS :: 0.1
ARM_SWING_FRACTION :: 0.6
LEAN_PER_SPEED_METERS :: 0.015

Bone :: struct {
	from:   Joint,
	to:     Joint,
	length: f32,
}

BONES :: [?]Bone{
	{.Pelvis, .Chest, TORSO_LENGTH_METERS},
	{.Chest, .Neck, NECK_LENGTH_METERS},
	{.Neck, .Head, HEAD_OFFSET_METERS},
	{.Pelvis, .Hip_Left, HIP_HALF_WIDTH_METERS},
	{.Pelvis, .Hip_Right, HIP_HALF_WIDTH_METERS},
	{.Chest, .Shoulder_Left, SHOULDER_BONE_METERS},
	{.Chest, .Shoulder_Right, SHOULDER_BONE_METERS},
	{.Shoulder_Left, .Elbow_Left, UPPER_ARM_METERS},
	{.Shoulder_Right, .Elbow_Right, UPPER_ARM_METERS},
	{.Elbow_Left, .Hand_Left, FOREARM_METERS},
	{.Elbow_Right, .Hand_Right, FOREARM_METERS},
	{.Hip_Left, .Knee_Left, THIGH_METERS},
	{.Hip_Right, .Knee_Right, THIGH_METERS},
	{.Knee_Left, .Ankle_Left, SHIN_METERS},
	{.Knee_Right, .Ankle_Right, SHIN_METERS},
}

Pose :: struct {
	joints:        [Joint]([3]f32),
	heading_radians: f32,
	aim_direction: [3]f32,
}

// What drives a pose. position is the ground point under the pelvis (its y is the ground height); heading turns the body about +Y
// (zero faces +Z). gait_phase is in turns. lean displaces the chest sideways (a hit); crouch runs 0 (standing) to 1 (low).
Pose_Input :: struct {
	position:        [3]f32,
	heading_radians: f32,
	speed:           f32,
	gait_phase:      f32,
	aiming:          bool,
	aim_direction:   [3]f32,
	crouch:          f32,
	lean:            [3]f32,
}

Rest_Pose :: proc(position: [3]f32, heading_radians: f32) -> Pose {
	return Pose_Solve(Pose_Input{position = position, heading_radians = heading_radians})
}

Pose_Solve :: proc(input: Pose_Input) -> (pose: Pose) {
	forward := [3]f32{math.sin(input.heading_radians), 0, math.cos(input.heading_radians)}
	left := [3]f32{math.cos(input.heading_radians), 0, -math.sin(input.heading_radians)}
	pose.heading_radians = input.heading_radians
	stride := Gait_Stride_Meters(input.speed) if input.speed > 0 else 0
	pelvis_height := min(STAND_PELVIS_HEIGHT_METERS, ANKLE_HEIGHT + math.sqrt(LEG_WORKING_REACH_METERS * LEG_WORKING_REACH_METERS - stride * stride / 4)) - input.crouch * CROUCH_DROP_METERS
	pose.joints[.Pelvis] = input.position + {0, pelvis_height, 0}
	solve_trunk(&pose, input, forward, left)
	solve_legs(&pose, input, forward, left, stride)
	solve_arms(&pose, input, forward, left)
	return pose
}

// The trunk leans as a rigid rod: a hit or running pushes its top, but its length does not change.
@(private = "file")
solve_trunk :: proc(pose: ^Pose, input: Pose_Input, forward, left: [3]f32) {
	lean := input.lean + forward * (LEAN_PER_SPEED_METERS * input.speed)
	torso_up := la.normalize([3]f32{0, TORSO_LENGTH_METERS, 0} + lean)
	pose.joints[.Chest] = pose.joints[.Pelvis] + torso_up * TORSO_LENGTH_METERS
	pose.joints[.Neck] = pose.joints[.Chest] + torso_up * NECK_LENGTH_METERS
	pose.joints[.Head] = pose.joints[.Neck] + torso_up * HEAD_OFFSET_METERS
	shoulder_axis := la.normalize(left - torso_up * la.dot(left, torso_up))
	pose.joints[.Shoulder_Left] = pose.joints[.Chest] + shoulder_axis * SHOULDER_HALF_WIDTH_METERS - torso_up * SHOULDER_DROP_METERS
	pose.joints[.Shoulder_Right] = pose.joints[.Chest] - shoulder_axis * SHOULDER_HALF_WIDTH_METERS - torso_up * SHOULDER_DROP_METERS
	pose.joints[.Hip_Left] = pose.joints[.Pelvis] + left * HIP_HALF_WIDTH_METERS
	pose.joints[.Hip_Right] = pose.joints[.Pelvis] - left * HIP_HALF_WIDTH_METERS
}

// Each foot follows the gait path (the right half a cycle behind the left); the knee is found by IK, bending forward.
@(private = "file")
solve_legs :: proc(pose: ^Pose, input: Pose_Input, forward, left: [3]f32, stride: f32) {
	for side in ([2]f32{1, -1}) {
		foot_phase := input.gait_phase + (0 if side > 0 else 0.5)
		offset, lift := Gait_Foot(foot_phase, stride, FOOT_LIFT_METERS)
		if input.speed <= 0 do offset, lift = 0, 0
		hip_joint, knee_joint, ankle_joint := Joint.Hip_Left, Joint.Knee_Left, Joint.Ankle_Left
		if side < 0 do hip_joint, knee_joint, ankle_joint = .Hip_Right, .Knee_Right, .Ankle_Right
		ankle_target := input.position + forward * offset + left * (side * HIP_HALF_WIDTH_METERS) + [3]f32{0, ANKLE_HEIGHT + lift, 0}
		hip := pose.joints[hip_joint]
		solution := Two_Bone_Ik(hip, ankle_target, hip + forward, THIGH_METERS, SHIN_METERS)
		pose.joints[knee_joint], pose.joints[ankle_joint] = solution.middle, solution.end
	}
}

// Walking: each arm swings opposite its own-side leg. Aiming: both hands take the rifle, the right near the trigger and the left
// out on the forend, along the aim direction.
@(private = "file")
solve_arms :: proc(pose: ^Pose, input: Pose_Input, forward, left: [3]f32) {
	aim := forward
	if input.aiming && la.length(input.aim_direction) > 1e-4 do aim = la.normalize(input.aim_direction)
	pose.aim_direction = aim
	torso_up := la.normalize(pose.joints[.Chest] - pose.joints[.Pelvis])
	chest := pose.joints[.Chest]
	for side in ([2]f32{1, -1}) {
		shoulder_joint, elbow_joint, hand_joint := Joint.Shoulder_Left, Joint.Elbow_Left, Joint.Hand_Left
		if side < 0 do shoulder_joint, elbow_joint, hand_joint = .Shoulder_Right, .Elbow_Right, .Hand_Right
		shoulder := pose.joints[shoulder_joint]
		target: [3]f32
		switch {
		case input.aiming && side < 0: target = chest + aim * 0.22 - torso_up * 0.22
		case input.aiming: target = chest + aim * 0.46 - torso_up * 0.2
		case: target = shoulder - torso_up * 0.5 + forward * swing_offset(input, side)
		}
		pole := shoulder + left * (side * 0.3) - torso_up * 0.3 - forward * 0.3
		solution := Two_Bone_Ik(shoulder, target, pole, UPPER_ARM_METERS, FOREARM_METERS)
		pose.joints[elbow_joint], pose.joints[hand_joint] = solution.middle, solution.end
	}
}

// The arm goes back as its own-side foot goes forward.
@(private = "file")
swing_offset :: proc(input: Pose_Input, side: f32) -> f32 {
	if input.speed <= 0 do return 0
	foot_phase := input.gait_phase + (0 if side > 0 else 0.5)
	foot_forward, _ := Gait_Foot(foot_phase, Gait_Stride_Meters(input.speed), FOOT_LIFT_METERS)
	return -ARM_SWING_FRACTION * foot_forward
}
