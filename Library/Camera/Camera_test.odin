// Camera_test.odin — sanity checks on core:math/linalg, run with
// `odin test Library/Camera`.
//
// These are confidence checks on how SENTINEL USES core:math/linalg (see
// the conventions block at the top of Camera.odin) — not a from-scratch
// math implementation to verify from first principles. If any of these
// ever fails after an Odin toolchain upgrade, the conventions comment in
// Camera.odin is the thing that's now wrong and needs re-deriving, not
// patching around here.
package Camera

import "core:math"
import la "core:math/linalg"
import "core:testing"

EPSILON :: 1e-4

@(test)
test_identity_is_neutral :: proc(t: ^testing.T) {
	identity := la.MATRIX4F32_IDENTITY
	v := la.Vector4f32{1, 2, 3, 1}
	expect_vector4_near(t, la.mul(identity, v), v)
}

@(test)
test_multiplication_is_associative :: proc(t: ^testing.T) {
	a := la.matrix4_translate(la.Vector3f32{1, 0, 0})
	b := la.matrix4_rotate(math.to_radians(f32(45)), la.Vector3f32{0, 1, 0})
	c := la.matrix4_scale(la.Vector3f32{2, 2, 2})
	v := la.Vector4f32{1, 2, 3, 1}

	left_first := la.mul(la.mul(a, b), c)
	right_first := la.mul(a, la.mul(b, c))

	expect_vector4_near(t, la.mul(left_first, v), la.mul(right_first, v))
}

@(test)
test_inverse_round_trip :: proc(t: ^testing.T) {
	m := la.mul(
		la.matrix4_translate(la.Vector3f32{3, -2, 5}),
		la.matrix4_rotate(math.to_radians(f32(37)), la.Vector3f32{0, 1, 0}),
	)
	round_trip := la.mul(la.matrix4_inverse(m), m)
	expect_vector4_near(t, la.mul(round_trip, la.Vector4f32{1, 2, 3, 1}), la.Vector4f32{1, 2, 3, 1})
}

// Confirms the right-hand-rule rotation direction recorded in Camera.odin's
// conventions block: +X rotated +90 degrees about +Y must land on -Z.
@(test)
test_known_rotation_direction :: proc(t: ^testing.T) {
	rot := la.matrix4_rotate(math.to_radians(f32(90)), la.Vector3f32{0, 1, 0})
	rotated := la.mul(rot, la.Vector4f32{1, 0, 0, 0})
	expect_vector4_near(t, rotated, la.Vector4f32{0, 0, -1, 0})
}

@(test)
test_normalize_produces_unit_length :: proc(t: ^testing.T) {
	length := la.length(la.normalize(la.Vector3f32{3, 4, 0}))
	testing.expectf(t, math.abs(length - 1) <= EPSILON, "expected unit length, got %v", length)
}

@(private = "file")
expect_vector4_near :: proc(t: ^testing.T, got, want: la.Vector4f32, loc := #caller_location) {
	for i in 0 ..< 4 {
		diff := math.abs(got[i] - want[i])
		testing.expectf(t, diff <= EPSILON, "vector mismatch at component %d: got %v, want %v (diff %v)", i, got, want, diff, loc = loc)
	}
}
