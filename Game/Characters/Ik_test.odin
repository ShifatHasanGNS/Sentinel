package Characters

import "core:math"
import "core:math/linalg"
import "core:testing"

UPPER: f32 : 0.45
LOWER: f32 : 0.4

@(test)
test_reachable_targets_are_hit_with_bone_lengths_preserved :: proc(t: ^testing.T) {
	root: [3]f32 = {1, 2, -1}
	for x in -4 ..= 4 do for y in -4 ..= 4 do for z in -4 ..= 4 {
		offset := [3]f32{f32(x), f32(y), f32(z)} * 0.1
		distance := linalg.length(offset)
		if distance < 0.06 || distance > 0.82 do continue
		target := root + offset
		solution := Two_Bone_Ik(root, target, root + {0, 0, 1}, UPPER, LOWER)
		testing.expect(t, solution.reached)
		testing.expect(t, linalg.length(solution.end - target) < 1e-3)
		testing.expect(t, abs(linalg.length(solution.middle - root) - UPPER) < 1e-4)
		testing.expect(t, abs(linalg.length(solution.end - solution.middle) - LOWER) < 1e-4)
	}
}

@(test)
test_unreachable_targets_give_a_fully_extended_limb_toward_the_target :: proc(t: ^testing.T) {
	root: [3]f32 = {0, 1, 0}
	target := [3]f32{0, 1, 5}
	solution := Two_Bone_Ik(root, target, {0, 1, 1}, UPPER, LOWER)
	testing.expect(t, !solution.reached)
	testing.expect(t, linalg.length(solution.end - [3]f32{0, 1, UPPER + LOWER}) < 1e-3)
	testing.expect(t, linalg.length(solution.middle - [3]f32{0, 1, UPPER}) < 1e-3) // Collinear: the joint lies on the straight line.
}

@(test)
test_degenerate_inputs_stay_finite :: proc(t: ^testing.T) {
	root: [3]f32 = {0, 0, 0}
	cases := [?][3][3]f32{
		{{0, 0, 0}, {0, 0, 1}, {0, 0, 0}}, // Target on the root: closer than the limb can fold.
		{{0, -0.8, 0}, {0, -1, 0}, {0, 0, 0}}, // Pole collinear with the limb direction.
		{{0, 0.02, 0}, {1, 0, 0}, {0, 0, 0}}, // Almost on the root.
	}
	for case_ in cases {
		solution := Two_Bone_Ik(root, case_[0], case_[1], UPPER, LOWER)
		for value in solution.middle do testing.expect(t, !math.is_nan(value) && !math.is_inf(value))
		for value in solution.end do testing.expect(t, !math.is_nan(value) && !math.is_inf(value))
		testing.expect(t, abs(linalg.length(solution.middle - root) - UPPER) < 1e-3)
		testing.expect(t, abs(linalg.length(solution.end - solution.middle) - LOWER) < 1e-3)
	}
}

// A knee bends toward the pole: with the foot below the hip and the pole in front, the knee sits in front of the straight line.
@(test)
test_the_middle_joint_bends_toward_the_pole :: proc(t: ^testing.T) {
	root: [3]f32 = {0, 1, 0}
	target := [3]f32{0, 0.25, 0.1}
	forward := Two_Bone_Ik(root, target, root + {0, 0, 1}, UPPER, LOWER)
	backward := Two_Bone_Ik(root, target, root + {0, 0, -1}, UPPER, LOWER)
	line_point :: proc(root, target, middle: [3]f32) -> [3]f32 {
		direction := linalg.normalize(target - root)
		return root + direction * linalg.dot(middle - root, direction)
	}
	testing.expect(t, forward.middle.z > line_point(root, target, forward.middle).z + 0.05)
	testing.expect(t, backward.middle.z < line_point(root, target, backward.middle).z - 0.05)
	testing.expect(t, abs(forward.middle.z - line_point(root, target, forward.middle).z + (backward.middle.z - line_point(root, target, backward.middle).z)) < 1e-4) // Mirror images.
}

@(test)
test_ik_is_deterministic :: proc(t: ^testing.T) {
	first := Two_Bone_Ik({0, 1, 0}, {0.2, 0.3, 0.4}, {0, 1, 1}, UPPER, LOWER)
	second := Two_Bone_Ik({0, 1, 0}, {0.2, 0.3, 0.4}, {0, 1, 1}, UPPER, LOWER)
	testing.expect_value(t, first, second)
}
