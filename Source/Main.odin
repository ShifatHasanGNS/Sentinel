// Package main — SENTINEL entry point: window, GL context, main loop, mode
// switching, and input dispatch. Ties together `Library/Engine`,
// `Library/Geometry`, `Library/Scene`, and core:math/linalg (allowed
// directly, CLAUDE.md §2 item 3 — no separate hand-written math package);
// itself stays thin (Requirements.md §7, CLAUDE.md §8/§13).
//
// Session 0 status (CLAUDE.md/Plan.md roadmap "prep"): opens a GLFW +
// OpenGL 3.3 core-profile window and draws ONE throwaway triangle to prove
// the pipeline end-to-end, plus the --capture self-verification flag. This
// deliberately does NOT go through Library/Engine/Shader yet — that
// package's Shader.New expects one combined file with "#shader vertex"/
// "#shader fragment" markers, while Shaders/Scene.vert and Scene.frag are
// two separate files; vendor:OpenGL's own gl.load_shaders_file(vert, frag)
// already matches the two-file layout with built-in compile/link error
// reporting, so it is used here instead. Session 1b (Engine integration)
// must decide how Library/Engine/Shader reconciles with this two-file
// convention before real scene rendering routes through it.
//
// TODO(roadmap step 3): the triangle below is a one-off pipeline smoke test
// (CLAUDE.md §2 item 5) — delete make_throwaway_triangle and its call once
// Library/Geometry produces real meshes.
//
// Source/Input.odin (added once Inspection Mode exists, roadmap step 10):
// GLFW key/mouse callbacks, object selection, all interactive controls
// (CLAUDE.md §7's suggested key layout — Tab mode switch, P projection,
// 1/2/3 shading, C culling, Z depth test, [ ] select object, translate/
// rotate keys). Document the final key map in README.md, not just here.
//
// Source/Renderer.odin (grows alongside `Library/Engine/Renderer`, see that
// package's TODO): GL setup, per-frame uniform upload, the single shared
// draw loop used by BOTH Patrol and Inspection modes (CLAUDE.md §2 item 9 —
// never fork rendering logic per mode).
package main

import "core:fmt"
import "core:os"
import "core:strconv"

import "vendor:glfw"
import gl "vendor:OpenGL"

import dbg "../Library/Engine/Debugger"
import capture "../Debug"

// ---------------------------------------------------------------------------
// Window/GL conventions fixed here (see PROGRESS.md "Fixed conventions").
// Coordinate-system and matrix-layout conventions come with Session 1, once
// core:math/linalg is actually in use — there is no camera/projection math
// yet for those to apply to.
//   - OpenGL 3.3, core profile, forward-compatible (macOS requires forward
//     compatibility for any core-profile context above 3.2).
//   - Both future Patrol and Inspection modes share this one render path
//     (CLAUDE.md §2 item 9); nothing here branches on a mode yet because
//     there is no mode yet.
// ---------------------------------------------------------------------------

GL_VERSION_MAJOR :: 3
GL_VERSION_MINOR :: 3

DEFAULT_WINDOW_WIDTH :: 1280
DEFAULT_WINDOW_HEIGHT :: 720

// Cool, near-black clear colour — the fixed baseline "night sky" every
// session's lighting will be judged against.
CLEAR_COLOR :: [4]f32{0.02, 0.02, 0.05, 1.0}

VERTEX_SHADER_PATH :: "Shaders/Scene.vert"
FRAGMENT_SHADER_PATH :: "Shaders/Scene.frag"

main :: proc() {
	capture_frames, capture_path, do_capture := parse_capture_flag(os.args[1:])

	if !glfw.Init() {
		fmt.eprintln("Failed to initialize GLFW")
		os.exit(1)
	}
	defer glfw.Terminate()

	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, GL_VERSION_MAJOR)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, GL_VERSION_MINOR)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
	glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, true)
	glfw.WindowHint(glfw.RESIZABLE, true)
	// A capture run has no one watching the window; hiding it avoids an
	// on-screen flash for a run that closes itself after N frames.
	glfw.WindowHint(glfw.VISIBLE, !do_capture)

	window := glfw.CreateWindow(DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT, "SENTINEL", nil, nil)
	if window == nil {
		fmt.eprintln("Failed to create GLFW window")
		os.exit(1)
	}
	defer glfw.DestroyWindow(window)

	glfw.MakeContextCurrent(window)
	glfw.SwapInterval(1)
	glfw.SetFramebufferSizeCallback(window, framebuffer_size_callback)
	glfw.SetKeyCallback(window, key_callback)

	gl.load_up_to(GL_VERSION_MAJOR, GL_VERSION_MINOR, glfw.gl_set_proc_address)

	fmt.printfln("GPU vendor:   %s", gl.GetString(gl.VENDOR))
	fmt.printfln("GPU renderer: %s", gl.GetString(gl.RENDERER))
	fmt.printfln("OpenGL:       %s", gl.GetString(gl.VERSION))
	fmt.printfln("GLSL:         %s", gl.GetString(gl.SHADING_LANGUAGE_VERSION))

	fb_width, fb_height := glfw.GetFramebufferSize(window)
	gl.Viewport(0, 0, fb_width, fb_height); dbg.GL_Check()

	triangle_vao, triangle_vbo := make_throwaway_triangle()
	defer gl.DeleteVertexArrays(1, &triangle_vao)
	defer gl.DeleteBuffers(1, &triangle_vbo)

	shader_program, shader_ok := gl.load_shaders_file(VERTEX_SHADER_PATH, FRAGMENT_SHADER_PATH)
	if !shader_ok {
		// gl.load_shaders_file already printed the GLSL compile/link log.
		fmt.eprintln("Failed to build the shader program; see the compile/link log above")
		os.exit(1)
	}
	defer gl.DeleteProgram(shader_program)
	fmt.printfln("Shader program linked: id=%d", shader_program)

	frame_count := 0
	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents()

		gl.ClearColor(CLEAR_COLOR.x, CLEAR_COLOR.y, CLEAR_COLOR.z, CLEAR_COLOR.w); dbg.GL_Check()
		gl.Clear(gl.COLOR_BUFFER_BIT); dbg.GL_Check()

		gl.UseProgram(shader_program); dbg.GL_Check()
		gl.BindVertexArray(triangle_vao); dbg.GL_Check()
		gl.DrawArrays(gl.TRIANGLES, 0, 3); dbg.GL_Check()

		frame_count += 1

		if do_capture && frame_count == capture_frames {
			if err := capture.Save_Screenshot(capture_path, int(fb_width), int(fb_height)); err != nil {
				fmt.eprintfln("Capture failed: %v", err)
				os.exit(1)
			}
			fmt.printfln("Captured frame %d/%d to %s", frame_count, capture_frames, capture_path)
			glfw.SetWindowShouldClose(window, true)
		}

		glfw.SwapBuffers(window)
	}
}

framebuffer_size_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
	gl.Viewport(0, 0, width, height)
}

key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
	if key == glfw.KEY_ESCAPE && action == glfw.PRESS {
		glfw.SetWindowShouldClose(window, true)
	}
}

// parse_capture_flag looks for "--capture <frames> <path>" anywhere in argv
// (there is nothing else to parse yet, so position doesn't matter). Exits
// the process on a malformed flag rather than silently ignoring it, since a
// typo'd capture request should never be mistaken for "capture disabled".
parse_capture_flag :: proc(args: []string) -> (frames: int, path: string, requested: bool) {
	for i := 0; i < len(args); i += 1 {
		if args[i] != "--capture" do continue

		if i + 2 >= len(args) {
			fmt.eprintln("--capture requires two arguments: <frames> <path>")
			os.exit(1)
		}

		parsed_frames, ok := strconv.parse_int(args[i + 1])
		if !ok || parsed_frames <= 0 {
			fmt.eprintfln("--capture: frame count must be a positive integer, got '%s'", args[i + 1])
			os.exit(1)
		}

		return parsed_frames, args[i + 2], true
	}

	return 0, "", false
}

// make_throwaway_triangle uploads one hardcoded triangle so Session 0 has
// something to draw before Library/Geometry exists. CLAUDE.md §2 item 5
// bans hardcoded scene geometry, but explicitly exempts this one throwaway
// pipeline-test triangle — see the file header TODO to delete it.
make_throwaway_triangle :: proc() -> (vao, vbo: u32) {
	positions := [9]f32{
		0.0, 0.6, 0.0,
		-0.6, -0.5, 0.0,
		0.6, -0.5, 0.0,
	}

	gl.GenVertexArrays(1, &vao); dbg.GL_Check()
	gl.BindVertexArray(vao); dbg.GL_Check()

	gl.GenBuffers(1, &vbo); dbg.GL_Check()
	gl.BindBuffer(gl.ARRAY_BUFFER, vbo); dbg.GL_Check()
	gl.BufferData(gl.ARRAY_BUFFER, size_of(positions), &positions, gl.STATIC_DRAW); dbg.GL_Check()

	gl.VertexAttribPointer(0, 3, gl.FLOAT, false, 3 * size_of(f32), 0); dbg.GL_Check()
	gl.EnableVertexAttribArray(0); dbg.GL_Check()

	gl.BindVertexArray(0); dbg.GL_Check()
	return
}
