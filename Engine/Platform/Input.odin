package Platform

import "vendor:glfw"

Input :: struct {
	window:         glfw.WindowHandle,
	mouse_position: [2]f64,
	mouse_delta:    [2]f32,
	has_mouse:      bool,
}

Input_Create :: proc(window: ^Window) -> Input {
	return Input{window = window.handle}
}

// Call once per frame after polling events.
Input_Update :: proc(input: ^Input) {
	x, y := glfw.GetCursorPos(input.window)
	if input.has_mouse {
		input.mouse_delta = {f32(x - input.mouse_position.x), f32(y - input.mouse_position.y)}
	}
	input.mouse_position = {x, y}
	input.has_mouse = true
}

Key :: enum {
	W,
	A,
	S,
	D,
	Q,
	E,
	Space,
	Left_Shift,
	Left_Control,
	Escape,
	Period,
	Comma,
}

@(private = "file")
glfw_keys := [Key]i32{
	.W = glfw.KEY_W,
	.A = glfw.KEY_A,
	.S = glfw.KEY_S,
	.D = glfw.KEY_D,
	.Q = glfw.KEY_Q,
	.E = glfw.KEY_E,
	.Space = glfw.KEY_SPACE,
	.Left_Shift = glfw.KEY_LEFT_SHIFT,
	.Left_Control = glfw.KEY_LEFT_CONTROL,
	.Escape = glfw.KEY_ESCAPE,
	.Period = glfw.KEY_PERIOD,
	.Comma = glfw.KEY_COMMA,
}

Input_Key_Down :: proc(input: ^Input, key: Key) -> bool {
	return glfw.GetKey(input.window, glfw_keys[key]) == glfw.PRESS
}

Input_Capture_Mouse :: proc(input: ^Input, captured: bool) {
	mode: i32 = glfw.CURSOR_DISABLED if captured else glfw.CURSOR_NORMAL
	glfw.SetInputMode(input.window, glfw.CURSOR, mode)
	input.has_mouse = false
}
