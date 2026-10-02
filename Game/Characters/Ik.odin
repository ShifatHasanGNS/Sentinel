package Characters

import "core:math"
import "core:math/linalg"

Two_Bone_Solution :: struct {
	middle:  [3]f32, // Elbow or knee.
	end:     [3]f32, // Hand or foot: the target if it was reachable, else as close as the limb stretches.
	reached: bool,
}

// Places the middle joint of a two-bone limb so its end meets the target. The bones and the target form a triangle with sides
// upper, lower and d = |target - root|; the law of cosines gives the angle at the root:
//   cos(a) = (upper^2 + d^2 - lower^2) / (2 upper d).
// The middle joint is that far along the root-to-target line and off it toward the pole. d is clamped to what the limb can span,
// so an unreachable target yields a straight limb pointing at it instead of a broken one.
Two_Bone_Ik :: proc(root, target, pole: [3]f32, length_upper, length_lower: f32) -> Two_Bone_Solution {
	assert(length_upper > 0 && length_lower > 0, "Two_Bone_Ik: bone lengths must be positive")
	to_target := target - root
	distance := linalg.length(to_target)
	direction := [3]f32{0, -1, 0} if distance < 1e-6 else to_target / distance
	reach_maximum := length_upper + length_lower
	reach_minimum := abs(length_upper - length_lower) + 1e-3
	clamped := clamp(distance, reach_minimum, reach_maximum)
	cosine := clamp((length_upper * length_upper + clamped * clamped - length_lower * length_lower) / (2 * length_upper * clamped), -1, 1)
	sine := math.sqrt(1 - cosine * cosine)
	pole_offset := pole - root
	sideways := pole_offset - direction * linalg.dot(pole_offset, direction)
	if linalg.length(sideways) < 1e-6 do sideways = linalg.cross(direction, [3]f32{1, 0, 0} if abs(direction.x) < 0.9 else [3]f32{0, 1, 0})
	sideways = linalg.normalize(sideways)
	return Two_Bone_Solution{
		middle = root + direction * (length_upper * cosine) + sideways * (length_upper * sine),
		end = root + direction * clamped,
		reached = distance >= reach_minimum && distance <= reach_maximum,
	}
}
