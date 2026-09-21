// Package Debug — self-verification screenshot capture (CLAUDE.md §1.2).
//
// Claude Code cannot see the rendered window, so Source/Main.odin's
// `--capture <frames> <path>` flag calls Save_Screenshot once the requested
// frame has been drawn, so a session can read the result back itself.
// Nothing here is theme-specific; this stays generic capture/encode plumbing
// usable by any future scene, not just Session 0's throwaway triangle.
//
// Format choice: BMP via core:image/bmp, the only encoder in this Odin
// build's core library (checked during Session 0: core:image/png only
// decodes, not encodes). Claude Code's own image viewer cannot render BMP,
// though, so BMP is not directly "an image format Claude can read back" on
// its own — the small conversion helper this required is Debug/ToPng.sh
// (macOS `sips`), run by hand after a capture. See Debug/README.md and
// PROGRESS.md for why.
package Debug

import "core:image"
import "core:image/bmp"
import gl "vendor:OpenGL"

// Save_Screenshot reads the current default framebuffer's colour buffer and
// writes it to `path` as a BMP. Must be called after drawing and before
// glfw.SwapBuffers (or with an unswapped single-buffered context) so the
// pixels being read are the ones just rendered, not the previous frame's.
Save_Screenshot :: proc(path: string, width, height: int) -> image.Error {
	channels :: 3

	row_size := width * channels
	bottom_up_pixels := make([]u8, row_size * height)
	defer delete(bottom_up_pixels)

	// Tightly packed rows: framebuffer widths won't always be 4-byte
	// aligned, and the default GL_PACK_ALIGNMENT of 4 would otherwise
	// silently insert row padding ReadPixels doesn't tell us about.
	gl.PixelStorei(gl.PACK_ALIGNMENT, 1)
	gl.ReadPixels(0, 0, i32(width), i32(height), gl.RGB, gl.UNSIGNED_BYTE, raw_data(bottom_up_pixels))

	// glReadPixels' row 0 is the BOTTOM of the framebuffer; every image
	// encoder (bmp included) expects row 0 to be the TOP of the image. Flip
	// once here so no caller has to remember this quirk itself.
	top_down_pixels := make([dynamic]u8, row_size * height)
	for y in 0 ..< height {
		src := bottom_up_pixels[y * row_size:][:row_size]
		dst := top_down_pixels[(height - 1 - y) * row_size:][:row_size]
		copy(dst, src)
	}

	img := image.Image {
		width    = width,
		height   = height,
		channels = channels,
		depth    = 8,
	}
	img.pixels.buf = top_down_pixels
	defer delete(img.pixels.buf)

	return bmp.save_to_file(path, &img)
}
