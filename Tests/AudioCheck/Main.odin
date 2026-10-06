package main

import "../../Engine/Audio"
import "../../Game/Sandbox"
import "../Support"
import "core:fmt"
import "core:math"
import "core:os"
import "core:time"

// Every sound the game makes is created exactly as in play, pushed through the real mixer into an offline buffer, and measured: it
// must be audible, finite and inside the limiter; panned sounds must favour the right ear; loops must keep sounding past their own
// length; and the real output device must open and start. Run it with the speakers on to hear a short alarm blip at the end.
main :: proc() {
	checks: Support.Checks
	c := &checks
	bank := Sandbox.sound_create_for_test()
	defer Sandbox.sound_destroy_for_test(&bank)
	sounds := Sandbox.sound_list_for_test(&bank)
	for entry in sounds {
		mixer := Audio.Mixer_Create()
		id := Audio.Mixer_Play(&mixer, entry.sound, 1, 0.8, 1, entry.loop)
		frames := Audio.SAMPLE_RATE / 2
		output := make([]f32, frames * 2)
		defer delete(output)
		Audio.Mixer_Fill(&mixer, output, frames)
		left, right: f32
		finite := true
		for frame in 0 ..< frames {
			l, r := output[frame * 2], output[frame * 2 + 1]
			if math.is_nan(l) || math.is_nan(r) || abs(l) > 1.0001 || abs(r) > 1.0001 do finite = false
			left, right = max(left, abs(l)), max(right, abs(r))
		}
		_ = id
		Support.expect(c, finite)
		Support.expect(c, max(left, right) > 0.02)
		Support.expect(c, right > left) // Panned right.
		if entry.loop {
			tail := make([]f32, frames * 2) // Half a second later a loop still sounds.
			defer delete(tail)
			for _ in 0 ..< 4 do Audio.Mixer_Fill(&mixer, tail, frames)
			peak: f32
			for sample in tail do peak = max(peak, abs(sample))
			Support.expect(c, peak > 0.01)
		}
		fmt.printfln("%-14s peak L %.2f R %.2f", entry.name, left, right)
	}
	device, ok := Audio.Device_Create()
	Support.expect(c, ok)
	if ok {
		Audio.Mixer_Play(&device.mixer, sounds[0].sound, 0.5, 0, 1)
		time.sleep(300 * time.Millisecond)
		Audio.Device_Destroy(device)
	}
	fmt.printfln("%d checks passed, %d failed", c.passed, c.failed)
	if c.failed > 0 do os.exit(1)
}
