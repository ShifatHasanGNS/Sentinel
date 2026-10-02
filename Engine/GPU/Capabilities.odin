package GPU

import gl "vendor:OpenGL"

@(private = "file")
anisotropy_max_cached: f32 = -1

// Zero means the driver lacks GL_EXT_texture_filter_anisotropic.
@(private = "package")
anisotropy_max :: proc() -> f32 {
	if anisotropy_max_cached >= 0 do return anisotropy_max_cached
	anisotropy_max_cached = 0
	if extension_supported("GL_EXT_texture_filter_anisotropic") {
		gl.GetFloatv(gl.MAX_TEXTURE_MAX_ANISOTROPY, &anisotropy_max_cached)
		GL_Check()
	}
	return anisotropy_max_cached
}

extension_supported :: proc(name: string) -> bool {
	count: i32
	gl.GetIntegerv(gl.NUM_EXTENSIONS, &count)
	for index in 0 ..< u32(count) {
		if string(gl.GetStringi(gl.EXTENSIONS, index)) == name do return true
	}
	return false
}
