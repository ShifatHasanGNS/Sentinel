package Platform

import "vendor:glfw"

Input :: struct {
	window:         glfw.WindowHandle,
	mouse_position: [2]f64,
	mouse_delta:    [2]f32,
	has_mouse:      bool,
	captured:       bool,
	focused:        bool, // False while another window is in front.
	click_edge:     bool, // The left button went down this frame.
	left_was_down:  bool,
	swallow_left:   bool, // The click that captured the mouse must not also fire.
}

Input_Create :: proc(window: ^Window) -> Input {
	return Input{window = window.handle, focused = true}
}

// Call once per frame after polling events.
Input_Update :: proc(input: ^Input) {
	x, y := glfw.GetCursorPos(input.window)
	input.focused = glfw.GetWindowAttrib(input.window, glfw.FOCUSED) != 0
	left_down := glfw.GetMouseButton(input.window, glfw.MOUSE_BUTTON_LEFT) == glfw.PRESS
	input.click_edge = left_down && !input.left_was_down
	input.left_was_down = left_down
	if !left_down do input.swallow_left = false
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
	Num_1,
	Num_2,
	Num_3,
	Num_4,
	Num_5,
	R,
	F,
	C,
	Tab,
	Enter,
	V,
	B,
	M,
	H,
	Z,
	X,
	F9,
	F11,
	Num_6,
	N,
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
	.Num_1 = glfw.KEY_1,
	.Num_2 = glfw.KEY_2,
	.Num_3 = glfw.KEY_3,
	.Num_4 = glfw.KEY_4,
	.Num_5 = glfw.KEY_5,
	.R = glfw.KEY_R,
	.F = glfw.KEY_F,
	.C = glfw.KEY_C,
	.Tab = glfw.KEY_TAB,
	.Enter = glfw.KEY_ENTER,
	.V = glfw.KEY_V,
	.B = glfw.KEY_B,
	.M = glfw.KEY_M,
	.H = glfw.KEY_H,
	.Z = glfw.KEY_Z,
	.X = glfw.KEY_X,
	.F9 = glfw.KEY_F9,
	.F11 = glfw.KEY_F11,
	.Num_6 = glfw.KEY_6,
	.N = glfw.KEY_N,
}

Input_Key_Down :: proc(input: ^Input, key: Key) -> bool {
	return glfw.GetKey(input.window, glfw_keys[key]) == glfw.PRESS
}

// A click inside the window takes the mouse (and is not also a shot).
Input_Capture_By_Click :: proc(input: ^Input) {
	Input_Capture_Mouse(input, true)
	input.swallow_left = true
}

Input_Capture_Mouse :: proc(input: ^Input, captured: bool) {
	mode: i32 = glfw.CURSOR_DISABLED if captured else glfw.CURSOR_NORMAL
	glfw.SetInputMode(input.window, glfw.CURSOR, mode)
	input.has_mouse = false
	input.captured = captured
	input.mouse_delta = {}
}

Mouse_Button :: enum {
	Left,
	Right,
}

Input_Mouse_Down :: proc(input: ^Input, button: Mouse_Button) -> bool {
	if button == .Left && input.swallow_left do return false
	glfw_button: i32 = glfw.MOUSE_BUTTON_LEFT if button == .Left else glfw.MOUSE_BUTTON_RIGHT
	return glfw.GetMouseButton(input.window, glfw_button) == glfw.PRESS
}
