package Audio

import "core:math"

// Every sound is computed from noise and oscillators at startup: nothing is loaded from disk. The recipes follow how the real sounds
// arise: a gunshot is a sharp noise burst (the muzzle blast) over a low thump (the pressure wave) that dies away exponentially, and
// an engine is a stack of harmonics of its firing frequency.

@(private = "file")
Noise :: struct {
	state: u32,
}

// xorshift32: a fast white-noise source in [-1, 1].
@(private = "file")
next_noise :: proc(noise: ^Noise) -> f32 {
	noise.state ~= noise.state << 13
	noise.state ~= noise.state >> 17
	noise.state ~= noise.state << 5
	return f32(noise.state) / 2147483648.0 - 1
}

@(private = "file")
make_buffer :: proc(seconds: f32) -> []f32 {
	return make([]f32, int(seconds * SAMPLE_RATE))
}

LOOP_FADE_SAMPLES :: 441 // 10 ms

// A loop is generated 10 ms longer than its length. closing it blends the start toward that extra tail, so the buffer's last sample
// flows into its first exactly as if the signal had simply continued (no click, whatever the noise did).
@(private = "file")
make_loop_buffer :: proc(seconds: f32) -> []f32 {
	return make([]f32, int(seconds * SAMPLE_RATE) + LOOP_FADE_SAMPLES)
}

@(private = "file")
close_loop :: proc(extended: []f32) -> []f32 {
	length := len(extended) - LOOP_FADE_SAMPLES
	for index in 0 ..< LOOP_FADE_SAMPLES {
		mix := f32(index) / f32(LOOP_FADE_SAMPLES)
		extended[index] = extended[index] * mix + extended[length + index] * (1 - mix)
	}
	trimmed := make([]f32, length)
	copy(trimmed, extended[:length])
	delete(extended)
	return trimmed
}

// One-pole low-pass filter: y += a (x - y), with a = 1 - exp(-2 pi f / fs). Smaller `cutoff` hz is duller.
@(private = "file")
smoothing :: proc(cutoff_hz: f32) -> f32 {
	return 1 - math.exp(-2 * math.PI * cutoff_hz / SAMPLE_RATE)
}

// Muzzle blast: filtered noise with a fast exponential decay, a low sine thump that falls in pitch, and a short bright crack at the
// very start. `body` is the decay time in seconds, `dullness` a low-pass cutoff (silenced shots are dull and short).
Synth_Gunshot :: proc(body_seconds, thump_hz, cutoff_hz, loudness: f32, seed: u32) -> Sound {
	buffer := make_buffer(body_seconds * 5)
	noise := Noise{seed}
	filtered: f32
	a := smoothing(cutoff_hz)
	for index in 0 ..< len(buffer) {
		t := f32(index) / SAMPLE_RATE
		envelope := math.exp(-t / body_seconds)
		filtered += a * (next_noise(&noise) - filtered)
		thump := math.sin(2 * math.PI * thump_hz * (1 - 0.5 * t / (body_seconds * 5)) * t) * math.exp(-t / (body_seconds * 0.7))
		crack := next_noise(&noise) * math.exp(-t / 0.004)
		buffer[index] = loudness * (0.75 * filtered * envelope + 0.5 * thump + 0.35 * crack)
	}
	return Sound{samples = buffer}
}

// Explosion: a long low rumble of strongly filtered noise swelling for a moment, a deep sine, and a debris crackle tail.
Synth_Explosion :: proc(seed: u32) -> Sound {
	buffer := make_buffer(2.6)
	noise := Noise{seed}
	filtered, filtered_more: f32
	for index in 0 ..< len(buffer) {
		t := f32(index) / SAMPLE_RATE
		filtered += smoothing(900) * (next_noise(&noise) - filtered)
		filtered_more += smoothing(160) * (next_noise(&noise) - filtered_more)
		swell := min(t / 0.03, 1) * math.exp(-t / 0.7)
		boom := math.sin(2 * math.PI * (55 - 20 * min(t, 1)) * t) * math.exp(-t / 0.6)
		crackle := next_noise(&noise) * (next_noise(&noise) > 0.92 ? 1 : 0) * math.exp(-t / 0.9) * 0.4
		buffer[index] = 0.9 * (0.7 * filtered * swell + 1.4 * filtered_more * swell + 0.8 * boom) + crackle
	}
	return Sound{samples = buffer}
}

// A footfall: a short low thud with a touch of grit. `hardness` brightens it (gravel, metal).
Synth_Footstep :: proc(hardness: f32, seed: u32) -> Sound {
	buffer := make_buffer(0.16)
	noise := Noise{seed}
	filtered: f32
	for index in 0 ..< len(buffer) {
		t := f32(index) / SAMPLE_RATE
		filtered += smoothing(300 + 1500 * hardness) * (next_noise(&noise) - filtered)
		buffer[index] = (filtered * 1.3 + math.sin(2 * math.PI * 70 * t) * 0.4) * math.exp(-t / 0.035) * 0.8
	}
	return Sound{samples = buffer}
}

// A mechanical click (reload, bolt, door latch): two very short decaying bursts a few milliseconds apart.
Synth_Click :: proc(seed: u32) -> Sound {
	buffer := make_buffer(0.12)
	noise := Noise{seed}
	for index in 0 ..< len(buffer) {
		t := f32(index) / SAMPLE_RATE
		second := t - 0.045
		buffer[index] = next_noise(&noise) * (math.exp(-t / 0.006) + (second > 0 ? 0.7 * math.exp(-second / 0.008) : 0)) * 0.6
	}
	return Sound{samples = buffer}
}

// A bullet hitting something: a dull tick, and for the ricochet a falling whine on top.
Synth_Impact :: proc(ricochet: bool, seed: u32) -> Sound {
	buffer := make_buffer(0.35)
	noise := Noise{seed}
	filtered: f32
	for index in 0 ..< len(buffer) {
		t := f32(index) / SAMPLE_RATE
		filtered += smoothing(2500) * (next_noise(&noise) - filtered)
		whine := ricochet ? math.sin(2 * math.PI * (2600 - 3500 * t) * t) * math.exp(-t / 0.12) * 0.4 : 0
		buffer[index] = filtered * math.exp(-t / 0.02) * 1.2 + whine
	}
	return Sound{samples = buffer}
}

// A loop of `seconds` whose every component completes a whole number of cycles inside it, so the end joins the start with no click.
// Frequencies are rounded to multiples of 1/seconds hz for that reason.
@(private = "file")
whole_cycles :: proc(frequency_hz, seconds: f32) -> f32 {
	return math.round(frequency_hz * seconds) / seconds
}

// A diesel-like engine note: the firing frequency and its first six harmonics (falling amplitudes), a slight amplitude flutter at
// the firing rate and a little noise for rattle. Pitch it up with the vehicle's speed through Mixer_Set.
Synth_Engine :: proc(firing_hz: f32, seed: u32) -> Sound {
	seconds: f32 = 1.0
	buffer := make_loop_buffer(seconds)
	noise := Noise{seed}
	base := whole_cycles(firing_hz, seconds)
	filtered: f32
	for index in 0 ..< len(buffer) {
		t := f32(index) / SAMPLE_RATE
		tone: f32
		for harmonic in 1 ..= 6 do tone += math.sin(2 * math.PI * base * f32(harmonic) * t) / f32(harmonic)
		filtered += smoothing(500) * (next_noise(&noise) - filtered)
		flutter := 0.8 + 0.2 * math.sin(2 * math.PI * whole_cycles(base * 0.5, seconds) * t)
		buffer[index] = (tone * 0.35 * flutter + filtered * 0.25) * 0.6
	}
	return Sound{samples = close_loop(buffer), loopable = true}
}

// Helicopter rotor: a thump at the blade-pass rate (low noise pulses) over a turbine whine, looped on a whole number of beats.
Synth_Rotor :: proc(seed: u32) -> Sound {
	seconds: f32 = 1.0
	buffer := make_loop_buffer(seconds)
	noise := Noise{seed}
	beat_hz: f32 = 12
	filtered: f32
	for index in 0 ..< len(buffer) {
		t := f32(index) / SAMPLE_RATE
		phase := math.mod(t * beat_hz, 1)
		pulse := math.exp(-phase / 0.12) * (1 - math.exp(-phase / 0.01))
		filtered += smoothing(260) * (next_noise(&noise) - filtered)
		whine := math.sin(2 * math.PI * 1200 * t) * 0.04 + math.sin(2 * math.PI * 2400 * t) * 0.02
		buffer[index] = filtered * pulse * 2.4 + math.sin(2 * math.PI * 48 * t) * pulse * 0.4 + whine
	}
	return Sound{samples = close_loop(buffer), loopable = true}
}

// An alarm siren: a tone sliding between two pitches in a triangle wave, looped on whole cycles of the slide.
Synth_Alarm :: proc() -> Sound {
	seconds: f32 = 1.2
	buffer := make_loop_buffer(seconds)
	phase: f32
	for index in 0 ..< len(buffer) {
		t := f32(index) / SAMPLE_RATE
		slide := math.abs(math.mod(t / seconds * 2, 2) - 1) // 0..1..0 over the loop
		frequency := 650 + 450 * slide
		phase += 2 * math.PI * frequency / SAMPLE_RATE
		buffer[index] = (math.sin(phase) + 0.3 * math.sin(2 * phase)) * 0.35
	}
	return Sound{samples = close_loop(buffer), loopable = true}
}

// A short two-note chime for pickups and objective completion: sine at `low_hz` then a fifth above, each with a bell-like decay.
Synth_Chime :: proc(low_hz: f32) -> Sound {
	buffer := make_buffer(0.5)
	for index in 0 ..< len(buffer) {
		t := f32(index) / SAMPLE_RATE
		second := t - 0.11
		first_note := math.sin(2 * math.PI * low_hz * t) * math.exp(-t / 0.12)
		second_note := second > 0 ? math.sin(2 * math.PI * low_hz * 1.5 * second) * math.exp(-second / 0.18) : 0
		buffer[index] = (first_note + second_note) * 0.5
	}
	return Sound{samples = buffer}
}

// Door creak: a sawtooth whose pitch wanders, band-passed by resonance (a squeaking hinge), 0.5 s with a swell envelope.
Synth_Creak :: proc(seed: u32) -> Sound {
	buffer := make_buffer(0.55)
	noise := Noise{seed}
	phase: f32
	wander: f32
	for index in 0 ..< len(buffer) {
		t := f32(index) / SAMPLE_RATE
		wander += 0.002 * next_noise(&noise)
		frequency := 220 + 90 * math.sin(2 * math.PI * 2.3 * t) + 400 * wander
		phase += frequency / SAMPLE_RATE
		saw := (phase - math.floor(phase)) * 2 - 1
		envelope := math.sin(math.PI * t / 0.55)
		buffer[index] = saw * envelope * envelope * 0.25
	}
	return Sound{samples = buffer}
}

Sound_Destroy :: proc(sound: ^Sound) {
	delete(sound.samples)
	sound^ = {}
}
