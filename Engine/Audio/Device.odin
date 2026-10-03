package Audio

import ma "vendor:miniaudio"
import "base:runtime"
import "core:fmt"

// The audio output: a miniaudio playback device that pulls stereo float frames from the mixer on its own thread.
Device :: struct {
	device:  ma.device,
	mixer:   Mixer,
	started: bool,
}

// Heap-allocated so the callback's pointer to the mixer stays valid.
Device_Create :: proc() -> (device: ^Device, ok: bool) {
	device = new(Device)
	device.mixer = Mixer_Create()
	config := ma.device_config_init(.playback)
	config.playback.format = .f32
	config.playback.channels = 2
	config.sampleRate = SAMPLE_RATE
	config.dataCallback = proc "c" (raw_device: ^ma.device, output, input: rawptr, frame_count: u32) {
		context = runtime.default_context()
		mixer := (^Mixer)(raw_device.pUserData)
		Mixer_Fill(mixer, ([^]f32)(output)[:frame_count * 2], int(frame_count))
	}
	config.pUserData = &device.mixer
	if ma.device_init(nil, &config, &device.device) != .SUCCESS {
		fmt.eprintln("audio: no output device; the game will be silent")
		free(device)
		return nil, false
	}
	if ma.device_start(&device.device) != .SUCCESS {
		fmt.eprintln("audio: the output device would not start; the game will be silent")
		ma.device_uninit(&device.device)
		free(device)
		return nil, false
	}
	device.started = true
	return device, true
}

Device_Destroy :: proc(device: ^Device) {
	if device == nil do return
	ma.device_uninit(&device.device)
	free(device)
}
