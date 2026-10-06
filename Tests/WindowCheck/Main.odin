package main

import "../../Engine/GPU"
import "../../Engine/Platform"
import "../../Game/Showroom"
import "../Support"
import "core:fmt"
import "core:os"
import gl "vendor:OpenGL"
import "vendor:glfw"

// What a player can do to the window with the mouse: drag it larger or smaller, maximise, minimise and restore, go fullscreen and back.
// Each step runs real frames of the showroom, so the renderer's targets are resized through every size; the check passes when the
// window ends where it was told to, no GL error appears and the minimum size is respected.
SIZES := [?][2]i32{{1280, 720}, {640, 360}, {801, 457}, {1920, 1080}, {700, 1000}, {1280, 720}, {2400, 900}, {640, 360}}

main :: proc() {
	checks: Support.Checks
	c := &checks
	window, ok := Platform.Window_Create("Window check", 1280, 720, true)
	Support.expect(c, ok)
	if !ok do os.exit(1)
	defer Platform.Window_Destroy(&window)
	defer GPU.Sampler_Cache_Destroy()
	showroom, showroom_ok := Showroom.Showroom_Create(window.framebuffer_width, window.framebuffer_height)
	Support.expect(c, showroom_ok)
	if !showroom_ok do os.exit(1)
	defer Showroom.Showroom_Destroy(&showroom)
	clock: Platform.Clock

	frames :: proc(c: ^Support.Checks, showroom: ^Showroom.Showroom, window: ^Platform.Window, clock: ^Platform.Clock, count: int) {
		for _ in 0 ..< count {
			Platform.Clock_Tick(clock)
			Showroom.Showroom_Update(showroom, clock^)
			if !Platform.Window_Is_Hidden(window^) do Showroom.Showroom_Render(showroom, window^)
			Platform.Window_Present(window)
			Support.expect(c, gl.GetError() == gl.NO_ERROR)
		}
	}

	frames(c, &showroom, &window, &clock, 5)
	for size in SIZES {
		glfw.SetWindowSize(window.handle, size.x, size.y)
		frames(c, &showroom, &window, &clock, 6)
		width, height := glfw.GetWindowSize(window.handle)
		Support.expect(c, width >= Platform.WINDOW_MIN_WIDTH && height >= Platform.WINDOW_MIN_HEIGHT)
		Support.expect(c, window.framebuffer_width >= width && window.framebuffer_height >= height) // Retina: at least one pixel per point.
		fmt.printfln("size %v -> window %dx%d, framebuffer %dx%d", size, width, height, window.framebuffer_width, window.framebuffer_height)
	}
	glfw.SetWindowSize(window.handle, 100, 50) // Cocoa enforces the size limits only on mouse drags; the renderer must survive a tiny window anyway.
	frames(c, &showroom, &window, &clock, 4)

	glfw.MaximizeWindow(window.handle)
	frames(c, &showroom, &window, &clock, 10)
	glfw.RestoreWindow(window.handle)
	frames(c, &showroom, &window, &clock, 10)

	glfw.IconifyWindow(window.handle)
	for _ in 0 ..< 10 do Platform.Window_Wait_Events(&window)
	frames(c, &showroom, &window, &clock, 3) // Minimised: frames are skipped, not crashed.
	glfw.RestoreWindow(window.handle)
	for _ in 0 ..< 40 do if Platform.Window_Is_Hidden(window) do Platform.Window_Wait_Events(&window) // macOS animates the restore.
	frames(c, &showroom, &window, &clock, 10)
	Support.expect(c, !Platform.Window_Is_Hidden(window))

	Platform.Window_Toggle_Fullscreen(&window)
	frames(c, &showroom, &window, &clock, 15)
	Support.expect(c, Platform.Window_Is_Fullscreen(window))
	Platform.Window_Toggle_Fullscreen(&window)
	frames(c, &showroom, &window, &clock, 15)
	Support.expect(c, !Platform.Window_Is_Fullscreen(window))

	fmt.printfln("%d checks passed, %d failed", c.passed, c.failed)
	if c.failed > 0 do os.exit(1)
}
