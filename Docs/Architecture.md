# Architecture

Layers (dependencies point down only): Game > Engine/Render > Engine/World > Engine/Procedural > Engine/GPU > Engine/Platform.
Renderer: deferred G-buffer plus a forward pass for transparents, sky and particles. All bakes and filters are fullscreen fragment passes (no compute on macOS GL 4.1).
Frame: Poll_Input, Update_World, Render_Frame (shadows, G-buffer, lighting, forward, post).
To be expanded at M1 and M4.
