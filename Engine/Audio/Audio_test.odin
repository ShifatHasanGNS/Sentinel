package Audio

import "core:math"
import "core:testing"

// Seams: the Synth_* generators (what waveform comes out) and Mixer_Fill (what the speakers would get).

all_sounds :: proc() -> [dynamic]Sound {
	sounds := make([dynamic]Sound)
	append(&sounds, Synth_Gunshot(0.05, 90, 6000, 1, 1), Synth_Gunshot(0.02, 140, 1200, 0.5, 2), Synth_Explosion(3), Synth_Footstep(0.3, 4), Synth_Click(5))
	append(&sounds, Synth_Impact(false, 6), Synth_Impact(true, 7), Synth_Engine(30, 8), Synth_Rotor(9), Synth_Alarm(), Synth_Chime(660), Synth_Creak(10))
	append(&sounds, Synth_Thud(70, 0.4, 30), Synth_Beep(1500, 0.08), Synth_Wind(31), Synth_Crickets(32), Synth_Bird(2600))
	return sounds
}

destroy_all :: proc(sounds: ^[dynamic]Sound) {
	for &sound in sounds do Sound_Destroy(&sound)
	delete(sounds^)
}

@(test)
test_every_sound_is_finite_audible_and_not_clipped_hard :: proc(t: ^testing.T) {
	sounds := all_sounds()
	defer destroy_all(&sounds)
	for sound, index in sounds {
		peak, energy: f32
		for sample in sound.samples {
			testing.expectf(t, !math.is_nan(sample) && !math.is_inf(sample), "sound %d has a non-finite sample", index)
			peak = max(peak, abs(sample))
			energy += sample * sample
		}
		testing.expectf(t, peak > 0.05, "sound %d is nearly silent (peak %f)", index, peak)
		testing.expectf(t, peak < 3.0, "sound %d is far too loud (peak %f)", index, peak)
		testing.expectf(t, energy / f32(len(sound.samples)) > 1e-5, "sound %d carries no energy", index)
	}
}

// A shot's energy sits at the front and decays: the last fifth of the buffer is much quieter than the first fifth.
@(test)
test_gunshots_and_explosions_die_away :: proc(t: ^testing.T) {
	for sound in ([]Sound{Synth_Gunshot(0.05, 90, 6000, 1, 1), Synth_Explosion(3)}) {
		sound := sound
		defer Sound_Destroy(&sound)
		fifth := len(sound.samples) / 5
		early, late: f32
		for index in 0 ..< fifth {
			early += sound.samples[index] * sound.samples[index]
			late += sound.samples[len(sound.samples) - 1 - index] * sound.samples[len(sound.samples) - 1 - index]
		}
		testing.expect(t, late < early * 0.02)
	}
}

@(test)
test_sounds_are_deterministic_per_seed_and_differ_between_seeds :: proc(t: ^testing.T) {
	a, b, c := Synth_Footstep(0.3, 4), Synth_Footstep(0.3, 4), Synth_Footstep(0.3, 5)
	defer Sound_Destroy(&a)
	defer Sound_Destroy(&b)
	defer Sound_Destroy(&c)
	same, different := true, false
	for index in 0 ..< len(a.samples) {
		if a.samples[index] != b.samples[index] do same = false
		if a.samples[index] != c.samples[index] do different = true
	}
	testing.expect(t, same && different)
}

// A loop must join smoothly: the step from the last sample to the first is no larger than a typical step inside the sound.
@(test)
test_loopable_sounds_join_without_a_click :: proc(t: ^testing.T) {
	for sound in ([]Sound{Synth_Engine(30, 8), Synth_Rotor(9), Synth_Alarm(), Synth_Wind(31), Synth_Crickets(32)}) {
		sound := sound
		defer Sound_Destroy(&sound)
		testing.expect(t, sound.loopable)
		typical: f32
		for index in 1 ..< len(sound.samples) do typical += abs(sound.samples[index] - sound.samples[index - 1])
		typical /= f32(len(sound.samples) - 1)
		seam := abs(sound.samples[0] - sound.samples[len(sound.samples) - 1])
		testing.expectf(t, seam < typical * 4 + 0.005, "loop seam %f vs typical step %f (len %d)", seam, typical, len(sound.samples))
	}
}

make_ramp :: proc(count: int) -> Sound {
	samples := make([]f32, count)
	for index in 0 ..< count do samples[index] = 1
	return Sound{samples = samples, loopable = true}
}

@(test)
test_the_mixer_sums_voices_pans_them_and_finishes_them :: proc(t: ^testing.T) {
	mixer := Mixer_Create()
	mixer.master = 1
	ones := make_ramp(1000)
	defer Sound_Destroy(&ones)
	Mixer_Play(&mixer, &ones, 0.1, -1) // Hard left.
	output: [400]f32
	Mixer_Fill(&mixer, output[:], 200)
	testing.expect(t, abs(output[100]) > 0.05 && abs(output[101]) < 1e-4) // Left only.
	Mixer_Play(&mixer, &ones, 0.1, 1) // Hard right.
	Mixer_Fill(&mixer, output[:], 200)
	testing.expect(t, output[100] > 0.05 && output[101] > 0.05)
	testing.expect_value(t, Mixer_Active_Count(&mixer), 2)
	for _ in 0 ..< 10 do Mixer_Fill(&mixer, output[:], 200) // 2000 frames: well past the 1000-sample sounds.
	testing.expect_value(t, Mixer_Active_Count(&mixer), 0)
	Mixer_Fill(&mixer, output[:], 200)
	testing.expect_value(t, output[10], 0)
}

@(test)
test_equal_power_pan_keeps_total_power_constant :: proc(t: ^testing.T) {
	for pan in ([5]f32{-1, -0.5, 0, 0.5, 1}) {
		left, right := pan_gains(1, pan)
		testing.expect(t, abs(left * left + right * right - 1) < 1e-4)
	}
	left, right := pan_gains(1, 0)
	testing.expect(t, abs(left - right) < 1e-5)
}

@(test)
test_loops_wrap_stop_on_request_and_pitch_changes_the_rate :: proc(t: ^testing.T) {
	mixer := Mixer_Create()
	mixer.master = 1
	ones := make_ramp(1000)
	defer Sound_Destroy(&ones)
	id := Mixer_Play(&mixer, &ones, 0.2, 0, 1, true)
	output: [400]f32
	for _ in 0 ..< 20 do Mixer_Fill(&mixer, output[:], 200) // 4000 frames through a 1000-sample loop.
	testing.expect_value(t, Mixer_Active_Count(&mixer), 1)
	Mixer_Stop(&mixer, id)
	testing.expect_value(t, Mixer_Active_Count(&mixer), 0)
	short := make_ramp(1000)
	defer Sound_Destroy(&short)
	Mixer_Play(&mixer, &short, 0.2, 0, 2) // An octave up: finished in half the time.
	for _ in 0 ..< 3 do Mixer_Fill(&mixer, output[:], 200) // 600 frames x 2 = 1200 samples of source consumed.
	testing.expect_value(t, Mixer_Active_Count(&mixer), 0)
}

@(test)
test_the_limiter_keeps_output_inside_one_however_many_voices_play :: proc(t: ^testing.T) {
	mixer := Mixer_Create()
	loud := make_ramp(2000)
	defer Sound_Destroy(&loud)
	for _ in 0 ..< VOICES_MAX do Mixer_Play(&mixer, &loud, 1, 0)
	output: [400]f32
	Mixer_Fill(&mixer, output[:], 200)
	for sample in output do testing.expect(t, abs(sample) <= 1)
}
