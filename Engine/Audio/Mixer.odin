package Audio

import "core:math"
import "core:sync"

SAMPLE_RATE :: 44100
VOICES_MAX :: 48

// A mono waveform, generated at startup (see Synth.odin). Loopable sounds are built so the last sample flows into the first.
Sound :: struct {
	samples:  []f32,
	loopable: bool,
}

Voice :: struct {
	sound:    ^Sound,
	position: f32, // In samples, fractional because of pitch.
	pitch:    f32, // Playback speed: 2 is an octave up.
	left:     f32, // Gains after volume and pan.
	right:    f32,
	looping:  bool,
	id:       u32,
	active:   bool,
}

// Mixes up to VOICES_MAX sounds into stereo. The game thread starts, adjusts and stops voices; the audio device's thread calls
// Mixer_Fill. A mutex guards the voice table: both sides hold it only for a few microseconds.
Mixer :: struct {
	voices:  [VOICES_MAX]Voice,
	lock:    sync.Mutex,
	next_id: u32,
	master:  f32,
}

Mixer_Create :: proc() -> Mixer {
	return Mixer{master = 0.8, next_id = 1}
}

// Equal-power pan: pan in [-1, 1] (left to right) sends cos and sin of a quarter turn to the two ears, so the total power stays
// constant across the sweep and a sound does not dip in the middle.
pan_gains :: proc(volume, pan: f32) -> (left, right: f32) {
	angle := (clamp(pan, -1, 1) + 1) * math.PI / 4
	return volume * math.cos(angle), volume * math.sin(angle)
}

// Starts a sound and returns an id for later adjustment. When every voice is busy the quietest one is replaced.
Mixer_Play :: proc(mixer: ^Mixer, sound: ^Sound, volume, pan: f32, pitch: f32 = 1, looping := false) -> u32 {
	assert(len(sound.samples) > 1, "Mixer_Play: empty sound")
	sync.mutex_lock(&mixer.lock)
	defer sync.mutex_unlock(&mixer.lock)
	slot := 0
	quietest := math.INF_F32
	for voice, index in mixer.voices {
		if !voice.active {
			slot = index
			break
		}
		if loudness := voice.left + voice.right; loudness < quietest && !voice.looping {
			quietest, slot = loudness, index
		}
	}
	left, right := pan_gains(volume, pan)
	id := mixer.next_id
	mixer.next_id += 1
	mixer.voices[slot] = Voice{sound = sound, pitch = pitch, left = left, right = right, looping = looping && sound.loopable, id = id, active = true}
	return id
}

// Changes a playing voice's volume, pan and pitch (an engine's note follows its speed). Does nothing for a voice that has finished.
Mixer_Set :: proc(mixer: ^Mixer, id: u32, volume, pan, pitch: f32) {
	sync.mutex_lock(&mixer.lock)
	defer sync.mutex_unlock(&mixer.lock)
	for &voice in mixer.voices {
		if voice.active && voice.id == id {
			voice.left, voice.right = pan_gains(volume, pan)
			voice.pitch = pitch
			return
		}
	}
}

Mixer_Stop :: proc(mixer: ^Mixer, id: u32) {
	sync.mutex_lock(&mixer.lock)
	defer sync.mutex_unlock(&mixer.lock)
	for &voice in mixer.voices do if voice.active && voice.id == id do voice.active = false
}

Mixer_Active_Count :: proc(mixer: ^Mixer) -> (count: int) {
	sync.mutex_lock(&mixer.lock)
	defer sync.mutex_unlock(&mixer.lock)
	for voice in mixer.voices do if voice.active do count += 1
	return
}

// Adds every voice into `output` (interleaved left, right; `frames` frames), resampling with linear interpolation, then applies the
// master gain and a soft limiter (tanh) so a pile-up of loud sounds saturates smoothly instead of clipping.
Mixer_Fill :: proc(mixer: ^Mixer, output: []f32, frames: int) {
	assert(len(output) >= frames * 2, "Mixer_Fill: output too small")
	for index in 0 ..< frames * 2 do output[index] = 0
	sync.mutex_lock(&mixer.lock)
	for &voice in mixer.voices {
		if !voice.active do continue
		samples := voice.sound.samples
		count := f32(len(samples))
		for frame in 0 ..< frames {
			if voice.position >= count - 1 {
				if voice.looping do voice.position -= count - 1
				else {
					voice.active = false
					break
				}
			}
			base := int(voice.position)
			fraction := voice.position - f32(base)
			sample := samples[base] * (1 - fraction) + samples[base + 1] * fraction
			output[frame * 2] += sample * voice.left
			output[frame * 2 + 1] += sample * voice.right
			voice.position += voice.pitch
		}
	}
	master := mixer.master
	sync.mutex_unlock(&mixer.lock)
	for index in 0 ..< frames * 2 do output[index] = math.tanh(output[index] * master)
}
