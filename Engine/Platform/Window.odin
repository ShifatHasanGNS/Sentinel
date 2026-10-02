package Platform

import "core:fmt"
import gl "vendor:OpenGL"
import "vendor:glfw"

GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 1

Window :: struct {
	handle:               glfw.WindowHandle,
	framebuffer_width:    i32,
	framebuffer_height:   i32,
}

// retina = false keeps one framebuffer pixel per window pixel on high-DPI displays (for benchmarks at a known resolution).
Window_Create :: proc(title: cstring, width, height: i32, visible: bool, retina := true) -> (window: Window, ok: bool) {
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

	window.handle = glfw.CreateWindow(width, height, title, nil, nil)
	if window.handle == nil {
		fmt.eprintln("glfw.CreateWindow failed")
		glfw.Terminate()
		return {}, false
	}
	glfw.MakeContextCurrent(window.handle)
	glfw.SwapInterval(1)
	gl.load_up_to(GL_VERSION_MAJOR, GL_VERSION_MINOR, glfw.gl_set_proc_address)
	window.framebuffer_width, window.framebuffer_height = glfw.GetFramebufferSize(window.handle)
	return window, true
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
