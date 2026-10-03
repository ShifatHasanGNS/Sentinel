package Sandbox

import "core:math"
import "core:testing"

// Seam: spatialize(base_volume, source, listener, yaw) -> (volume, pan).

@(test)
test_sounds_fall_off_with_distance_and_never_get_louder_than_their_base :: proc(t: ^testing.T) {
	near, _ := spatialize(1, {0, 0, -1}, {0, 0, 0}, 0)
	middle, _ := spatialize(1, {0, 0, -30}, {0, 0, 0}, 0)
	far, _ := spatialize(1, {0, 0, -300}, {0, 0, 0}, 0)
	testing.expect(t, near > middle && middle > far && far > 0)
	testing.expect(t, near <= 1)
	at_ear, pan := spatialize(1, {0, 0, 0}, {0, 0, 0}, 0)
	testing.expect(t, at_ear == 1 && pan == 0)
	testing.expect(t, middle < 0.2) // A shot 30 m away is well down from a shot beside you.
}

// Facing -Z (yaw 0) the listener's right is +X: a source at +X pans right, at -X left, ahead or behind it is centred; turning the
// listener a quarter turn to the left (yaw +90 degrees faces -X) puts the old -Z source on the right.
@(test)
test_pan_follows_which_side_the_sound_is_on_and_turns_with_the_listener :: proc(t: ^testing.T) {
	_, right := spatialize(1, {10, 0, 0}, {0, 0, 0}, 0)
	_, left := spatialize(1, {-10, 0, 0}, {0, 0, 0}, 0)
	_, ahead := spatialize(1, {0, 0, -10}, {0, 0, 0}, 0)
	_, behind := spatialize(1, {0, 0, 10}, {0, 0, 0}, 0)
	testing.expect(t, right > 0.99 && left < -0.99)
	testing.expect(t, abs(ahead) < 1e-4 && abs(behind) < 1e-4)
	_, turned := spatialize(1, {0, 0, -10}, {0, 0, 0}, math.PI / 2)
	testing.expect(t, turned > 0.99)
}

// Seam: bearing_relative_degrees and heading_degrees. Facing -Z (north, yaw 0): east (+X) is 90 degrees right, west 90 left, south is
// behind (180); turning left (positive yaw) by 90 degrees faces west, where north is then 90 degrees to the right.
@(test)
test_bearings_are_measured_clockwise_from_the_way_the_player_faces :: proc(t: ^testing.T) {
	origin := [3]f32{}
	testing.expect(t, abs(bearing_relative_degrees(origin, 0, {0, 0, -10})) < 1e-3)
	testing.expect(t, abs(bearing_relative_degrees(origin, 0, {10, 0, 0}) - 90) < 1e-3)
	testing.expect(t, abs(bearing_relative_degrees(origin, 0, {-10, 0, 0}) + 90) < 1e-3)
	testing.expect(t, abs(abs(bearing_relative_degrees(origin, 0, {0, 0, 10})) - 180) < 1e-3)
	testing.expect(t, abs(bearing_relative_degrees(origin, math.PI / 2, {0, 0, -10}) - 90) < 1e-3)
	testing.expect(t, abs(heading_degrees(0)) < 1e-3)
	testing.expect(t, abs(heading_degrees(math.PI / 2) - 270) < 1e-3) // Facing west is 270 degrees clockwise from north.
	testing.expect(t, abs(heading_degrees(-math.PI / 2) - 90) < 1e-3)
}
