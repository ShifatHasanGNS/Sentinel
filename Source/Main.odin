// package main — SENTINEL entry point: window, GL context, main loop, mode switching, input.
package main

import "core:fmt"
import "core:math"
import la "core:math/linalg"
import "core:os"
import "core:strconv"
import "base:runtime"

import "vendor:glfw"
import gl "vendor:OpenGL"

import cam "../Library/Camera"
import geo "../Library/Geometry"
import scenepkg "../Library/Scene"

import dbg "../Library/Engine/Debugger"
import sd "../Library/Engine/Shader"
import capture "../Debug"

GL_VERSION_MAJOR :: 3
GL_VERSION_MINOR :: 3

DEFAULT_WINDOW_WIDTH :: 1280
DEFAULT_WINDOW_HEIGHT :: 720

CLEAR_COLOR :: [4]f32{0.02, 0.02, 0.05, 1.0}

COMBINED_SHADER_PATH :: "Shaders/Scene.glsl"

CAMERA_START_EYE :: la.Vector3f32{0.0, 22.0, 34.0}
SCENE_FOCUS :: la.Vector3f32{0, 0, 0}

AMBIENT_COLOR :: la.Vector3f32{0.55, 0.6, 0.75}
AMBIENT_STRENGTH :: 0.18

GROUND_SIZE :: 60.0
GROUND_Y :: 0.0

DEFAULT_MODE :: Mode.Patrol
DEFAULT_ANIMATION_SPEED_SCALE :: f32(1.0)
DEFAULT_AREA_LIGHT_SAMPLE_COUNT :: 4

// Must match Shaders/Scene.glsl's SHADING_FLAT/GOURAUD/PHONG #defines.
SHADING_FLAT :: i32(0)
SHADING_GOURAUD :: i32(1)
SHADING_PHONG :: i32(2)
DEFAULT_SHADING_MODE :: SHADING_PHONG

SHADING_MODE_NAME := [3]string{"Flat", "Gouraud", "Phong"}

// Must match Shaders/Scene.glsl's CULL_OFF/CULL_MANUAL/CULL_GL #defines.
CULL_OFF :: i32(0)
CULL_MANUAL :: i32(1)
CULL_GL :: i32(2)
DEFAULT_CULL_MODE :: CULL_GL
CULL_MODE_NAME := [3]string{"Off", "Manual", "GL"}

TRIANGLE_COUNT_DEMO_OBJECT :: "Watchtower"

GROUND_GRID_LOW_RESOLUTION :: 1
GROUND_GRID_HIGH_RESOLUTION :: 24

DEFAULT_EDIT_STEP_SCALE :: f32(1.0)
DEFAULT_RAY_TRACED_REFLECTION_ENABLED :: true

DEFAULT_TONEMAPPING_ENABLED :: true
DEFAULT_VIGNETTE_ENABLED :: true
DEFAULT_FOG_ENABLED :: true
DEFAULT_GROUND_DETAIL_ENABLED :: true
DEFAULT_SKY_ENABLED :: true

// [PROGRESS-DEMO] Branch-only (`progress_objects`), not present on `main`.
// Forces Shaders/Scene.glsl's u_ObjectsOnlyMode uniform on, which makes
// main() there return a fragment's own flat u_BaseColor immediately,
// before lighting/shading-mode/reflection/polish code ever runs — every
// toggle ABOVE this line (reflection, tonemapping, vignette, fog, ground
// detail, sky) still gets its normal default and still gets uploaded each
// frame exactly as on `main`, it's just that the shader never reaches the
// code that would read most of them. Nothing here was removed or
// commented out (this session's own instruction) — this one constant is
// the entire change on the Odin side; delete the `progress_objects`
// branch to remove it rather than hand-reverting.
DEFAULT_OBJECTS_ONLY_MODE :: true

// Must fit inside Camera's far plane (100) even from a cube corner.
SKY_CUBE_SIZE :: f32(80.0)

FPS_DISPLAY_UPDATE_INTERVAL :: f32(0.5)
BENCHMARK_WARMUP_FRAMES :: 10

main :: proc() {
	capture_frames, capture_path, do_capture := parse_capture_flag(os.args[1:])
	start_projection := parse_projection_flag(os.args[1:])
	shading_mode = parse_shading_flag(os.args[1:])
	ground_resolution = parse_ground_resolution_flag(os.args[1:])
	cull_mode = parse_cull_flag(os.args[1:])
	depth_test_enabled = parse_depth_test_flag(os.args[1:])
	wireframe_enabled = parse_wireframe_flag(os.args[1:])
	backface_debug_enabled = parse_backface_debug_flag(os.args[1:])
	depth_visualization_enabled = parse_depth_visualization_flag(os.args[1:])
	current_mode = parse_mode_flag(os.args[1:])
	animation_speed_scale = parse_patrol_speed_flag(os.args[1:])
	// [PROGRESS-DEMO] Branch-only: --test-inspection and ray-traced
	// reflection are both removed on this branch (the former verified
	// light-tracking specifically; the latter needs Library/Lights-derived
	// material/light data). See PROGRESS-DEMO notes throughout this file.
	edit_step_scale = DEFAULT_EDIT_STEP_SCALE
	tonemapping_enabled = parse_tonemapping_flag(os.args[1:])
	vignette_enabled = parse_vignette_flag(os.args[1:])
	fog_enabled = parse_fog_flag(os.args[1:])
	ground_detail_enabled = parse_ground_detail_flag(os.args[1:])
	sky_enabled = parse_sky_flag(os.args[1:])
	// [PROGRESS-DEMO] Branch-only — see DEFAULT_OBJECTS_ONLY_MODE's comment.
	objects_only_mode = DEFAULT_OBJECTS_ONLY_MODE
	benchmark_frames, do_benchmark := parse_benchmark_flag(os.args[1:])
	msaa_samples := parse_msaa_flag(os.args[1:])

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
	// Sample count is fixed at context creation; can't toggle MSAA live.
	if msaa_samples > 0 {
		glfw.WindowHint(glfw.SAMPLES, msaa_samples)
	}
	glfw.WindowHint(glfw.VISIBLE, !do_capture && !do_benchmark)

	window := glfw.CreateWindow(DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT, build_window_title(), nil, nil)
	if window == nil {
		fmt.eprintln("Failed to create GLFW window")
		os.exit(1)
	}
	defer glfw.DestroyWindow(window)

	glfw.MakeContextCurrent(window)
	// Benchmark wants uncapped GPU cost, not display-refresh-capped.
	glfw.SwapInterval(0 if do_benchmark else 1)
	glfw.SetFramebufferSizeCallback(window, framebuffer_size_callback)
	glfw.SetKeyCallback(window, key_callback)
	glfw.SetMouseButtonCallback(window, mouse_button_callback)
	glfw.SetScrollCallback(window, scroll_callback)

	gl.load_up_to(GL_VERSION_MAJOR, GL_VERSION_MINOR, glfw.gl_set_proc_address)

	if msaa_samples > 0 {
		// The hint above only requests it; still needs enabling.
		gl.Enable(gl.MULTISAMPLE); dbg.GL_Check()
		fmt.printfln("MSAA: %dx (--msaa)", msaa_samples)
	}

	fmt.printfln("GPU vendor:   %s", gl.GetString(gl.VENDOR))
	fmt.printfln("GPU renderer: %s", gl.GetString(gl.RENDERER))
	fmt.printfln("OpenGL:       %s", gl.GetString(gl.VERSION))
	fmt.printfln("GLSL:         %s", gl.GetString(gl.SHADING_LANGUAGE_VERSION))

	fb_width, fb_height := glfw.GetFramebufferSize(window)
	gl.Viewport(0, 0, fb_width, fb_height); dbg.GL_Check()

	scene := scenepkg.Build_Scene()
	defer scenepkg.Destroy(&scene)

	// Rest pose captured once, before any edits, for the reset keys.
	original_transforms := make([]scenepkg.Transform, len(scene.Nodes))
	defer delete(original_transforms)
	for node, i in scene.Nodes {
		original_transforms[i] = node.Local
	}

	object_count, node_count := 0, len(scene.Nodes)
	for node in scene.Nodes {
		if node.Parent == scenepkg.NO_PARENT do object_count += 1
	}
	fmt.printfln("Scene: %d objects, %d nodes total", object_count, node_count)

	ground_mesh := build_ground_mesh(ground_resolution)
	defer geo.Destroy(&ground_mesh)
	fmt.printfln("Ground grid: %dx%d cells (G to toggle), shading mode: %s", ground_resolution, ground_resolution, SHADING_MODE_NAME[shading_mode])
	ground_material := scenepkg.Default_Material(la.Vector3f32{0.05, 0.05, 0.06})
	ground_model := la.mul(la.matrix4_translate(la.Vector3f32{0, GROUND_Y, 0}), la.matrix4_rotate(-math.PI * 0.5, la.Vector3f32{1, 0, 0}))

	// Sky dome mesh built once; its transform is re-centred on the camera every frame.
	sky_mesh := geo.Cube(SKY_CUBE_SIZE, SKY_CUBE_SIZE, SKY_CUBE_SIZE)
	geo.Upload(&sky_mesh)
	defer geo.Destroy(&sky_mesh)
	sky_material := scenepkg.Default_Material(la.Vector3f32{0, 0, 0})

	// [PROGRESS-DEMO] Branch-only: Library/Lights' rig build/upload/gizmos
	// and the area-light sample-count/jitter controls are removed here —
	// see PROGRESS-DEMO notes throughout this file. Restore by switching
	// to main or deleting this branch.

	fmt.printfln(
		"Render toggles: Cull=%s (C), Depth test=%v (Z), Depth visualization=%v (X), Wireframe=%v (F), Backface debug=%v (B)",
		CULL_MODE_NAME[cull_mode], depth_test_enabled, depth_visualization_enabled, wireframe_enabled, backface_debug_enabled,
	)

	total_triangle_count := count_total_triangles(&scene, &ground_mesh)
	demo_node_index := scenepkg.Find_Node(&scene, TRIANGLE_COUNT_DEMO_OBJECT)
	if demo_node_index != scenepkg.NO_PARENT {
		startup_world_matrices := scenepkg.Compute_World_Matrices(&scene)
		demo_world_matrix := startup_world_matrices[demo_node_index]
		demo_normal_matrix := scenepkg.Normal_Matrix(demo_world_matrix)
		demo_view_direction := la.normalize(CAMERA_START_EYE - scenepkg.World_Position(demo_world_matrix))
		delete(startup_world_matrices)

		demo_mesh := &scene.Nodes[demo_node_index].Mesh
		demo_triangle_count := len(demo_mesh.Indices) / 3
		demo_back_facing_count := count_back_facing_triangles(demo_mesh, demo_normal_matrix, demo_view_direction)
		fmt.printfln(
			"Triangles: %d submitted across the whole scene; %s alone has %d, ~%d (%.0f%%) estimated back-facing from the starting view (roughly the saving GL cull mode would give on it)",
			total_triangle_count,
			TRIANGLE_COUNT_DEMO_OBJECT,
			demo_triangle_count,
			demo_back_facing_count,
			100.0 * f32(demo_back_facing_count) / f32(demo_triangle_count),
		)
	}

	floodlight_head_node := scenepkg.Find_Node(&scene, "Watchtower Floodlight Head")
	radar_dish_node := scenepkg.Find_Node(&scene, "Radar Dish")
	tank_turret_node := scenepkg.Find_Node(&scene, "Tank Turret")
	jeep_headlight_left_node := scenepkg.Find_Node(&scene, "Jeep Headlight Left")
	jeep_headlight_right_node := scenepkg.Find_Node(&scene, "Jeep Headlight Right")

	// [PROGRESS-DEMO] Branch-only: the radar-beacon/fence-lamp INTENSITY
	// animations (Library/Lights-derived) are removed here — see the
	// per-frame Patrol block below. Restore by switching to main or
	// deleting this branch.

	selectable_nodes := Build_Selectable_Nodes(&scene)
	defer delete(selectable_nodes)
	selectable_aabbs := make([]AABB, len(selectable_nodes))
	defer delete(selectable_aabbs)
	for node_index, i in selectable_nodes {
		selectable_aabbs[i] = Compute_Local_AABB(&scene.Nodes[node_index].Mesh)
	}
	selected_node_name = scene.Nodes[selectable_nodes[selected_index]].Name
	fmt.printfln("Inspection: %d selectable objects, starting selection %q ([/] to cycle, H for full controls)", len(selectable_nodes), selected_node_name)
	Print_Controls()

	// [PROGRESS-DEMO] Branch-only: ray-traced reflection's proxy setup and
	// Library/Lights' gizmo meshes are both removed here — see
	// PROGRESS-DEMO notes throughout this file. Restore by switching to
	// main or deleting this branch.

	shader := sd.New(COMBINED_SHADER_PATH)
	if shader.RendererID == 0 {
		fmt.eprintln("Failed to build the shader program; see the log above")
		os.exit(1)
	}
	fmt.printfln("Shader program linked: id=%d", shader.RendererID)
	defer sd.Delete(&shader)

	camera := cam.Camera_Looking_At(CAMERA_START_EYE, SCENE_FOCUS)
	if start_projection == .Orthographic {
		cam.Toggle_Projection(&camera, SCENE_FOCUS)
	}

	last_cursor_x, last_cursor_y: f64
	if !do_capture {
		glfw.SetInputMode(window, glfw.CURSOR, glfw.CURSOR_DISABLED)
		last_cursor_x, last_cursor_y = glfw.GetCursorPos(window)
	}

	frame_count := 0
	last_frame_time := glfw.GetTime()

	// Benchmark accumulators; first BENCHMARK_WARMUP_FRAMES excluded from the average.
	benchmark_frame_time_sum: f32
	benchmark_frame_time_min := f32(1e9)
	benchmark_frame_time_max := f32(0)
	benchmark_measured_frames := 0
	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents()

		current_time := glfw.GetTime()
		dt_seconds := f32(current_time - last_frame_time)
		last_frame_time = current_time

		if !do_capture {
			cursor_x, cursor_y := glfw.GetCursorPos(window)
			if current_mode == .Inspection {
				cam.Apply_Look_Delta(&camera, f32(cursor_x - last_cursor_x), f32(cursor_y - last_cursor_y))

				move_forward := key_axis(window, glfw.KEY_W, glfw.KEY_S)
				move_right := key_axis(window, glfw.KEY_D, glfw.KEY_A)
				move_up := key_axis(window, glfw.KEY_E, glfw.KEY_Q)
				sprint := glfw.GetKey(window, glfw.KEY_LEFT_SHIFT) == glfw.PRESS || glfw.GetKey(window, glfw.KEY_RIGHT_SHIFT) == glfw.PRESS
				cam.Apply_Move(&camera, move_forward, move_right, move_up, dt_seconds, sprint)
			}
			last_cursor_x, last_cursor_y = cursor_x, cursor_y

			fps_display_accum_time += dt_seconds
			fps_display_accum_frames += 1
			if fps_display_accum_time >= FPS_DISPLAY_UPDATE_INTERVAL {
				fps_display_value = f32(fps_display_accum_frames) / fps_display_accum_time
				fps_display_accum_time = 0
				fps_display_accum_frames = 0
				glfw.SetWindowTitle(window, build_window_title())
			}

			if projection_toggle_requested {
				cam.Toggle_Projection(&camera, SCENE_FOCUS)
				projection_toggle_requested = false
			}

			if camera.projection == .Orthographic && scroll_delta_y != 0 {
				cam.Zoom_Ortho(&camera, scroll_delta_y)
			}
			scroll_delta_y = 0

			if mode_switch_requested {
				if current_mode == .Inspection {
					// Resume patrol from the nearest path point, not a raw-clock jump.
					desired_angle := cam.Patrol_Nearest_Angle(camera.position)
					base_angle := animation_time * cam.PATROL_ANGULAR_SPEED
					patrol_time_offset = (desired_angle - base_angle) / cam.PATROL_ANGULAR_SPEED
					current_mode = .Patrol
				} else {
					current_mode = .Inspection
				}
				glfw.SetWindowTitle(window, build_window_title())
				mode_switch_requested = false
			}

			if current_mode == .Inspection {
				if select_prev_requested {
					selected_index = (selected_index - 1 + len(selectable_nodes)) % len(selectable_nodes)
					selected_node_name = scene.Nodes[selectable_nodes[selected_index]].Name
					glfw.SetWindowTitle(window, build_window_title())
				}
				if select_next_requested {
					selected_index = (selected_index + 1) % len(selectable_nodes)
					selected_node_name = scene.Nodes[selectable_nodes[selected_index]].Name
					glfw.SetWindowTitle(window, build_window_title())
				}

				selected_scene_node := selectable_nodes[selected_index]
				if pending_translate_delta != (la.Vector3f32{0, 0, 0}) {
					Apply_Translate(&scene, selected_scene_node, pending_translate_delta)
					pending_translate_delta = {0, 0, 0}
				}
				if pending_rotate_delta != (la.Vector3f32{0, 0, 0}) {
					Apply_Rotate(&scene, selected_scene_node, pending_rotate_delta)
					pending_rotate_delta = {0, 0, 0}
				}
				if reset_selected_requested {
					Reset_Node(&scene, selected_scene_node, original_transforms[selected_scene_node])
					reset_selected_requested = false
				}
				if reset_all_requested {
					for i in 0 ..< len(scene.Nodes) {
						Reset_Node(&scene, i, original_transforms[i])
					}
					reset_all_requested = false
				}
			} else {
				select_prev_requested = false
				select_next_requested = false
				pending_translate_delta = {0, 0, 0}
				pending_rotate_delta = {0, 0, 0}
				reset_selected_requested = false
				reset_all_requested = false
				pick_requested = false
			}
		}

		if ground_resolution_toggle_requested {
			geo.Destroy(&ground_mesh)
			ground_resolution = GROUND_GRID_HIGH_RESOLUTION if ground_resolution == GROUND_GRID_LOW_RESOLUTION else GROUND_GRID_LOW_RESOLUTION
			ground_mesh = build_ground_mesh(ground_resolution)
			fmt.printfln("Ground grid: %dx%d cells", ground_resolution, ground_resolution)
			ground_resolution_toggle_requested = false
		}

		// Fixed nominal step during --capture, for reproducibility.
		frame_dt := dt_seconds
		if do_capture {
			frame_dt = 1.0 / 60.0
		}
		if !animation_paused {
			animation_time += frame_dt * animation_speed_scale
		}

		if current_mode == .Patrol {
			camera_path_time := animation_time + patrol_time_offset
			camera.position, camera.yaw, camera.pitch = cam.Patrol_Camera_Pose(camera_path_time)

			if floodlight_head_node != scenepkg.NO_PARENT {
				scene.Nodes[floodlight_head_node].Local.Rotation.y = Patrol_Floodlight_Sweep_Angle(animation_time)
			}
			if radar_dish_node != scenepkg.NO_PARENT {
				scene.Nodes[radar_dish_node].Local.Rotation.y = Patrol_Radar_Spin_Angle(animation_time)
			}
			// [PROGRESS-DEMO] Branch-only: beacon intensity blink removed —
			// see PROGRESS-DEMO notes throughout this file.

			if tank_turret_node != scenepkg.NO_PARENT {
				scene.Nodes[tank_turret_node].Local.Rotation.y = Patrol_Turret_Scan_Angle(animation_time)
			}
			if jeep_headlight_left_node != scenepkg.NO_PARENT {
				scene.Nodes[jeep_headlight_left_node].Local.Rotation.x = Patrol_Jeep_Dip_Angle(animation_time)
			}
			if jeep_headlight_right_node != scenepkg.NO_PARENT {
				scene.Nodes[jeep_headlight_right_node].Local.Rotation.x = Patrol_Jeep_Dip_Angle(animation_time)
			}
			// [PROGRESS-DEMO] Branch-only: fence-lamp flicker removed — see
			// PROGRESS-DEMO notes throughout this file.
		}

		apply_render_state()

		gl.ClearColor(CLEAR_COLOR.x, CLEAR_COLOR.y, CLEAR_COLOR.z, CLEAR_COLOR.w); dbg.GL_Check()
		gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT); dbg.GL_Check()

		current_fb_width, current_fb_height := glfw.GetFramebufferSize(window)
		aspect := f32(current_fb_width) / f32(current_fb_height)

		view := cam.View_Matrix(&camera)
		projection := cam.Projection_Matrix(&camera, aspect)

		if !do_capture && current_mode == .Inspection && pick_requested {
			ray_origin, ray_direction := Screen_Point_To_Ray(view, projection, 0, 0)
			pick_world_matrices := scenepkg.Compute_World_Matrices(&scene)
			picked := Pick_Node(pick_world_matrices[:], selectable_nodes[:], selectable_aabbs, ray_origin, ray_direction)
			delete(pick_world_matrices)
			if picked >= 0 {
				selected_index = picked
				selected_node_name = scene.Nodes[selectable_nodes[selected_index]].Name
				glfw.SetWindowTitle(window, build_window_title())
			}
		}
		pick_requested = false

		world_matrices := scenepkg.Compute_World_Matrices(&scene)
		sd.SetUniform(&shader, "u_ViewPosition", camera.position.x, camera.position.y, camera.position.z)
		sd.SetUniform(&shader, "u_AmbientColor", AMBIENT_COLOR.r, AMBIENT_COLOR.g, AMBIENT_COLOR.b)
		sd.SetUniform(&shader, "u_AmbientStrength", f32(AMBIENT_STRENGTH))
		// [PROGRESS-DEMO] Branch-only: Library/Lights' per-frame update/
		// upload and the area-light sample-count/jitter uniforms are
		// removed here — see PROGRESS-DEMO notes throughout this file.
		sd.SetUniform(&shader, "u_ShadingMode", shading_mode)

		sd.SetUniform(&shader, "u_CullMode", cull_mode)
		view_direction := cam.Forward(&camera)
		sd.SetUniform(&shader, "u_ViewDirection", view_direction.x, view_direction.y, view_direction.z)
		is_orthographic_value: i32 = 0
		if camera.projection == .Orthographic do is_orthographic_value = 1
		sd.SetUniform(&shader, "u_IsOrthographic", is_orthographic_value)
		backface_debug_value: i32 = 0
		if backface_debug_enabled do backface_debug_value = 1
		sd.SetUniform(&shader, "u_BackfaceDebug", backface_debug_value)
		depth_visualization_value: i32 = 0
		if depth_visualization_enabled do depth_visualization_value = 1
		sd.SetUniform(&shader, "u_DepthVisualization", depth_visualization_value)
		sd.SetUniform(&shader, "u_Near", camera.near)
		sd.SetUniform(&shader, "u_Far", camera.far)

		// [PROGRESS-DEMO] Branch-only: ray-traced reflection's per-frame
		// proxy rebuild/upload is removed here — see PROGRESS-DEMO notes
		// throughout this file.
		sd.SetUniform(&shader, "u_SkyColor", CLEAR_COLOR.x, CLEAR_COLOR.y, CLEAR_COLOR.z)

		// [PROGRESS-DEMO] Branch-only — see DEFAULT_OBJECTS_ONLY_MODE's own comment.
		objects_only_mode_value: i32 = 0
		if objects_only_mode do objects_only_mode_value = 1
		sd.SetUniform(&shader, "u_ObjectsOnlyMode", objects_only_mode_value)

		tonemapping_value: i32 = 0
		if tonemapping_enabled do tonemapping_value = 1
		sd.SetUniform(&shader, "u_TonemappingEnabled", tonemapping_value)
		vignette_value: i32 = 0
		if vignette_enabled do vignette_value = 1
		sd.SetUniform(&shader, "u_VignetteEnabled", vignette_value)
		sd.SetUniform(&shader, "u_Resolution", f32(current_fb_width), f32(current_fb_height))
		fog_value: i32 = 0
		if fog_enabled do fog_value = 1
		sd.SetUniform(&shader, "u_FogEnabled", fog_value)
		sd.SetUniform(&shader, "u_Time", animation_time)

		// Sky drawn first, no depth write, standard skybox technique.
		if sky_enabled {
			sky_model := la.matrix4_translate(camera.position)
			gl.Disable(gl.CULL_FACE); dbg.GL_Check()
			gl.DepthMask(false); dbg.GL_Check()
			sd.SetUniform(&shader, "u_IsSky", i32(1))
			scenepkg.Draw_Node(&shader, view, projection, sky_model, &sky_mesh, sky_material)
			sd.SetUniform(&shader, "u_IsSky", i32(0))
			gl.DepthMask(true); dbg.GL_Check()
			apply_render_state()
		}

		ground_detail_value: i32 = 0
		if ground_detail_enabled do ground_detail_value = 1
		sd.SetUniform(&shader, "u_IsGround", ground_detail_value)
		scenepkg.Draw_Node(&shader, view, projection, ground_model, &ground_mesh, ground_material)
		sd.SetUniform(&shader, "u_IsGround", i32(0))

		highlighted_node := selectable_nodes[selected_index] if current_mode == .Inspection else -1
		draw_scene_nodes(&shader, view, projection, &scene, world_matrices[:], highlighted_node, Inspection_Highlight_Pulse(animation_time))
		delete(world_matrices)

		// [PROGRESS-DEMO] Branch-only: light gizmos removed — see
		// PROGRESS-DEMO notes throughout this file.

		frame_count += 1

		if do_capture && frame_count == capture_frames {
			if err := capture.Save_Screenshot(capture_path, int(fb_width), int(fb_height)); err != nil {
				fmt.eprintfln("Capture failed: %v", err)
				os.exit(1)
			}
			fmt.printfln("Captured frame %d/%d to %s", frame_count, capture_frames, capture_path)
			glfw.SetWindowShouldClose(window, true)
		}

		if do_benchmark {
			if frame_count > BENCHMARK_WARMUP_FRAMES {
				benchmark_frame_time_sum += dt_seconds
				benchmark_frame_time_min = min(benchmark_frame_time_min, dt_seconds)
				benchmark_frame_time_max = max(benchmark_frame_time_max, dt_seconds)
				benchmark_measured_frames += 1
			}
			if frame_count == benchmark_frames {
				if benchmark_measured_frames == 0 {
					fmt.eprintfln("Benchmark: --benchmark %d must exceed the %d warm-up frames", benchmark_frames, BENCHMARK_WARMUP_FRAMES)
					os.exit(1)
				}
				avg_ms := (benchmark_frame_time_sum / f32(benchmark_measured_frames)) * 1000.0
				avg_fps := 1000.0 / avg_ms
				target_ms := f32(1000.0 / 60.0)
				fmt.printfln(
					"Benchmark: %d frames measured (after %d warm-up, vsync off) at %dx%d — avg %.3fms (%.1f FPS), min %.3fms, max %.3fms",
					benchmark_measured_frames, BENCHMARK_WARMUP_FRAMES, fb_width, fb_height,
					avg_ms, avg_fps, benchmark_frame_time_min*1000.0, benchmark_frame_time_max*1000.0,
				)
				if avg_ms > target_ms {
					fmt.printfln("Benchmark: average frame time EXCEEDS the 60 FPS budget (%.3fms) by %.3fms", target_ms, avg_ms-target_ms)
				} else {
					fmt.printfln("Benchmark: holds 60 FPS with %.3fms of budget to spare", target_ms-avg_ms)
				}
				glfw.SetWindowShouldClose(window, true)
			}
		}

		glfw.SwapBuffers(window)
	}
}

framebuffer_size_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
	gl.Viewport(0, 0, width, height)
}

projection_toggle_requested: bool
scroll_delta_y: f32

// [PROGRESS-DEMO] Branch-only: gizmos_visible/area_light_sample_count/
// area_light_jitter (all Library/Lights-derived) removed here — see
// PROGRESS-DEMO notes throughout this file.

shading_mode: i32
ground_resolution: int
ground_resolution_toggle_requested: bool

cull_mode: i32
depth_test_enabled: bool
depth_visualization_enabled: bool
wireframe_enabled: bool
backface_debug_enabled: bool

current_mode: Mode
mode_switch_requested: bool
animation_time: f32
animation_paused: bool
animation_speed_scale: f32
patrol_time_offset: f32

// selected_index indexes INTO selectable_nodes, not scene.Nodes directly.
selected_index: int
selected_node_name: string
select_next_requested: bool
select_prev_requested: bool
pick_requested: bool
pending_translate_delta: la.Vector3f32
pending_rotate_delta: la.Vector3f32
edit_step_scale: f32
reset_selected_requested: bool
reset_all_requested: bool

// [PROGRESS-DEMO] Branch-only: ray_traced_reflection_enabled removed —
// see PROGRESS-DEMO notes throughout this file.

tonemapping_enabled: bool
vignette_enabled: bool
fog_enabled: bool
ground_detail_enabled: bool
sky_enabled: bool

// [PROGRESS-DEMO] Branch-only, see DEFAULT_OBJECTS_ONLY_MODE's own comment.
objects_only_mode: bool

fps_display_value: f32
fps_display_accum_time: f32
fps_display_accum_frames: int

key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
	context = runtime.default_context()

	if key == glfw.KEY_ESCAPE && action == glfw.PRESS {
		glfw.SetWindowShouldClose(window, true)
	}
	if key == glfw.KEY_P && action == glfw.PRESS {
		projection_toggle_requested = true
	}
	// [PROGRESS-DEMO] Branch-only: light-gizmo toggle (L), area-light
	// sample-count/jitter controls (+/-/N), shading-mode selection
	// (1/2/3), ground-grid resolution (G), back-face culling (C), depth
	// test (Z), depth visualisation (X), back-face debug tint (B), and
	// the polish-pass toggles (M/V/Y/T/`/`) are all removed here. Every
	// one of them either controls a syllabus topic this milestone
	// explicitly scopes as "planned, not yet done" (shading, culling,
	// hidden-surface removal — see Docs/report), or was already a
	// silent no-op on this branch: Shaders/Scene.glsl's u_ObjectsOnlyMode
	// early-return is the very first statement in the fragment shader's
	// main(), before any of that code ever runs, so pressing these keys
	// previously retitled the window (implying something changed) with
	// zero visible effect — exactly the kind of input-system
	// inconsistency this pass removes. Wireframe (F, below) is kept: it
	// is a plain mesh-inspection tool (GL_LINE polygon mode is real GL
	// state, independent of the shader) that directly supports this
	// milestone's own "these are real procedural triangle meshes" story,
	// not a lighting/shading/culling concept.
	if key == glfw.KEY_F && action == glfw.PRESS {
		wireframe_enabled = !wireframe_enabled
		glfw.SetWindowTitle(window, build_window_title())
	}
	if key == glfw.KEY_TAB && action == glfw.PRESS {
		mode_switch_requested = true
	}
	if key == glfw.KEY_SPACE && action == glfw.PRESS {
		animation_paused = !animation_paused
		glfw.SetWindowTitle(window, build_window_title())
	}
	if key == glfw.KEY_PERIOD && action == glfw.PRESS {
		animation_speed_scale = min(animation_speed_scale*PATROL_SPEED_STEP_FACTOR, f32(PATROL_MAX_SPEED_SCALE))
		glfw.SetWindowTitle(window, build_window_title())
	}
	if key == glfw.KEY_COMMA && action == glfw.PRESS {
		animation_speed_scale = max(animation_speed_scale/PATROL_SPEED_STEP_FACTOR, f32(PATROL_MIN_SPEED_SCALE))
		glfw.SetWindowTitle(window, build_window_title())
	}

	if key == glfw.KEY_LEFT_BRACKET && action == glfw.PRESS {
		select_prev_requested = true
	}
	if key == glfw.KEY_RIGHT_BRACKET && action == glfw.PRESS {
		select_next_requested = true
	}
	if key == glfw.KEY_J && (action == glfw.PRESS || action == glfw.REPEAT) {
		pending_translate_delta.x -= BASE_TRANSLATE_STEP * edit_step_scale
	}
	if key == glfw.KEY_L && (action == glfw.PRESS || action == glfw.REPEAT) {
		pending_translate_delta.x += BASE_TRANSLATE_STEP * edit_step_scale
	}
	if key == glfw.KEY_I && (action == glfw.PRESS || action == glfw.REPEAT) {
		pending_translate_delta.z -= BASE_TRANSLATE_STEP * edit_step_scale
	}
	if key == glfw.KEY_K && (action == glfw.PRESS || action == glfw.REPEAT) {
		pending_translate_delta.z += BASE_TRANSLATE_STEP * edit_step_scale
	}
	if key == glfw.KEY_U && (action == glfw.PRESS || action == glfw.REPEAT) {
		pending_translate_delta.y += BASE_TRANSLATE_STEP * edit_step_scale
	}
	if key == glfw.KEY_O && (action == glfw.PRESS || action == glfw.REPEAT) {
		pending_translate_delta.y -= BASE_TRANSLATE_STEP * edit_step_scale
	}
	// 4/5/6/7/8/9 = yaw-/yaw+/pitch-/pitch+/roll-/roll+ (local axes).
	rotate_step := math.to_radians(f32(BASE_ROTATE_STEP_DEGREES)) * edit_step_scale
	if key == glfw.KEY_4 && (action == glfw.PRESS || action == glfw.REPEAT) {
		pending_rotate_delta.y -= rotate_step
	}
	if key == glfw.KEY_5 && (action == glfw.PRESS || action == glfw.REPEAT) {
		pending_rotate_delta.y += rotate_step
	}
	if key == glfw.KEY_6 && (action == glfw.PRESS || action == glfw.REPEAT) {
		pending_rotate_delta.x -= rotate_step
	}
	if key == glfw.KEY_7 && (action == glfw.PRESS || action == glfw.REPEAT) {
		pending_rotate_delta.x += rotate_step
	}
	if key == glfw.KEY_8 && (action == glfw.PRESS || action == glfw.REPEAT) {
		pending_rotate_delta.z -= rotate_step
	}
	if key == glfw.KEY_9 && (action == glfw.PRESS || action == glfw.REPEAT) {
		pending_rotate_delta.z += rotate_step
	}
	if key == glfw.KEY_APOSTROPHE && action == glfw.PRESS {
		edit_step_scale = min(edit_step_scale*EDIT_STEP_FACTOR, f32(EDIT_STEP_MAX_SCALE))
		fmt.printfln("Edit step scale: %.2fx", edit_step_scale)
	}
	if key == glfw.KEY_SEMICOLON && action == glfw.PRESS {
		edit_step_scale = max(edit_step_scale/EDIT_STEP_FACTOR, f32(EDIT_STEP_MIN_SCALE))
		fmt.printfln("Edit step scale: %.2fx", edit_step_scale)
	}
	if key == glfw.KEY_0 && action == glfw.PRESS {
		if mods & glfw.MOD_SHIFT != 0 {
			reset_all_requested = true
		} else {
			reset_selected_requested = true
		}
	}
	if key == glfw.KEY_H && action == glfw.PRESS {
		Print_Controls()
	}
	// [PROGRESS-DEMO] Branch-only: R (ray-traced reflection toggle) and
	// M/V/Y/T/`/` (the polish-pass toggles: tonemapping, vignette, fog,
	// ground detail, sky) removed — see this proc's own comment above
	// for why (every one was already a silent no-op under
	// u_ObjectsOnlyMode).
}

mouse_button_callback :: proc "c" (window: glfw.WindowHandle, button, action, mods: i32) {
	if button == glfw.MOUSE_BUTTON_LEFT && action == glfw.PRESS {
		pick_requested = true
	}
}

// [PROGRESS-DEMO] Branch-only: dropped every toggle segment that no
// longer has a live key to change it (shading mode, cull, depth test,
// back-face debug, depth visualisation, tonemapping, vignette, fog,
// ground detail, sky — see key_callback's own comment) — showing a
// fixed value with no way to change it would just be more of the same
// title-bar-implies-something-you-can't-actually-do inconsistency this
// pass removes. Wire stays: F still genuinely toggles it.
build_window_title :: proc() -> cstring {
	wireframe_state := "On" if wireframe_enabled else "Off"
	paused_suffix := " [Paused]" if animation_paused else ""
	selection_suffix := fmt.tprintf(" Sel:%s", selected_node_name) if current_mode == .Inspection else ""

	return fmt.ctprintf(
		"SENTINEL - %s%s | Speed:%.2fx Wire:%s FPS:%.0f%s",
		MODE_NAME[current_mode],
		paused_suffix,
		animation_speed_scale,
		wireframe_state,
		fps_display_value,
		selection_suffix,
	)
}

apply_render_state :: proc() {
	switch cull_mode {
	case CULL_OFF:
		gl.Disable(gl.CULL_FACE)
	case CULL_MANUAL:
		gl.Disable(gl.CULL_FACE)
	case CULL_GL:
		gl.Enable(gl.CULL_FACE)
		gl.CullFace(gl.BACK)
		gl.FrontFace(gl.CCW) // CCW = front, matches Geometry generators.
	}
	dbg.GL_Check()

	if depth_test_enabled {
		gl.Enable(gl.DEPTH_TEST)
	} else {
		gl.Disable(gl.DEPTH_TEST)
	}
	dbg.GL_Check()

	if wireframe_enabled {
		gl.PolygonMode(gl.FRONT_AND_BACK, gl.LINE)
	} else {
		gl.PolygonMode(gl.FRONT_AND_BACK, gl.FILL)
	}
	dbg.GL_Check()
}

count_total_triangles :: proc(scene: ^scenepkg.Hierarchy, ground_mesh: ^geo.Mesh) -> int {
	total := len(ground_mesh.Indices) / 3
	for node in scene.Nodes {
		total += len(node.Mesh.Indices) / 3
	}
	return total
}

count_back_facing_triangles :: proc(mesh: ^geo.Mesh, normal_matrix: la.Matrix3f32, view_direction: la.Vector3f32) -> int {
	count := 0
	for i := 0; i < len(mesh.Indices); i += 3 {
		local_normal := mesh.Vertices[mesh.Indices[i]].Normal
		world_normal := la.normalize(la.mul(normal_matrix, local_normal))
		if la.dot(world_normal, view_direction) < 0 do count += 1
	}
	return count
}

// [PROGRESS-DEMO] Branch-only: find_light_by_parent removed — see
// PROGRESS-DEMO notes throughout this file.

// Grid of Plane cells stitched via Append_Mesh; more cells = better Gouraud sampling.
build_ground_mesh :: proc(resolution: int) -> geo.Mesh {
	mesh := geo.Empty_Mesh()

	cell_size := GROUND_SIZE / f32(resolution)
	cell := geo.Plane(cell_size, cell_size)
	defer geo.Destroy(&cell)

	for row in 0 ..< resolution {
		for col in 0 ..< resolution {
			x := -GROUND_SIZE*0.5 + cell_size*(f32(col) + 0.5)
			y := -GROUND_SIZE*0.5 + cell_size*(f32(row) + 0.5)
			geo.Append_Mesh(&mesh, cell, la.matrix4_translate(la.Vector3f32{x, y, 0}))
		}
	}

	geo.Upload(&mesh)
	return mesh
}

scroll_callback :: proc "c" (window: glfw.WindowHandle, x_offset, y_offset: f64) {
	scroll_delta_y += f32(y_offset)
}

key_axis :: proc(window: glfw.WindowHandle, positive_key, negative_key: i32) -> f32 {
	axis: f32 = 0
	if glfw.GetKey(window, positive_key) == glfw.PRESS do axis += 1
	if glfw.GetKey(window, negative_key) == glfw.PRESS do axis -= 1
	return axis
}

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

parse_projection_flag :: proc(args: []string) -> cam.Projection_Mode {
	for i := 0; i < len(args); i += 1 {
		if args[i] != "--projection" do continue

		if i + 1 >= len(args) {
			fmt.eprintln("--projection requires one argument: <perspective|orthographic>")
			os.exit(1)
		}

		switch args[i + 1] {
		case "perspective":
			return .Perspective
		case "orthographic":
			return .Orthographic
		case:
			fmt.eprintfln("--projection: expected 'perspective' or 'orthographic', got '%s'", args[i + 1])
			os.exit(1)
		}
	}

	return .Perspective
}

// [PROGRESS-DEMO] Branch-only: parse_gizmos_flag/parse_area_samples_flag/
// parse_area_jitter_flag (all Library/Lights-derived) removed — see
// PROGRESS-DEMO notes throughout this file.

parse_shading_flag :: proc(args: []string) -> i32 {
	for i := 0; i < len(args); i += 1 {
		if args[i] != "--shading" do continue

		if i + 1 >= len(args) {
			fmt.eprintln("--shading requires one argument: <flat|gouraud|phong>")
			os.exit(1)
		}

		switch args[i + 1] {
		case "flat":
			return SHADING_FLAT
		case "gouraud":
			return SHADING_GOURAUD
		case "phong":
			return SHADING_PHONG
		case:
			fmt.eprintfln("--shading: expected 'flat', 'gouraud', or 'phong', got '%s'", args[i + 1])
			os.exit(1)
		}
	}

	return DEFAULT_SHADING_MODE
}

parse_ground_resolution_flag :: proc(args: []string) -> int {
	for i := 0; i < len(args); i += 1 {
		if args[i] != "--ground-resolution" do continue

		if i + 1 >= len(args) {
			fmt.eprintln("--ground-resolution requires one argument: <low|high>")
			os.exit(1)
		}

		switch args[i + 1] {
		case "low":
			return GROUND_GRID_LOW_RESOLUTION
		case "high":
			return GROUND_GRID_HIGH_RESOLUTION
		case:
			fmt.eprintfln("--ground-resolution: expected 'low' or 'high', got '%s'", args[i + 1])
			os.exit(1)
		}
	}

	return GROUND_GRID_LOW_RESOLUTION
}

parse_cull_flag :: proc(args: []string) -> i32 {
	for i := 0; i < len(args); i += 1 {
		if args[i] != "--cull" do continue

		if i + 1 >= len(args) {
			fmt.eprintln("--cull requires one argument: <off|manual|gl>")
			os.exit(1)
		}

		switch args[i + 1] {
		case "off":
			return CULL_OFF
		case "manual":
			return CULL_MANUAL
		case "gl":
			return CULL_GL
		case:
			fmt.eprintfln("--cull: expected 'off', 'manual', or 'gl', got '%s'", args[i + 1])
			os.exit(1)
		}
	}

	return DEFAULT_CULL_MODE
}

parse_depth_test_flag :: proc(args: []string) -> bool {
	for i := 0; i < len(args); i += 1 {
		if args[i] != "--depth-test" do continue

		if i + 1 >= len(args) {
			fmt.eprintln("--depth-test requires one argument: <on|off>")
			os.exit(1)
		}

		switch args[i + 1] {
		case "on":
			return true
		case "off":
			return false
		case:
			fmt.eprintfln("--depth-test: expected 'on' or 'off', got '%s'", args[i + 1])
			os.exit(1)
		}
	}

	return true
}

parse_wireframe_flag :: proc(args: []string) -> bool {
	for arg in args {
		if arg == "--wireframe" do return true
	}
	return false
}

parse_backface_debug_flag :: proc(args: []string) -> bool {
	for arg in args {
		if arg == "--backface-debug" do return true
	}
	return false
}

parse_depth_visualization_flag :: proc(args: []string) -> bool {
	for arg in args {
		if arg == "--depth-visualization" do return true
	}
	return false
}

parse_mode_flag :: proc(args: []string) -> Mode {
	for i := 0; i < len(args); i += 1 {
		if args[i] != "--mode" do continue

		if i + 1 >= len(args) {
			fmt.eprintln("--mode requires one argument: <patrol|inspection>")
			os.exit(1)
		}

		switch args[i + 1] {
		case "patrol":
			return .Patrol
		case "inspection":
			return .Inspection
		case:
			fmt.eprintfln("--mode: expected 'patrol' or 'inspection', got '%s'", args[i + 1])
			os.exit(1)
		}
	}

	return DEFAULT_MODE
}

parse_patrol_speed_flag :: proc(args: []string) -> f32 {
	for i := 0; i < len(args); i += 1 {
		if args[i] != "--patrol-speed" do continue

		if i + 1 >= len(args) {
			fmt.eprintln("--patrol-speed requires one argument: <scale>")
			os.exit(1)
		}

		parsed, ok := strconv.parse_f32(args[i + 1])
		if !ok || parsed <= 0 {
			fmt.eprintfln("--patrol-speed: expected a positive number, got '%s'", args[i + 1])
			os.exit(1)
		}

		return parsed
	}

	return DEFAULT_ANIMATION_SPEED_SCALE
}

// [PROGRESS-DEMO] Branch-only: parse_reflection_flag removed — see
// PROGRESS-DEMO notes throughout this file.

parse_tonemapping_flag :: proc(args: []string) -> bool {
	for i := 0; i < len(args); i += 1 {
		if args[i] != "--tonemapping" do continue

		if i + 1 >= len(args) {
			fmt.eprintln("--tonemapping requires one argument: <on|off>")
			os.exit(1)
		}

		switch args[i + 1] {
		case "on":
			return true
		case "off":
			return false
		case:
			fmt.eprintfln("--tonemapping: expected 'on' or 'off', got '%s'", args[i + 1])
			os.exit(1)
		}
	}

	return DEFAULT_TONEMAPPING_ENABLED
}

parse_vignette_flag :: proc(args: []string) -> bool {
	for i := 0; i < len(args); i += 1 {
		if args[i] != "--vignette" do continue

		if i + 1 >= len(args) {
			fmt.eprintln("--vignette requires one argument: <on|off>")
			os.exit(1)
		}

		switch args[i + 1] {
		case "on":
			return true
		case "off":
			return false
		case:
			fmt.eprintfln("--vignette: expected 'on' or 'off', got '%s'", args[i + 1])
			os.exit(1)
		}
	}

	return DEFAULT_VIGNETTE_ENABLED
}

parse_fog_flag :: proc(args: []string) -> bool {
	for i := 0; i < len(args); i += 1 {
		if args[i] != "--fog" do continue

		if i + 1 >= len(args) {
			fmt.eprintln("--fog requires one argument: <on|off>")
			os.exit(1)
		}

		switch args[i + 1] {
		case "on":
			return true
		case "off":
			return false
		case:
			fmt.eprintfln("--fog: expected 'on' or 'off', got '%s'", args[i + 1])
			os.exit(1)
		}
	}

	return DEFAULT_FOG_ENABLED
}

parse_ground_detail_flag :: proc(args: []string) -> bool {
	for i := 0; i < len(args); i += 1 {
		if args[i] != "--ground-detail" do continue

		if i + 1 >= len(args) {
			fmt.eprintln("--ground-detail requires one argument: <on|off>")
			os.exit(1)
		}

		switch args[i + 1] {
		case "on":
			return true
		case "off":
			return false
		case:
			fmt.eprintfln("--ground-detail: expected 'on' or 'off', got '%s'", args[i + 1])
			os.exit(1)
		}
	}

	return DEFAULT_GROUND_DETAIL_ENABLED
}

parse_sky_flag :: proc(args: []string) -> bool {
	for i := 0; i < len(args); i += 1 {
		if args[i] != "--sky" do continue

		if i + 1 >= len(args) {
			fmt.eprintln("--sky requires one argument: <on|off>")
			os.exit(1)
		}

		switch args[i + 1] {
		case "on":
			return true
		case "off":
			return false
		case:
			fmt.eprintfln("--sky: expected 'on' or 'off', got '%s'", args[i + 1])
			os.exit(1)
		}
	}

	return DEFAULT_SKY_ENABLED
}

parse_benchmark_flag :: proc(args: []string) -> (frames: int, requested: bool) {
	for i := 0; i < len(args); i += 1 {
		if args[i] != "--benchmark" do continue

		if i + 1 >= len(args) {
			fmt.eprintln("--benchmark requires one argument: <frames>")
			os.exit(1)
		}

		parsed_frames, ok := strconv.parse_int(args[i + 1])
		if !ok || parsed_frames <= BENCHMARK_WARMUP_FRAMES {
			fmt.eprintfln("--benchmark: expected an integer frame count > %d, got '%s'", BENCHMARK_WARMUP_FRAMES, args[i + 1])
			os.exit(1)
		}

		return parsed_frames, true
	}

	return 0, false
}

parse_msaa_flag :: proc(args: []string) -> i32 {
	for i := 0; i < len(args); i += 1 {
		if args[i] != "--msaa" do continue

		if i + 1 >= len(args) {
			fmt.eprintln("--msaa requires one argument: <sample count>")
			os.exit(1)
		}

		parsed_samples, ok := strconv.parse_int(args[i + 1])
		if !ok || parsed_samples <= 0 {
			fmt.eprintfln("--msaa: expected a positive integer sample count, got '%s'", args[i + 1])
			os.exit(1)
		}

		return i32(parsed_samples)
	}

	return 0
}

// [PROGRESS-DEMO] Branch-only: parse_test_inspection_flag is now unused
// (its only caller was removed along with --test-inspection); left
// defined but uncalled rather than deleted, to keep this a comment-only
// pass. See PROGRESS-DEMO notes throughout this file.
parse_test_inspection_flag :: proc(args: []string) -> (prefix: string, requested: bool) {
	for i := 0; i < len(args); i += 1 {
		if args[i] != "--test-inspection" do continue

		if i + 1 >= len(args) {
			fmt.eprintln("--test-inspection requires one argument: <path-prefix>")
			os.exit(1)
		}

		return args[i + 1], true
	}

	return "", false
}
