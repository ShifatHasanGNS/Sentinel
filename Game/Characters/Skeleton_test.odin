package Characters

import "core:math"
import "core:math/linalg"
import "core:testing"

sample_inputs :: proc() -> (inputs: [dynamic]Pose_Input) {
	for speed in ([4]f32{0, 1.2, 3, 6}) {
		for step in 0 ..< 12 {
			base := Pose_Input{position = {3, 10, -4}, heading_radians = 0.7, speed = speed, gait_phase = f32(step) / 12}
			append(&inputs, base)
			aiming := base
			aiming.aiming = true
			aiming.aim_direction = linalg.normalize([3]f32{0.3, 0.1, 0.9})
			append(&inputs, aiming)
			hurt := base
			hurt.lean = {0.12, -0.05, -0.1}
			hurt.crouch = 0.6
			append(&inputs, hurt)
		}
	}
	return
}

@(test)
test_every_bone_keeps_its_length_in_every_pose :: proc(t: ^testing.T) {
	inputs := sample_inputs()
	defer delete(inputs)
	for input in inputs {
		pose := Pose_Solve(input)
		for bone in BONES {
			length := linalg.length(pose.joints[bone.to] - pose.joints[bone.from])
			testing.expectf(t, abs(length - bone.length) < 2e-3, "%v->%v is %.4f m, should be %.4f", bone.from, bone.to, length, bone.length)
		}
	}
}

@(test)
test_the_rest_pose_is_a_human_standing_on_the_ground :: proc(t: ^testing.T) {
	pose := Rest_Pose({0, 0, 0}, 0)
	testing.expect(t, abs(pose.joints[.Ankle_Left].y - ANKLE_HEIGHT) < 0.02 && abs(pose.joints[.Ankle_Right].y - ANKLE_HEIGHT) < 0.02)
	top_of_head := pose.joints[.Head].y + HEAD_RADIUS_METERS
	testing.expect(t, top_of_head > 1.65 && top_of_head < 1.95)
	shoulders := linalg.length(pose.joints[.Shoulder_Left] - pose.joints[.Shoulder_Right])
	testing.expect(t, shoulders > 0.3 && shoulders < 0.5)
	testing.expect(t, pose.joints[.Hand_Left].y < pose.joints[.Elbow_Left].y && pose.joints[.Elbow_Left].y < pose.joints[.Shoulder_Left].y) // Arms hang.
}

@(test)
test_feet_never_sink_below_the_ground_and_swing_feet_rise :: proc(t: ^testing.T) {
	inputs := sample_inputs()
	defer delete(inputs)
	highest_ankle: f32
	for input in inputs {
		pose := Pose_Solve(input)
		for ankle in ([2]Joint{.Ankle_Left, .Ankle_Right}) {
			height := pose.joints[ankle].y - input.position.y
			testing.expect(t, height >= ANKLE_HEIGHT - 2e-3)
			highest_ankle = max(highest_ankle, height)
		}
	}
	testing.expect(t, highest_ankle > ANKLE_HEIGHT + 0.05) // Some foot lifts during a swing.
}

// Move the whole body along its heading at constant speed; a foot in stance must stay put in the world while the body passes over it.
@(test)
test_a_stance_foot_stays_fixed_in_the_world_while_the_body_walks :: proc(t: ^testing.T) {
	heading: f32 = 0.7
	forward := [3]f32{math.sin(heading), 0, math.cos(heading)}
	for speed in ([2]f32{1.4, 4}) {
		cycle := Gait_Cycle_Seconds(speed)
		first_ankle: [3]f32
		for step in 0 ..= 40 {
			phase := 0.03 + (GAIT_DUTY_FACTOR - 0.06) * f32(step) / 40
			position := [3]f32{5, 0, 5} + forward * speed * phase * cycle
			pose := Pose_Solve(Pose_Input{position = position, heading_radians = heading, speed = speed, gait_phase = phase})
			ankle := pose.joints[.Ankle_Left]
			if step == 0 do first_ankle = ankle
			testing.expect(t, abs(ankle.x - first_ankle.x) < 5e-3 && abs(ankle.z - first_ankle.z) < 5e-3)
		}
	}
}

@(test)
test_the_two_feet_alternate :: proc(t: ^testing.T) {
	heading: f32 = 0
	for phase in ([2]f32{0.25, 0.8}) {
		pose := Pose_Solve(Pose_Input{heading_radians = heading, speed = 2, gait_phase = phase})
		left_forward, right_forward := pose.joints[.Ankle_Left].z, pose.joints[.Ankle_Right].z
		testing.expect(t, left_forward * right_forward < 0) // One is ahead of the hips, the other behind.
	}
}

@(test)
test_aiming_brings_both_hands_forward_along_the_aim_direction :: proc(t: ^testing.T) {
	aim := linalg.normalize([3]f32{0.4, 0.2, 0.9})
	pose := Pose_Solve(Pose_Input{heading_radians = 0.3, aiming = true, aim_direction = aim})
	chest := pose.joints[.Chest]
	right, left := pose.joints[.Hand_Right], pose.joints[.Hand_Left]
	testing.expect(t, linalg.dot(right - chest, aim) > 0.15 && linalg.dot(left - chest, aim) > 0.3)
	separation := linalg.length(left - right)
	testing.expect(t, separation > 0.2 && separation < 0.5)
	testing.expect(t, linalg.dot(linalg.normalize(left - right), aim) > 0.9) // The rifle axis runs along the aim.
	testing.expect(t, linalg.length(pose.aim_direction - aim) < 1e-5)
}

@(test)
test_crouching_lowers_the_pelvis_but_keeps_the_feet_down :: proc(t: ^testing.T) {
	standing := Pose_Solve(Pose_Input{})
	crouched := Pose_Solve(Pose_Input{crouch = 1})
	testing.expect(t, standing.joints[.Pelvis].y - crouched.joints[.Pelvis].y > 0.2)
	testing.expect(t, abs(crouched.joints[.Ankle_Left].y - ANKLE_HEIGHT) < 2e-3)
}

@(test)
test_a_hit_pushes_the_chest_but_not_the_pelvis :: proc(t: ^testing.T) {
	still := Pose_Solve(Pose_Input{})
	hit := Pose_Solve(Pose_Input{lean = {0.15, 0, 0}})
	testing.expect_value(t, still.joints[.Pelvis], hit.joints[.Pelvis])
	testing.expect(t, hit.joints[.Chest].x - still.joints[.Chest].x > 0.05)
	testing.expect(t, abs(linalg.length(hit.joints[.Chest] - hit.joints[.Pelvis]) - TORSO_LENGTH_METERS) < 1e-4)
}

@(test)
test_poses_are_deterministic :: proc(t: ^testing.T) {
	input := Pose_Input{position = {1, 2, 3}, heading_radians = 1, speed = 3, gait_phase = 0.37, aiming = true, aim_direction = {0, 0, 1}}
	testing.expect_value(t, Pose_Solve(input), Pose_Solve(input))
}
