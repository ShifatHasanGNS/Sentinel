package Mission

import "core:testing"

// Seam: Save_Format / Save_Parse and Profile_Record_Completion.

sample_profile :: proc() -> Profile {
	profile := Profile{best_seconds = 312.5, completions = 3}
	profile.checkpoint = Checkpoint{valid = true, position = {12.5, 10, -48.25}, yaw = 1.5, health = 63.5, elapsed_seconds = 101.25, radar_destroyed = true}
	profile.checkpoint.objectives_done[.Enter_Compound] = true
	profile.checkpoint.objectives_done[.Destroy_Radar] = true
	profile.checkpoint.ammo = {30, 12, 5, 1, 1, 10, 0, 0}
	profile.checkpoint.reserve = {120, 60, 15, 3, 2, 50, 0, 0}
	return profile
}

@(test)
test_a_profile_survives_a_round_trip_through_text :: proc(t: ^testing.T) {
	original := sample_profile()
	restored := Save_Parse(Save_Format(original))
	testing.expect_value(t, restored, original)
}

@(test)
test_a_profile_without_a_checkpoint_round_trips_too :: proc(t: ^testing.T) {
	original := Profile{best_seconds = 99, completions = 1}
	restored := Save_Parse(Save_Format(original))
	testing.expect_value(t, restored, original)
	testing.expect(t, !restored.checkpoint.valid)
}

// Damaged input must never crash or poison the profile: garbage lines, truncated lines, negative or absurd numbers, wrong keys.
@(test)
test_damaged_files_are_survived_and_bad_values_ignored :: proc(t: ^testing.T) {
	text := "best -5\ncompletions abc\ncheckpoint 1\nposition 1 2\ndone 99\ndone -1\nhealth -20\nweapon 99 1 1\nweapon 0 -4 3\nwhat is this\n\n   \nyaw 2.5\nweapon 1 7 9\n"
	profile := Save_Parse(text)
	testing.expect_value(t, profile.best_seconds, 0)
	testing.expect_value(t, profile.completions, 0)
	testing.expect(t, profile.checkpoint.valid)
	testing.expect_value(t, profile.checkpoint.position, [3]f32{})
	testing.expect_value(t, profile.checkpoint.objectives_done, [Objective]bool{})
	testing.expect_value(t, profile.checkpoint.health, 0)
	testing.expect_value(t, profile.checkpoint.ammo[0], 0)
	testing.expect_value(t, profile.checkpoint.yaw, 2.5) // Good lines among bad ones still count.
	testing.expect_value(t, profile.checkpoint.ammo[1], 7)
	testing.expect_value(t, profile.checkpoint.reserve[1], 9)
	empty := Save_Parse("")
	testing.expect_value(t, empty, Profile{})
}

@(test)
test_completions_keep_the_best_time_and_clear_the_checkpoint :: proc(t: ^testing.T) {
	profile := sample_profile()
	testing.expect(t, !Profile_Record_Completion(&profile, 400)) // Slower than 312.5.
	testing.expect_value(t, profile.best_seconds, 312.5)
	testing.expect_value(t, profile.completions, 4)
	testing.expect(t, !profile.checkpoint.valid) // A finished mission has nothing to resume.
	testing.expect(t, Profile_Record_Completion(&profile, 250))
	testing.expect_value(t, profile.best_seconds, 250)
	fresh := Profile{}
	testing.expect(t, Profile_Record_Completion(&fresh, 500)) // The first completion is always a best.
}
