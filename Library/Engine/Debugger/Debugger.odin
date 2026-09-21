// Package Debugger — Library/Engine sub-package.
// Theme-agnostic: must never know about SENTINEL-specific scene/object code.
// Carried over from the earlier learning-project Engine.zip skeleton
// (Requirements.md §7, CLAUDE.md §13.2). Audited: no core:math/linalg usage,
// looks reusable as-is. Re-confirm during Session 1b's Engine integration pass.

package Debugger

import "core:fmt"
import "core:log"
import gl "vendor:OpenGL"

GL_Clear_Errors :: #force_inline proc() {
	for gl.GetError() != gl.NO_ERROR {}
}

GL_Check :: #force_inline proc(location := #caller_location) {
	for {
		error_code := gl.GetError()
		if error_code == gl.NO_ERROR do break
		GL_Clear_Errors()
		log.panicf("\n\n%s\n", GL_Error(error_code), location = location)
	}
}

Here :: proc() {
	fmt.eprint("\n====== Here ======\n")
}

@(private = "file")
GL_Error :: #force_inline proc(error_code: u32) -> (error: string) {
	switch error_code {
	case gl.INVALID_ENUM:
		error = "[OpenGL] (Error 0x0500) \"Invalid Enum\"\n         An unacceptable value is specified for an enumerated argument.\n         The offending command is ignored and has no other side effect than to set the error flag."
	case gl.INVALID_VALUE:
		error = "[OpenGL] (Error 0x0501) \"Invalid Value\"\n         A numeric argument is out of range.\n		 The offending command is ignored and has no other side effect than to set the error flag."
	case gl.INVALID_OPERATION:
		error = "[OpenGL] (Error 0x0502) \"Invalid Operation\"\n         The specified operation is not allowed in the current state.\n         The offending command is ignored and has no other side effect than to set the error flag."
	case gl.STACK_OVERFLOW:
		error = "[OpenGL] (Error 0x0503) \"Stack Overflow\"\n         An attempt has been made to perform an operation that would cause an internal stack to overflow."
	case gl.STACK_UNDERFLOW:
		error = "[OpenGL] (Error 0x0504) \"Stack Underflow\"\n         An attempt has been made to perform an operation that would cause an internal stack to underflow."
	case gl.OUT_OF_MEMORY:
		error = "[OpenGL] (Error 0x0505) \"Out of Memory\"\n         There is not enough memory left to execute the command.\n         The state of the GL is undefined, except for the state of the error flags, after this error is recorded."
	case gl.INVALID_FRAMEBUFFER_OPERATION:
		error = "[OpenGL] (Error 0x0506) \"Invalid Framebuffer Operation\"\n         The framebuffer object is not complete.\n         The offending command is ignored and has no other side effect than to set the error flag."
	case gl.NO_ERROR:
		error = "[OpenGL] \"No Error\""
	}
	return error
}
