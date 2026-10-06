# Architecture

Layers (dependencies point down only): Game > Engine/Render > Engine/World > Engine/Procedural > Engine/GPU > Engine/Platform.
Renderer: deferred G-buffer plus a forward pass for transparents, sky and particles. All bakes and filters are fullscreen fragment passes (no compute on macOS GL 4.1).
Frame: Poll_Input, Update_World, Render_Frame (shadows, G-buffer, lighting, forward, post).
Window and audio: `Source/Loop.odin` owns the loop (focus-loss pause, minimised sleep via WaitEventsTimeout); the cursor is captured by click (`Engine/Platform/Input.odin`). `Engine/Audio` is a 48-voice mixer (equal-power pan, tanh limiter) fed by synthesised sounds; `Game/Sandbox/SoundFeedback.odin` turns game events into cues and ambience.
