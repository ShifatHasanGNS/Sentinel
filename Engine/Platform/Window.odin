package Platform

import "core:fmt"
import gl "vendor:OpenGL"
import "vendor:glfw"

GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 1

Window :: struct {
	windowed_position:    [2]i32, // Where the window was before going fullscreen.
	windowed_size:        [2]i32,
	handle:               glfw.WindowHandle,
	framebuffer_width:    i32,
	framebuffer_height:   i32,
}

// retina = false keeps one framebuffer pixel per window pixel on high-DPI displays (for benchmarks at a known resolution).
Window_Create :: proc(title: cstring, width, height: i32, visible: bool, retina := true, fullscreen := false) -> (window: Window, ok: bool) {
	if !glfw.Init() {
		fmt.eprintln("glfw.Init failed")
		return {}, false
	}
	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, GL_VERSION_MAJOR)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, GL_VERSION_MINOR)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
	glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, true)
	glfw.WindowHint(glfw.VISIBLE, b32(visible))
	glfw.WindowHint(glfw.COCOA_RETINA_FRAMEBUFFER, b32(retina))
	glfw.WindowHint(glfw.RESIZABLE, true)
	glfw.WindowHint(glfw.DECORATED, true)
	glfw.WindowHint(glfw.FOCUS_ON_SHOW, true)

	// Fullscreen takes the primary monitor at its current video mode: no title bar to grab, so the window cannot be dragged,
	// minimised or resized with the mouse while it is captured.
	monitor: glfw.MonitorHandle
	width, height := width, height
	if fullscreen {
		monitor = glfw.GetPrimaryMonitor()
		if mode := glfw.GetVideoMode(monitor); mode != nil do width, height = mode.width, mode.height
	}
	window.handle = glfw.CreateWindow(width, height, title, monitor, nil)
	if window.handle == nil {
		fmt.eprintln("glfw.CreateWindow failed")
		glfw.Terminate()
		return {}, false
	}
	if monitor == nil {
		glfw.SetWindowSizeLimits(window.handle, WINDOW_MIN_WIDTH, WINDOW_MIN_HEIGHT, glfw.DONT_CARE, glfw.DONT_CARE)
		center_on_monitor(window.handle, width, height)
	}
	glfw.MakeContextCurrent(window.handle)
	glfw.SwapInterval(1)
	gl.load_up_to(GL_VERSION_MAJOR, GL_VERSION_MINOR, glfw.gl_set_proc_address)
	window.framebuffer_width, window.framebuffer_height = glfw.GetFramebufferSize(window.handle)
	return window, true
}

// A window smaller than this cannot show the HUD, so the user cannot shrink it past it.
WINDOW_MIN_WIDTH :: 640
WINDOW_MIN_HEIGHT :: 360

// Centres a new window in the primary monitor's work area (the part not covered by the menu bar and dock).
@(private = "file")
center_on_monitor :: proc(handle: glfw.WindowHandle, width, height: i32) {
	x, y, area_width, area_height := glfw.GetMonitorWorkarea(glfw.GetPrimaryMonitor())
	if area_width <= 0 || area_height <= 0 do return
	glfw.SetWindowPos(handle, x + max((area_width - width) / 2, 0), y + max((area_height - height) / 2, 0))
}

Window_Show :: proc(window: ^Window) {
	glfw.ShowWindow(window.handle)
	glfw.FocusWindow(window.handle)
}

Window_Is_Focused :: proc(window: Window) -> bool {
	return glfw.GetWindowAttrib(window.handle, glfw.FOCUSED) != 0
}

// True while the window is minimised or has no drawable area; there is nothing to render then.
Window_Is_Hidden :: proc(window: Window) -> bool {
	return window.framebuffer_width <= 0 || window.framebuffer_height <= 0 || glfw.GetWindowAttrib(window.handle, glfw.ICONIFIED) != 0
}

// Sleeps until the window event (restore, resize, close) arrives, so a minimised game uses no CPU or GPU.
Window_Wait_Events :: proc(window: ^Window) {
	glfw.WaitEventsTimeout(0.1)
	window.framebuffer_width, window.framebuffer_height = glfw.GetFramebufferSize(window.handle)
}

Window_Destroy :: proc(window: ^Window) {
	glfw.DestroyWindow(window.handle)
	glfw.Terminate()
}

Window_Should_Close :: proc(window: ^Window) -> bool {
	return bool(glfw.WindowShouldClose(window.handle))
}

Window_Present :: proc(window: ^Window) {
	glfw.SwapBuffers(window.handle)
	glfw.PollEvents()
	window.framebuffer_width, window.framebuffer_height = glfw.GetFramebufferSize(window.handle)
}

Window_Request_Close :: proc(window: ^Window) {
	glfw.SetWindowShouldClose(window.handle, true)
}

Window_Set_Vsync :: proc(enabled: bool) {
	glfw.SwapInterval(1 if enabled else 0)
}

Window_Is_Fullscreen :: proc(window: Window) -> bool {
	return glfw.GetWindowMonitor(window.handle) != nil
}

// Switches between a normal resizable window and fullscreen on the monitor it is on, remembering the window's place and size.
Window_Toggle_Fullscreen :: proc(window: ^Window) {
	if Window_Is_Fullscreen(window^) {
		glfw.SetWindowMonitor(window.handle, nil, window.windowed_position.x, window.windowed_position.y, window.windowed_size.x, window.windowed_size.y, glfw.DONT_CARE)
		return
	}
	window.windowed_position.x, window.windowed_position.y = glfw.GetWindowPos(window.handle)
	window.windowed_size.x, window.windowed_size.y = glfw.GetWindowSize(window.handle)
	monitor := glfw.GetPrimaryMonitor()
	mode := glfw.GetVideoMode(monitor)
	glfw.SetWindowMonitor(window.handle, monitor, 0, 0, mode.width, mode.height, mode.refresh_rate)
}
