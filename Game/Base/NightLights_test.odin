package Base

import la "core:math/linalg"
import "core:testing"

// Seam: Layout_Night_Lights(layout, ground, darkness) -> lights.

@(test)
test_no_lights_in_daylight :: proc(t: ^testing.T) {
	layout := Layout_Create(7, PLATEAU_RADIUS_METERS)
	defer Layout_Destroy(&layout)
	testing.expect_value(t, len(Layout_Night_Lights(layout, 10, 0)), 0)
}

// One light per lamp of every placement, each inside the compound or at its edge, scaled by darkness.
@(test)
test_night_lights_match_the_layout :: proc(t: ^testing.T) {
	layout := Layout_Create(7, PLATEAU_RADIUS_METERS)
	defer Layout_Destroy(&layout)
	expected := 0
	for placement in layout.placements do expected += len(lamps_for(placement.kind))
	testing.expect(t, expected > 0)
	full, half := Layout_Night_Lights(layout, 10, 1), Layout_Night_Lights(layout, 10, 0.5)
	testing.expect_value(t, len(full), expected)
	for light, index in full {
		testing.expect(t, light.position.y > 10)
		testing.expect(t, la.length([2]f32{light.position.x, light.position.z}) < PERIMETER_RADIUS_METERS + 10)
		testing.expect(t, abs(half[index].intensity * 2 - light.intensity) < 1e-3)
		if light.kind == .Spot do testing.expect(t, abs(la.length(light.direction) - 1) < 1e-4)
	}
}

// A floodlight faces outward at yaw 0 (+Z), and the lamp turns with the placement: at yaw 90 it sits at +X of the pole and aims +X.
@(test)
test_lamp_follows_placement_yaw :: proc(t: ^testing.T) {
	layout: Layout
	defer Layout_Destroy(&layout)
	append(&layout.placements, Placement{kind = .Floodlight, x = 0, z = 0, yaw_degrees = 0}, Placement{kind = .Floodlight, x = 0, z = 0, yaw_degrees = 90})
	lights := Layout_Night_Lights(layout, 0, 1)
	testing.expect_value(t, len(lights), 2)
	testing.expect(t, lights[0].direction.z > 0 && abs(lights[0].position.x - 0.6) < 1e-4)
	testing.expect(t, lights[1].direction.x > 0 && abs(lights[1].position.z + 0.6) < 1e-4)
}
