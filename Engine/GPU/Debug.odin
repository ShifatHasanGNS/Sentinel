package GPU

import "core:fmt"
import gl "vendor:OpenGL"

GL_Check :: proc(location := #caller_location) {
	error_code := gl.GetError()
	if error_code == gl.NO_ERROR do return
	for gl.GetError() != gl.NO_ERROR {}
	panic(fmt.tprintf("OpenGL error 0x%04X", error_code), location)
}
