package Mission

import "core:testing"

// Seam: Mission_Update(mission, observation, dt) and Mission_Current_Objective.

started :: proc() -> Mission {
	mission := Mission_Create()
	Mission_Start(&mission)
	return mission
}

@(test)
test_nothing_happens_before_the_briefing_is_dismissed :: proc(t: ^testing.T) {
	mission := Mission_Create()
	Mission_Update(&mission, Observation{inside_compound = true, radar_destroyed = true}, 1)
	testing.expect_value(t, mission.done, [Objective]bool{})
	testing.expect_value(t, mission.elapsed_seconds, 0)
	Mission_Start(&mission)
	Mission_Update(&mission, Observation{inside_compound = true}, 1)
	testing.expect(t, mission.done[.Enter_Compound])
}

@(test)
test_the_middle_objectives_can_come_in_any_order_and_each_is_reported_once :: proc(t: ^testing.T) {
	mission := started()
	Mission_Update(&mission, Observation{inside_compound = true}, 0.1)
	testing.expect_value(t, mission.just_completed, bit_set[Objective]{.Enter_Compound})
	Mission_Update(&mission, Observation{inside_compound = true}, 0.1)
	testing.expect_value(t, mission.just_completed, bit_set[Objective]{}) // Already reported.
	Mission_Update(&mission, Observation{radar_destroyed = true}, 0.1)
	testing.expect_value(t, mission.just_completed, bit_set[Objective]{.Destroy_Radar})
	Mission_Update(&mission, Observation{hostage_in_reach = true, interact_pressed = true}, 0.1)
	testing.expect(t, mission.done[.Rescue_Hostage])
	objective, any := Mission_Current_Objective(mission)
	testing.expect(t, any)
	testing.expect_value(t, objective, Objective.Hack_Cameras) // The first one still open, in the listed order.
}

@(test)
test_the_hostage_needs_a_press_in_reach_not_a_press_far_away_or_reach_alone :: proc(t: ^testing.T) {
	mission := started()
	Mission_Update(&mission, Observation{interact_pressed = true}, 0.1)
	Mission_Update(&mission, Observation{hostage_in_reach = true}, 0.1)
	testing.expect(t, !mission.done[.Rescue_Hostage])
	Mission_Update(&mission, Observation{hostage_in_reach = true, interact_pressed = true}, 0.1)
	testing.expect(t, mission.done[.Rescue_Hostage])
}

@(test)
test_a_hack_needs_an_unbroken_hold_and_drains_when_released :: proc(t: ^testing.T) {
	mission := started()
	holding := Observation{terminal_in_reach = true, interact_held = true}
	for _ in 0 ..< 60 do Mission_Update(&mission, holding, 1.0 / 60) // One second.
	testing.expect(t, abs(mission.hack_seconds - 1) < 0.02 && !mission.done[.Hack_Cameras])
	for _ in 0 ..< 30 do Mission_Update(&mission, Observation{terminal_in_reach = true}, 1.0 / 60) // Let go for half a second.
	testing.expect(t, abs(mission.hack_seconds - 0) < 0.02) // Drains at twice the rate: 1 - 0.5 * 2.
	for _ in 0 ..< 60 do Mission_Update(&mission, Observation{interact_held = true}, 1.0 / 60) // Holding E away from the computer does nothing.
	testing.expect_value(t, mission.hack_seconds, 0)
	for _ in 0 ..< int(HACK_SECONDS * 60) + 2 do Mission_Update(&mission, holding, 1.0 / 60)
	testing.expect(t, mission.done[.Hack_Cameras])
	testing.expect_value(t, mission.hack_seconds, HACK_SECONDS)
	Mission_Update(&mission, Observation{}, 5)
	testing.expect(t, mission.done[.Hack_Cameras]) // Stays done.
}

@(test)
test_extraction_opens_only_after_hack_radar_and_hostage_and_ends_the_mission :: proc(t: ^testing.T) {
	mission := started()
	Mission_Update(&mission, Observation{inside_compound = true, radar_destroyed = true, hostage_in_reach = true, interact_pressed = true, at_extraction = true}, 0.1)
	testing.expect(t, !mission.done[.Reach_Extraction]) // The hack is missing.
	for _ in 0 ..< int(HACK_SECONDS * 60) + 2 do Mission_Update(&mission, Observation{terminal_in_reach = true, interact_held = true}, 1.0 / 60)
	testing.expect(t, mission.done[.Hack_Cameras])
	testing.expect_value(t, mission.status, Mission_Status.Active)
	Mission_Update(&mission, Observation{at_extraction = true}, 0.1)
	testing.expect(t, mission.done[.Reach_Extraction])
	testing.expect_value(t, mission.status, Mission_Status.Complete)
	_, any := Mission_Current_Objective(mission)
	testing.expect(t, !any)
	elapsed := mission.elapsed_seconds
	Mission_Update(&mission, Observation{}, 10)
	testing.expect_value(t, mission.elapsed_seconds, elapsed) // The clock stops.
}
