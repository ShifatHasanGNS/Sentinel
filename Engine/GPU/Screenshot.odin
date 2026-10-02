package GPU

import "core:fmt"
import "core:image"
import "core:image/bmp"
import gl "vendor:OpenGL"

// Reads the bound framebuffer; call after drawing and before the buffer swap. BMP because core:image can encode nothing else here.
Screenshot_Save :: proc(path: string, width, height: int) -> bool {
	channels :: 3
	row_size := width * channels
	bottom_up := make([]u8, row_size * height)
	defer delete(bottom_up)
	gl.PixelStorei(gl.PACK_ALIGNMENT, 1)
	gl.ReadPixels(0, 0, i32(width), i32(height), gl.RGB, gl.UNSIGNED_BYTE, raw_data(bottom_up))
	GL_Check()

	top_down := make([dynamic]u8, row_size * height)
	for row in 0 ..< height {
		copy(top_down[(height - 1 - row) * row_size:][:row_size], bottom_up[row * row_size:][:row_size])
	}
	screenshot := image.Image{width = width, height = height, channels = channels, depth = 8}
	screenshot.pixels.buf = top_down
	defer delete(screenshot.pixels.buf)

	save_error := bmp.save_to_file(path, &screenshot)
	if save_error != nil {
		fmt.eprintfln("screenshot save failed: %v", save_error)
		return false
	}
	return true
}
