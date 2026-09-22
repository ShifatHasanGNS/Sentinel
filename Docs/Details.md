# SENTINEL — Technical Details

This document is the technical reference that used to live as extensive
inline comments throughout the source tree. On the `progress_objects`
branch those comments have been stripped down to at most one short line
each (or removed entirely) so the code reads cleanly for a progress
check — this file exists so nothing that was explained inline is
actually lost. It covers the complete workflow (startup, the main loop,
mode switching) and a per-file technical breakdown of every `.odin` file
and the shader, in the state they're in on this branch.

**Branch note:** `progress_objects` is a temporary build for a course
progress check that precedes the illumination-model section of the
syllabus. `Library/Lights/` and `Source/Reflection*.odin` (ray-traced
reflection) have been physically removed from this branch — moved to
`../Sentinel_hidden_docs_backup/`, not deleted — and every call site that
depended on them was removed from `Source/Main.odin`/`Source/Inspection.odin`,
each marked inline with a `[PROGRESS-DEMO]` comment. A
`u_ObjectsOnlyMode` shader uniform, forced on by
`Source/Main.odin`'s `DEFAULT_OBJECTS_ONLY_MODE`, additionally makes the
fragment shader short-circuit to a flat, unlit `u_BaseColor` before any
lighting/shading/reflection/polish code runs. On `main`, none of this
applies — the full renderer (lighting, ray-traced reflection, the polish
pass) is intact there. See `PROGRESS.md` (moved to the same backup
folder) for the complete session history.

---

## 1. Workflow overview

### 1.1 Startup sequence (`Source/Main.odin`, `main()`)

1. Parse all CLI flags (`--capture`, `--projection`, `--shading`,
   `--ground-resolution`, `--cull`, `--depth-test`, `--wireframe`,
   `--backface-debug`, `--depth-visualization`, `--mode`,
   `--patrol-speed`, `--tonemapping`, `--vignette`, `--fog`,
   `--ground-detail`, `--sky`, `--benchmark`, `--msaa`) into
   package-level state.
2. `glfw.Init()`; set GL 3.3 core/forward-compatible window hints; an
   optional `SAMPLES` hint if `--msaa` was passed.
3. Create the GLFW window with `build_window_title()` as its initial
   title; `glfw.MakeContextCurrent`; `SwapInterval(0 if do_benchmark else 1)`
   (vsync off only for a true unthrottled `--benchmark` run).
4. Register GLFW callbacks: `framebuffer_size_callback`, `key_callback`,
   `mouse_button_callback`, `scroll_callback`.
5. `gl.load_up_to(3, 3, ...)`; enable `GL_MULTISAMPLE` if MSAA was
   requested; print GPU vendor/renderer/GL/GLSL version strings.
6. Set the GL viewport from the framebuffer size.
7. `scenepkg.Build_Scene()` — builds the entire procedural scene
   hierarchy (all 9 objects, see §5 below) in one call.
8. Snapshot every node's `Local` transform into `original_transforms` —
   the rest pose the `0`/`Shift+0` reset keys restore.
9. Build the ground mesh (`build_ground_mesh`) and its static model
   matrix; build the sky-dome cube mesh (`geo.Cube(SKY_CUBE_SIZE, ...)`).
10. Print scene/render-toggle/triangle-count diagnostics to stdout.
11. Look up the fixed node indices Patrol Mode needs (floodlight head,
    radar dish, tank turret, both jeep headlights).
12. `Build_Selectable_Nodes` + a local-space AABB per selectable node
    (for Inspection Mode's mouse picking); print the control list.
13. Compile/link the shader (`sd.New(COMBINED_SHADER_PATH)` →
    `Shaders/Scene.glsl`).
14. Build the starting `Camera` (`cam.Camera_Looking_At`); apply
    `--projection orthographic` if requested.
15. Capture the mouse cursor (unless `--capture`); enter the main loop.

### 1.2 Main loop, per frame

1. `glfw.PollEvents()`; compute `dt_seconds`.
2. (Skipped entirely during a `--capture` run, for reproducibility) Poll
   cursor delta and WASD/QE keys, applied to the camera only in
   Inspection Mode; update the FPS title accumulator; apply a deferred
   projection toggle / scroll-zoom; handle a deferred mode switch (§1.3);
   apply or discard pending Inspection edit requests (select/translate/
   rotate/reset) depending on `current_mode`.
3. Rebuild the ground mesh if `G` was pressed
   (`ground_resolution_toggle_requested`).
4. Advance `animation_time` — a fixed `1/60` step during `--capture`
   (so a given frame number always lands at the same pose, regardless of
   real wall-clock time), real `dt_seconds` otherwise — unless paused.
5. If `current_mode == .Patrol`: set `camera.position/yaw/pitch` from
   `cam.Patrol_Camera_Pose`, and write the floodlight-head/radar-dish/
   turret/jeep-headlight nodes' `Local.Rotation` from
   `Source/Patrol.odin`'s pure formula functions.
6. `apply_render_state()` pushes the current cull/depth-test/wireframe
   toggles to GL; clear the framebuffer.
7. Recompute `view`/`projection` from the current camera and aspect
   ratio.
8. Handle a pending mouse pick in Inspection Mode
   (`Screen_Point_To_Ray` + `Pick_Node`).
9. `scenepkg.Compute_World_Matrices(&scene)` once for the whole frame;
   upload every per-frame uniform (§6.7 in the Main.odin section below).
10. Draw the sky dome (if `sky_enabled`) first, with culling and
    depth-write both off, then restore render state.
11. Draw the ground plane (`u_IsGround` uniform on for just that one
    call).
12. `draw_scene_nodes` — the ONE shared draw path for every scene node,
    used identically in both modes, with the Inspection-only highlight
    tint applied via a highlighted-node index (-1 in Patrol).
13. Handle `--capture`'s frame-count exit (saves a screenshot) and
    `--benchmark`'s accumulation/report/exit.
14. `glfw.SwapBuffers(window)`.

### 1.3 Mode switching (Patrol ↔ Inspection)

`current_mode: Mode` (`Mode.Patrol` / `Mode.Inspection`, the enum lives
in `Source/Patrol.odin`) gates only WHICH DRIVER writes the camera/node
transforms each frame — Patrol via pure formulas, Inspection via live
input — never which draw call runs; both modes call the exact same
`draw_scene_nodes` every frame. `Tab` sets `mode_switch_requested`; the
main loop then:

- Leaving Inspection for Patrol: calls `cam.Patrol_Nearest_Angle(camera.position)`
  to find the closest point on the circular patrol path from wherever
  the free camera currently is, and derives a `patrol_time_offset` so
  `Patrol_Camera_Pose` resumes from THAT point instead of jumping to
  wherever the shared clock's raw angle happens to be.
- Leaving Patrol for Inspection: no special handling needed — `camera`
  already holds Patrol's last-computed pose, so Inspection's free-fly
  simply continues from there.

Patrol's own animation writes (floodlight sweep, radar spin, turret
scan, jeep headlight dip) are gated to `current_mode == .Patrol`, so
switching to Inspection just STOPS writing them — they hold their last
value rather than resetting to a rest pose — while `animation_time`
itself keeps advancing in the background regardless of mode (only
`Space` pauses it).

---

## 2. `Library/Engine` — theme-agnostic OpenGL abstraction layer

Knows nothing about SENTINEL's own scene/objects; pure GL plumbing.

### `Library/Engine/Debugger/Debugger.odin`

**Purpose:** Wraps OpenGL's error-polling API into a panic-on-error
assertion, plus a `Here()` stdout marker for print-debugging.
**Key procedures:**

- `GL_Clear_Errors()` — drains the GL error queue via `gl.GetError()` in
  a loop until `gl.NO_ERROR`, discarding whatever it finds.
- `GL_Check(location := #caller_location)` — clears the queue, re-polls;
  if a real error was queued, formats it via `GL_Error` and
  `log.panicf`s, tagged with the CALLER's source location (via Odin's
  `#caller_location`) so the panic points at the actual `gl.Something()`
  call, not at `GL_Check` itself.
- `Here()` — prints a `"\n====== Here ======\n"` marker to stderr.
- `GL_Error(error_code) -> string` (file-private) — switches over the 7
  standard GL error enums, returning the spec's own descriptive text.
  **How it connects:** Every other `Library/Engine` package calls
  `dbg.GL_Check()` immediately after nearly every `gl.*` call
  (`gl.Foo(...); dbg.GL_Check()`) — the project's only GL error-checking
  mechanism.

### `Library/Engine/IndexBuffer/IndexBuffer.odin`

**Purpose:** Thin wrapper around one GL element/index buffer object (EBO).
**Key procedures:**

- `IndexBuffer { RendererID: u32, Count: int }`.
- `New(data: []u32) -> IndexBuffer` — generates + binds a buffer, uploads
  `data` via `gl.BufferData` (`gl.STATIC_DRAW`); `Count = len(data)`, so
  it can never drift from what was actually uploaded.
- `Delete`/`Bind`/`Unbind`, `GetCount(i_buffer) -> int`.
  **How it connects:** `Library/Engine/Renderer` binds it before every
  `gl.DrawElements`; `Library/Geometry`'s `Mesh` owns one internally
  (created during `Upload`).

### `Library/Engine/Renderer/Renderer.odin`

**Purpose:** Bundles one `VertexArray` + `IndexBuffer` + `Shader` triple
and issues its draw call; also owns the global `gl.Clear`.
**Key procedures:**

- `Renderer { VertexArray: ^va.VertexArray, IndexBuffer: ^ib.IndexBuffer, Shader: ^sd.Shader }`
  — three raw pointers, no ownership of its own.
- `New`/`Renew` — construct or re-point a `Renderer`.
- `Delete` — unbinds VAO+VBO then IndexBuffer/Shader (if set), deletes
  every GL object it still holds a non-nil pointer to.
- `Draw` — asserts all 3 fields non-nil (each its own message, so a
  missing one fails loudly instead of null-dereferencing later), binds
  VAO → IndexBuffer → Shader, then `gl.DrawElements(gl.TRIANGLES, ...)`.
- `Clear()` — `gl.Clear(COLOR_BUFFER_BIT | DEPTH_BUFFER_BIT)`.
  **How it connects:** A known limitation: `Draw` only ever binds exactly
  ONE triple per call, no per-object uniform support. In practice
  SENTINEL's real render loop bypasses this `Draw` entirely and calls
  `Library/Geometry`'s own `Draw(mesh, shader)` per node instead (which
  does its own VAO/EBO bind); only `Clear` sees real per-frame use.

### `Library/Engine/Shader/Shader.odin`

**Purpose:** Compiles a combined vertex+fragment GLSL source file (split
on `#shader vertex`/`#shader fragment` markers) into a linked GL
program, plus a full set of typed, location-caching uniform-upload procs.
**Key procedures:**

- `Shader { FilePath: string, RendererID: u32, UniformLocationCache: map[string]i32 }`.
- `New(shader_source_file_path) -> Shader` — resolves the path,
  `load_shaders_from` splits it into vertex/fragment source, each
  compiled by `compile_shader`, linked into one GL program (attach →
  link → validate → delete the now-linked-in shader objects). Returns a
  zero-value `Shader{}` (logged, not panicked) on a bad path.
- `Delete`/`Bind`/`Unbind`.
- `GetUniformLocation(shader, name, location) -> i32` — cache-checks
  first; on a miss calls `gl.GetUniformLocation`, warns if `-1` (unused
  uniform — GLSL may optimize it away), caches the result either way so
  a name is looked up at most once per `Shader`.
- `SetUniform` — an overloaded proc GROUP resolving by argument type to
  one of 11 concrete procs (`SetUniform1i32`..`4i32`, `1f32`..`4f32`,
  `Matrix2f32`..`4f32`). Every variant calls `Bind` first automatically.
  The matrix variants take `^la.Matrix{2,3,4}f32` and pass
  `la.to_ptr(mat)` with `transpose = false` — linalg matrices are
  column-major in memory, matching GLSL's own `mat4` exactly.
- `load_shaders_from` (file-private) — splits the combined file
  line-by-line on `#shader vertex`/`#shader fragment` markers into two
  `strings.Builder`s, capturing the file's one `#version` line once and
  prepending it to both (GLSL requires `#version` as the literal first
  line of each independently-compiled stage).
- `compile_shader(shader_type, shader_src) -> u32` (file-private) —
  creates/uploads/compiles a shader object, checks `COMPILE_STATUS`, and
  on failure reads+panics with the GL info log.
  **How it connects:** One shared `Shader` instance, built once from
  `Shaders/Scene.glsl` in `Source/Main.odin`. `Library/Scene`'s
  `Draw_Node` and `Library/Geometry`'s `Draw` both call `SetUniform`/`Bind`
  on it every frame.

### `Library/Engine/VertexArray/VertexArray.odin`

**Purpose:** Wraps a GL Vertex Array Object (VAO) and describes a
`VertexBuffer`'s memory layout to it.
**Key procedures:**

- `VertexArray { RendererID: u32 }`; `New`/`Delete`/`Bind`/`Unbind`.
- `AddBuffer(v_array, v_buffer, layout: ^VertexBufferLayout)` — binds
  VAO then VBO; for each `layout.Elements[i]`, calls
  `gl.VertexAttribPointer(u32(i), count, type, normalized, stride, offset)`
  - `gl.EnableVertexAttribArray(u32(i))`, advancing a running byte
    `offset` by each element's `size` — so attribute locations are
    assigned 0, 1, 2... in `Elements` order.
    **How it connects:** `Library/Geometry`'s `Mesh.Upload` creates one VAO,
    one VBO of `Vertex` structs, one layout (position + normal), and calls
    `AddBuffer` once to wire them together.

### `Library/Engine/VertexBuffer/VertexBuffer.odin`

**Purpose:** Thin wrapper around one GL array buffer (VBO) of raw vertex
data.
**Key procedures:**

- `VertexBuffer { RendererID: u32 }`.
- `New(data: []$T) -> VertexBuffer` — a generic proc (Odin's `$T`
  polymorphic parameter): binds `gl.ARRAY_BUFFER`, uploads via
  `gl.BufferData(..., len(data)*size_of(T), raw_data(data), gl.STATIC_DRAW)`
  — `T` inferred from the argument, so the byte-size math is always
  correct regardless of the struct/primitive type passed.
  **How it connects:** `Mesh.Upload` calls `vb.New(mesh.Vertices[:])` to
  upload interleaved position+normal data.

### `Library/Engine/VertexBufferLayout/VertexBufferLayout.odin`

**Purpose:** A CPU-side builder recording a sequence of vertex-attribute
descriptions plus the accumulated per-vertex stride, later fed straight
into `VertexArray.AddBuffer`'s `gl.VertexAttribPointer` calls.
**Key procedures:**

- `VertexBufferElement { type: int, count: int, normalized: bool, size: int }`
  (file-private).
- `VertexBufferLayout { Elements: [dynamic]VertexBufferElement, Stride: int }`.
- `Push(layout, element_type: typeid, count, normalized)` — switches on
  the Odin `typeid` (`i8`/`u8`/`i16`/`u16`/`i32`/`u32`/`f32`/`f64`),
  mapping each to its GL enum and byte width, appends the element, adds
  its size to the running `Stride`.
  **How it connects:** `Mesh.Upload` pushes one entry for `a_Position`
  (f32×3) and one for `a_Normal` (f32×3), matching the `Vertex` struct's
  two fields exactly.

---

## 3. `Library/Geometry` — procedural mesh generation

Theme-agnostic; restricted to the three base primitives CLAUDE.md
requires (Cube, Tetrahedron, Plane), plus the combining helper
everything else is built from.

### `Library/Geometry/Geometry.odin`

**Purpose:** Generates the three legally-allowed base primitives
procedurally at runtime, provides `Append_Mesh` as the sole mechanism
for building every other (composite/curved-looking) shape from
instances of those three, and wraps a `Mesh`'s GL upload/draw/destroy
lifecycle.

**Mesh/Vertex data layout:**

- `Vertex { Position: Vector3f32, Normal: Vector3f32 }` — no colour
  field (that lives in `Scene.Material`, applied at draw time).
- `Mesh { Vertices: [dynamic]Vertex, Indices: [dynamic]u32, vertex_buffer, index_buffer, vertex_array, layout, uploaded: bool }`
  — `uploaded` lets `Destroy` skip GL cleanup for a mesh only ever used
  as an `Append_Mesh` SOURCE (no GL context exists under `odin test`, so
  unconditional GL calls there would segfault through nil function
  pointers).

**Key procedures:**

- `Empty_Mesh() -> Mesh` — zero-value starting accumulator.
- `Cube(width, height, depth) -> Mesh` — full (not half) dimensions,
  centered on local origin. Loops over 3 axes × 2 signs (6 faces); each
  face walks a fixed `corner_signs := [4][2]f32{{-1,-1},{1,-1},{1,1},{-1,1}}`
  traversal across its own (u,v) tangent axes, scaled by `half`, appended
  via `append_quad`. 24 vertices (4 duplicated per face, for flat
  per-face normals), 12 triangles.
- `Tetrahedron(size) -> Mesh` — 4 corners = `{1,1,1}, {1,-1,-1}, {-1,1,-1}, {-1,-1,1}} * (size*0.5)`
  — 4 alternating corners of a cube (the standard regular-tetrahedron-
  inside-a-cube parametrization). `face := [4][3]int{{1,2,3},{0,2,3},{0,1,3},{0,1,2}}`
  — row i lists the 3 corners of the face NOT touching corner i;
  winding is auto-corrected, so row order is arbitrary. 12 vertices, 4
  triangles.
- `Plane(width, height) -> Mesh` — single quad in the local XY plane at
  z=0, FIXED normal `(0,0,1)`, corners at `(±half_width, ±half_height, 0)`.
  Does not use the auto-orientation helpers (see winding convention
  below). 4 vertices, 2 triangles.
- `append_triangle`/`append_quad` (file-private) — compute the geometric
  normal via `cross(b-a, c-a)`, then check `dot(normal, centroid - inward_reference)`:
  if negative, reverse order (or flip the normal, for the quad case) so
  the stored normal always points away from `inward_reference`
  (`{0,0,0}` for both Cube and Tetrahedron, since both center on their
  own local origin). `append_quad` appends exactly 4 vertices + 2
  triangles' worth of indices (not 6 vertices via two independent
  `append_triangle` calls) — why Cube has 24 vertices, not 36.
- `Append_Mesh(dst, src, transform)` — copies every `src` vertex into
  `dst`, transforming position via the homogeneous 4×4 `transform` and
  normal via its inverse-transpose normal matrix (correct under
  non-uniform scale, e.g. a tapered instance). Indices copied with a
  `base_index` offset so a second instance references its own copied
  vertices, never the first instance's.
- `Smooth_Cylinder_Normals(mesh, axis_point, axis_direction)` —
  overwrites every vertex's normal with the analytically-correct
  outward radial direction around a local axis
  (`offset - dot(offset,axis)*axis`, normalized). A per-vertex FORMULA,
  not neighbour-averaging — deliberately, since this project's ring
  segments (built in `Library/Scene/Objects.odin`) intentionally overlap
  slightly and don't share exact seam vertices a welding pass would
  need. Must run on a ring's own LOCAL vertex data before `Append_Mesh`
  composes it into a larger whole. A vertex exactly on the axis (radial
  length < 1e-5) keeps its existing normal.
- `Upload(mesh)` — creates GL VBO/EBO/VAO via `Library/Engine`, 2-attribute
  layout (`a_Position` loc 0, `a_Normal` loc 1); sets `uploaded = true`.
- `Draw(mesh, shader)` — builds a transient `Renderer`, issues one draw
  call. Never deletes the shared `Shader` (owned/deleted exactly once by
  `Source/Main.odin`).
- `Destroy(mesh)` — always frees CPU arrays; only touches GL buffers if
  `uploaded`.

**Winding/normal convention stated here:** CCW (counter-clockwise, viewed
from outside/in front of a face) = front-facing. Enforced automatically
for Cube/Tetrahedron by the `inward_reference` auto-orientation (never
hand-derived per face). Plane is the one exception: a flat, zero-volume
quad's centroid sits exactly ON its own plane, so "points away from an
interior reference" is undefined for it — Plane's CCW-from-+Z winding is
instead a fixed, directly-chosen convention, cross-checked in the test
file the same way (geometric normal from winding must match stored
normal), just without the auto-orientation step.

**Append_Mesh / composition mechanism:** `Append_Mesh` is the ONLY way a
composite/curved-looking shape comes into existence anywhere in the
project. Callers (`Library/Scene/Objects.odin`, not this file) loop at
runtime, compute a fresh transform per instance (e.g. a rotation matrix
per ring segment for a "cylinder," a taper+rotation for a "cone"), and
call `Append_Mesh` once per instance into a growing destination `Mesh` —
never a stored/cached list of positions.

**How it connects to the rest of the project:** `Library/Scene/Objects.odin`
calls `Cube`/`Tetrahedron`/`Plane` + `Append_Mesh` (and occasionally
`Smooth_Cylinder_Normals`) in runtime loops to build all 9 SENTINEL
objects and every non-primitive shape from them. `Library/Scene/Transform.odin`'s
`Draw_Node` calls `Draw` per node each frame. `Source/Main.odin` calls
`Upload`/`Destroy` for the ground mesh and the sky dome. Zero knowledge
of SENTINEL-specific object names — fully theme-agnostic.

### `Library/Geometry/Geometry_test.odin`

**Purpose:** Verifies winding/normal correctness and `Append_Mesh`'s
transform behaviour for every generator (`odin test Library/Geometry`).
**What it verifies:**

- Cube: triangle normals match their own geometric winding; all normals
  point outward from `{0,0,0}`; exactly 24 vertices / 36 indices; face
  extents match the given width/height/depth exactly.
- Tetrahedron: same winding/outward checks; exactly 12 vertices / 12
  indices.
- Plane: winding check; every normal is exactly `(0,0,1)` (checked
  directly, since a flat plane has no well-defined interior); exactly 4
  vertices / 6 indices.
- `Append_Mesh`: identity transform preserves positions/normals exactly;
  two appended instances get correctly-offset indices (never aliasing
  back into the first instance); a translation shifts every position by
  exactly that offset; a non-uniform in-plane scale on a Plane leaves
  its already-perpendicular normal unchanged (confirms the
  inverse-transpose normal matrix is genuinely used, not a naive
  same-as-position transform); a +90° rotation about +Y sends a
  `(0,0,1)` normal to `(1,0,0)` (matches `Library/Camera/Camera_test.odin`'s
  rotation-direction convention).
- Shared private helpers: `expect_winding_matches_normals`,
  `expect_normals_point_outward`, `expect_vector3_near` (component-wise,
  `EPSILON = 1e-4`).

---

## 4. `Library/Camera` — free-fly camera, projections, Patrol path

### `Library/Camera/Camera.odin`

**Purpose:** Free-fly camera (Inspection Mode), perspective/orthographic
projection matrices, and a formula-driven Patrol Mode path — everything
needed to build a view + projection matrix each frame, with zero GLFW
dependency (unit-testable without a window/GL context).

**Key types/constants:**

- `Camera { position, yaw, pitch (radians), fov_y, near, far, projection (enum), ortho_half_height, move_speed, sprint_multiplier, look_sensitivity }`.
- `Projection_Mode` enum — `.Perspective` / `.Orthographic`.
- `WORLD_UP = (0,1,0)`.
- `PITCH_LIMIT_RADIANS = 89°` — exactly 90° would make `Right()`
  (`cross(Forward, WORLD_UP)`) degenerate since Forward and WORLD_UP
  become parallel.
- `MIN_ORTHO_HALF_HEIGHT = 0.1` — floor so the ortho volume can't
  collapse to a singular matrix.
- `ORTHO_ZOOM_FACTOR_PER_SCROLL_STEP = 0.9`.
- `DEFAULT_*` — starting lens/movement (FOV 45°, near 0.1, far 100,
  ortho half-height 5, move speed 4 u/s, sprint ×3, look sensitivity
  0.0025 rad/px).
- Patrol constants: `PATROL_RADIUS = 24` (clears the 28×28 perimeter
  fence's worst-case corner distance, 14·√2 ≈ 19.8); `PATROL_HEIGHT = 9`,
  bob amplitude 1.2 at rate 0.3 rad/s; `PATROL_ANGULAR_SPEED = 0.0698 rad/s`
  (2π/90s, one lap ≈ 90s); look-target drift radius 2.5 with independent
  X/Z drift rates 0.11 / 0.077 rad/s (non-integer ratio so the drift path
  never closes/repeats).

**Key procedures:**

- `Default_Camera(position) -> Camera` — facing -Z, default lens/move params.
- `Camera_Looking_At(position, target) -> Camera` — solves starting
  yaw/pitch via `yaw_pitch_looking_at`.
- `yaw_pitch_looking_at` (file-private) — closed-form inverse of
  `Forward`: `pitch = asin(clamp(dir.y,-1,1))`, `yaw = atan2(-dir.x, -dir.z)`.
- `Forward(cam) -> Vector3f32` — closed form of `R_y(yaw)*R_x(pitch)*(0,0,-1)`;
  already unit length by construction.
- `Right`/`Up` — `normalize(cross(Forward, WORLD_UP))` / `cross(Right, Forward)`.
- `View_Matrix(cam) -> Matrix4f32` — `la.matrix4_look_at(position, position+Forward, WORLD_UP)`,
  rebuilt fresh every call.
- `Projection_Matrix(cam, aspect) -> Matrix4f32` — perspective or
  orthographic depending on `cam.projection`; ortho half-width =
  `ortho_half_height * aspect`.
- `Apply_Look_Delta(cam, dx, dy)` — `yaw -= dx*sensitivity`,
  `pitch -= dy*sensitivity` (both negated: dx because +yaw turns the
  camera toward -X/left, so a rightward mouse move must DECREASE yaw;
  dy because GLFW's cursor Y grows downward), then clamps pitch.
- `Apply_Move(cam, move_forward, move_right, move_up, dt, sprint)` —
  combines Forward/Right/WORLD_UP by the three inputs (expected in
  [-1,1]), re-normalizes so diagonal movement isn't faster, scales by
  `move_speed` (×sprint_multiplier) and `dt`.
- `Toggle_Projection(cam, focus)` — Perspective→Orthographic sets
  `ortho_half_height = distance(cam,focus) * tan(fov_y/2)` so the ortho
  volume matches the perspective framing at the moment of the switch;
  the reverse direction needs no sync.
- `Zoom_Ortho(cam, scroll_delta_y)` — `ortho_half_height *= ZOOM_FACTOR^scroll_delta_y`,
  clamped to `MIN_ORTHO_HALF_HEIGHT`.
- `Patrol_Path_Position(angle) -> Vector3f32` — `(RADIUS*cos, 0, RADIUS*sin)`,
  a plain circle (a superellipse was tried and rejected: infinite
  derivative at its 4 axis crossings caused visible snapping).
- `Patrol_Look_Target(time_seconds) -> Vector3f32` — slowly drifting
  point near the origin.
- `Patrol_Camera_Pose(time_seconds) -> (position, yaw, pitch)` —
  converts time to path angle, adds a sine height-bob, solves yaw/pitch
  to look at `Patrol_Look_Target`. Returns only these 3 fields (not a
  full `Camera`) so a caller can copy them into a live camera without
  clobbering its projection/lens/speed state.
- `Patrol_Nearest_Angle(world_position) -> f32` — `atan2(z, x)`; EXACT
  (not approximate), since for a circle centred at the origin the
  nearest point to any external position lies exactly on the ray from
  the centre through that position.

**Conventions established here:** Right-handed, +X right, +Y up, camera
looks down -Z in view space (linalg's `flip_z_axis = true` default,
never overridden). Vectors are columns, transformed on the right
(`la.mul(M, p)`); composing reads right-to-left in code. `Matrix4f32` is
column-major in memory, matching GLSL's `mat4` exactly (confirmed via
`la.to_ptr`, so `SetUniformMatrix4f32` never needs `transpose = true`).
All angle STATE is radians; degrees only at human-facing edges. Rotation
follows the right-hand rule (+X rotated +90° about +Y → -Z). Clip-space
NDC z is `[-1,+1]` for both projections (OpenGL's traditional range, not
D3D's `[0,1]`), since `gl.ClipControl` is never called.

**How it connects to the rest of the project:** `Source/Main.odin` owns
the actual GLFW input polling and calls `Apply_Move`/`Apply_Look_Delta`/
`Toggle_Projection`/`Zoom_Ortho` each frame, and `View_Matrix`/
`Projection_Matrix` to build the MVP. `Source/Patrol.odin`/`Main.odin`'s
Patrol branch call `Patrol_Camera_Pose`/`Patrol_Nearest_Angle`. Depends
only on `core:math`/`core:math/linalg` — no GLFW, Scene, or Lights
knowledge.

### `Library/Camera/Camera_test.odin`

**Purpose:** `odin test Library/Camera` — confidence checks on how this
project USES `core:math/linalg` (empirically, not assumed from docs)
plus correctness tests for every proc above.
**What it verifies:**

- Baseline linalg sanity: identity matrix neutral, 4×4 multiply
  associative, `matrix4_inverse` round-trips to identity, `normalize`
  produces unit length.
- Rotation direction: (1,0,0) rotated +90° about (0,1,0) lands on
  (0,0,-1) — the right-hand-rule convention `Forward`'s derivation
  depends on.
- `View_Matrix` places a straight-ahead point on view-space -Z (camera
  at origin, yaw=pitch=0).
- `Forward` at yaw=90° faces -X.
- Perspective and orthographic `Projection_Matrix` both map near→NDC
  z=-1, far→NDC z=+1.
- Orthographic has no foreshortening: two points at the same world X but
  different depths land at the same NDC x.
- `Apply_Look_Delta` sign convention and pitch clamping under an extreme
  input.
- `Apply_Move`: forward/right axis movement lands at the expected
  position, sprint multiplies distance ×3, zero input is a true no-op.
- `Toggle_Projection` syncs `ortho_half_height` correctly (fov_y=90° for
  an easy tan(45°)=1 expected value) and flips the enum both directions.
- `Zoom_Ortho` shrinks on a positive scroll step, clamps at
  `MIN_ORTHO_HALF_HEIGHT`.
- Patrol: `Patrol_Path_Position` stays exactly `PATROL_RADIUS` from the
  origin at 5 test angles; `Patrol_Nearest_Angle` round-trips through
  `Patrol_Path_Position`; `Patrol_Camera_Pose`'s height is exactly
  `PATROL_HEIGHT` at t=0 and stays within bob amplitude at an arbitrary
  t; its returned yaw/pitch, reconstructed into a `Forward` vector,
  actually points at `Patrol_Look_Target` at that same time.

---

## 5. `Library/Scene` — transform hierarchy + the 9 scene objects

SENTINEL-specific; built from `Library/Geometry`'s three primitives.

### `Library/Scene/Transform.odin`

**Purpose:** A hand-rolled scene-graph replacement — a flat array of
nodes with integer parent indices, local transforms, and a per-node
material — plus the world-matrix math and the shared draw call every
node goes through.

**Key types:**

- `Transform { Position: vec3, Rotation: vec3 (radians, Euler: X=pitch, Y=yaw, Z=roll), Scale: vec3 }`.
- `Material { BaseColor: vec3, SpecularStrength: f32, Shininess: f32, EmissionColor: vec3, Reflective: bool }`
  — `EmissionColor` is for self-lit parts (glass/beacons); `Reflective`
  marks a ray-traced-reflection surface (the feature reading it is
  removed on this branch — field is otherwise inert here).
- `Node { Name: string, Parent: int (NO_PARENT = -1 for root), Local: Transform, Mesh: geo.Mesh, Material }`.
- `Hierarchy { Nodes: [dynamic]Node }` — a FLAT array, not a tree of
  pointers: an index survives `append`-triggered reallocation, a
  pointer wouldn't.

**Key procedures:**

- `Identity_Transform() -> Transform` — Position (0,0,0), Rotation
  (0,0,0), Scale (1,1,1).
- `Local_Matrix(t) -> Matrix4f32` — `translate * (yaw * pitch * roll) * scale`;
  rotation order is yaw-outermost, pitch-middle, roll-innermost.
- `Add_Node(h, name, parent, local, mesh, material) -> int` — appends,
  returns the new index; asserts `parent` is `NO_PARENT` or an
  already-valid index (parents are always added before children by
  construction).
- `Compute_World_Matrices(h) -> [dynamic]Matrix4f32` — **the core
  algorithm**: one single top-down pass over `h.Nodes` in array order;
  `world[i] = Local_Matrix(node.Local)` if root, else
  `world[i] = world[node.Parent] * Local_Matrix(node.Local)`. Asserts
  `node.Parent < i`. Caller owns/deletes the result; meant to be
  recomputed fresh every frame, never cached across frames.
- `Find_Node(h, name) -> int` — linear scan by `Name`, `NO_PARENT` if
  not found.
- `World_Point(world_matrix, local_point) -> Vector3f32` — local point
  (w=1) to world space.
- `World_Position(world_matrix) -> Vector3f32` — `World_Point` at local
  (0,0,0); a node's own world origin.
- `World_Direction(world_matrix, local_direction) -> Vector3f32` — local
  direction (w=0, translation ignored).
- `Normal_Matrix(world_matrix) -> Matrix3f32` — inverse-transpose of the
  world matrix's upper-left 3×3, for correct normals under non-uniform
  scale.
- `Draw_Node(shader, view, projection, model, mesh, material)` — the
  ONE shared draw path: skips zero-index meshes; computes
  `Normal_Matrix(model)` and `MVP = projection*view*model` fresh (never
  cached); uploads `u_MVP`, `u_Model`, `u_NormalMatrix`, `u_BaseColor`,
  `u_SpecularStrength`, `u_Shininess`, `u_EmissionColor`,
  `u_IsReflectiveSurface`; calls `geo.Draw`.
- `Default_Material(base_color) -> Material` — SpecularStrength 0.25,
  Shininess 16, EmissionColor black.
- `Destroy(h)` — destroys every node's mesh, deletes `Nodes`.

**How it connects to the rest of the project:** `Library/Scene/Objects.odin`'s
`Build_Scene` populates a `Hierarchy` via `Add_Node`. `Source/Main.odin`'s
main loop calls `Compute_World_Matrices` once per frame, passed to
`draw_scene_nodes` (`Source/Inspection.odin`), which calls `Draw_Node`
per node. `Source/Inspection.odin`'s `Apply_Translate`/`Apply_Rotate`
mutate `Node.Local` directly; `Source/Patrol.odin`'s formulas write the
same `Local.Rotation` fields for automatic animation.

### `Library/Scene/Objects.odin`

**Purpose:** Builds all 9 SENTINEL scene objects — `Build_Scene() -> Hierarchy`
calls 9 `build_*` procedures, each constructing one object's geometry
procedurally and adding it (plus any child nodes) to the shared
hierarchy.

**Scene layout** (all 9 are root nodes at a fixed `*_POSITION` constant;
only 3 objects have child nodes):

| #   | Object                 | Root node             | Children                                                               | Notes                                                                                                                                                                       |
| --- | ---------------------- | --------------------- | ---------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Watchtower             | `"Watchtower"`        | `"Watchtower Floodlight Head"`                                         | 4 legs, platform, railing ring, 4-slab pyramid roof; head is a separate child so it can rotate independently in Patrol Mode                                                 |
| 2   | Perimeter fence + gate | `"Perimeter Fence"`   | `"Perimeter Gate"`                                                     | Full rectangular loop of posts+panels via a boundary-walk formula, with a gap left for the gate                                                                             |
| 3   | Armored jeep           | `"Jeep"`              | `"Jeep Windshield"`, `"Jeep Headlight Left"`, `"Jeep Headlight Right"` | Body/cabin/hood/4 wheels baked into root; windshield and both headlights are explicit children                                                                              |
| 4   | Sandbag bunker         | `"Sandbag Bunker"`    | none                                                                   | U-shaped 3-wall, 2-row stacked ring-sandbags, staggered per row                                                                                                             |
| 5   | Radar mast             | `"Radar Mast"`        | `"Radar Dish"`, `"Radar Beacon"`                                       | Dish tilted 35°; both dish and beacon are children for independent Patrol-Mode animation                                                                                    |
| 6   | Barracks hut           | `"Barracks Hut"`      | `"Barracks Window 1/2/3"`                                              | Box body + 2-slab wedge roof + door baked in; 3 windows on the back wall are children (area-light geometry)                                                                 |
| 7   | Cargo crate stack      | `"Cargo Crate Stack"` | none                                                                   | 6 crates, size/rotation/offset varied by a deterministic function of loop index `i`                                                                                         |
| 8   | Battle tank            | `"Tank Hull"`         | `"Tank Turret"` → `"Tank Barrel"`, `"Tank Periscope"`                  | **3-level chain**: Hull (root, glacis+headlights+treads+10 wheels baked in) → Turret (child, searchlight housing baked in) → Barrel and Periscope (both children of Turret) |
| 9   | Gun emplacement        | `"Gun Emplacement"`   | none                                                                   | Sandbag ring, 3-leg tripod, gun body+barrel, work-light post; deliberately no children, no articulation                                                                     |

**Composition technique used:** Two shared ring helpers do all the
"cylinder-like" composition, both using the box-ring-via-runtime-loop
technique CLAUDE.md §2 item 6 requires:

- `append_ring_y(dst, segment, count, radius, y_offset)` — sweeps
  `count` copies of a box `segment` around a circle of `radius` in the
  local XZ plane (rotation about Y), composed as
  `rotate(angle) * translate(radius, y_offset, 0)`. Used for: the
  watchtower's railing posts, the sandbag bunker's per-bag ring wall
  (each "sandbag" is itself a tiny box-ring), the radar dish's ring of
  flat segments, the gun emplacement's sandbag ring.
- `append_ring_x(dst, segment, count, radius, x_offset)` — same
  technique swept about X (for wheel rims, in the local YZ plane). Used
  for: jeep wheels (×4), tank road wheels (×10, 5 per side).
- Curved-looking rings (jeep/tank wheels, radar dish) additionally call
  `geo.Smooth_Cylinder_Normals` afterward to blend their per-segment
  flat normals into a smooth curve; everything else stays faceted.
- Angled flat panels (not full rings) use a single `geo.Cube` scaled
  thin and tilted with `matrix4_rotate(pitch, X-axis)`, pitch solved via
  `atan2(rise, run)` from two pinned edge points — used for the
  watchtower's 4 roof slabs (swept 90° apart, not a ring loop, since a
  square pyramid always has exactly 4 sides), the barracks' 2-slab wedge
  roof, the tank's glacis plate.
- The perimeter fence walks a rectangle boundary via
  `Fence_Post_Position(t)`, a formula over `t ∈ [0,1]` (exported for
  reuse), placing a post/panel pair per step rather than a stored path
  array.
- `append_translated(dst, segment, position)` is the trivial
  no-rotation case of `Append_Mesh`, used everywhere for single-instance
  placements (legs, hoods, doors, treads, etc.).

**Key procedures/constants:**

- `Build_Scene() -> Hierarchy` — calls all 9 `build_*` procs in order.
- `build_watchtower`, `build_perimeter_fence`, `build_jeep`,
  `build_bunker`, `build_radar`, `build_barracks`, `build_crate_stack`,
  `build_tank`, `build_gun_emplacement` — one per object; each builds a
  local `geo.Mesh` via `geo.Empty_Mesh()` + repeated `Append_Mesh`/
  `append_translated`/`append_ring_*` calls, `geo.Upload`s it, then
  `Add_Node`s it (and children) into `h`.
- `Fence_Post_Position(t) -> Vector3f32` (exported) — the fence
  boundary-walk formula.
- Position constants: `WATCHTOWER_POSITION`, `BARRACKS_POSITION`,
  `BUNKER_POSITION`, `GUN_EMPLACEMENT_POSITION`, `RADAR_POSITION`,
  `CRATE_STACK_POSITION`, `JEEP_POSITION`, `TANK_POSITION` — one
  hand-placed root position per object (allowed as a "small parameter,"
  not a banned position table, since each names a single unique object
  with no underlying placement formula).
- Dimension constants worth knowing: `FENCE_HALF_WIDTH`/`FENCE_HALF_DEPTH = 14`
  (the ~28×28 perimeter footprint every other object sits inside);
  `TOWER_HEIGHT = 5.0`; `TANK_HULL_SIZE`/`TANK_TURRET_SIZE`/
  `TANK_BARREL_LENGTH`; `BARRACKS_WINDOW_COUNT = 3`,
  `BARRACKS_WINDOW_WIDTH`/`HEIGHT`.
- Colour/material constants: `COLOR_*` (14 base colours) and
  `MATERIAL_GLASS`/`MATERIAL_FLOODLIGHT`/`MATERIAL_BEACON`/
  `MATERIAL_BARRACKS_WINDOW` (pre-built emissive `Material` values).

**How it connects to the rest of the project:** `Source/Main.odin` calls
`scenepkg.Build_Scene()` exactly once at startup to construct the live
`scene: scenepkg.Hierarchy`, which the main loop then reads/mutates
every frame for the rest of the program's life.

### `Library/Scene/Transform_test.odin`

**Purpose:** Hierarchy correctness checks (`odin test Library/Scene`) —
confirms `Compute_World_Matrices` composes parent/child transforms
correctly through multi-level chains.
**What it verifies:**

- A root node's world position equals its own local Position.
- A 3-level base→arm→tip chain (identity rotations) puts the tip at its
  local offset (2,0,0) in world space.
- **Central hierarchy test:** rotating only the middle node (`arm`) by
  +90° about Y carries the tip from local (2,0,0) to world (0,0,-2) —
  proves a child's world position correctly composes through an
  ancestor's rotation, the same bug class the tank hull→turret chain
  depends on being correct.
- Translating the root (`base`) by (5,0,0), on top of the arm's existing
  +90° rotation, moves the tip to (5,0,-2) — composition through more
  than one level at once.
- `World_Direction` on a node with both a large translation and a +90°
  Y rotation still returns the correctly-rotated direction with no
  translation leaking in.
- `Find_Node` returns the correct index for an existing name and
  `NO_PARENT` for a nonexistent one.

---

## 6. `Source/Main.odin` — application entry point

**Purpose:** The `package main` entry point. Owns the GLFW window and
OpenGL context, the single shared render loop used by both Patrol and
Inspection modes, all GLFW input callbacks, CLI flag parsing, and
per-frame uniform uploads to the one combined shader program. (Its
startup sequence, main loop, and mode-switching mechanism are covered in
full in §1 above — this section covers everything else.)

### 6.1 Key package-level state (globals)

- `current_mode: Mode`, `mode_switch_requested: bool`, `patrol_time_offset: f32`
- `animation_time: f32`, `animation_paused: bool`, `animation_speed_scale: f32`
  — the one shared clock driving all Patrol animation.
- `shading_mode: i32` (`SHADING_FLAT/GOURAUD/PHONG`), `cull_mode: i32`
  (`CULL_OFF/MANUAL/GL`), `depth_test_enabled`, `wireframe_enabled`,
  `backface_debug_enabled`, `depth_visualization_enabled: bool`.
- `tonemapping_enabled`, `vignette_enabled`, `fog_enabled`,
  `ground_detail_enabled`, `sky_enabled: bool` — polish-pass toggles,
  each still uploaded every frame regardless of `objects_only_mode`.
- `objects_only_mode: bool` — **[PROGRESS-DEMO]**, forced true via
  `DEFAULT_OBJECTS_ONLY_MODE`.
- `ground_resolution: int`, `ground_resolution_toggle_requested: bool`.
- `selected_index: int` (indexes into the local `selectable_nodes` list,
  NOT `scene.Nodes` directly), `selected_node_name: string`,
  `select_next_requested`/`select_prev_requested`/`pick_requested: bool`,
  `pending_translate_delta`/`pending_rotate_delta: la.Vector3f32`,
  `edit_step_scale: f32`, `reset_selected_requested`/`reset_all_requested: bool`.
- `projection_toggle_requested: bool`, `scroll_delta_y: f32`.
- `fps_display_value/accum_time/accum_frames`.

### 6.2 Input handling (`key_callback`)

| Key           | Effect                                                    |
| ------------- | --------------------------------------------------------- |
| Esc           | Close window                                              |
| P             | Toggle perspective/orthographic                           |
| 1/2/3         | Shading mode Flat/Gouraud/Phong                           |
| G             | Toggle ground grid resolution                             |
| C             | Cycle cull mode Off→Manual→GL                             |
| Z             | Toggle depth test                                         |
| X             | Toggle depth visualization                                |
| F             | Toggle wireframe                                          |
| B             | Toggle back-face debug tint                               |
| Tab           | Request mode switch                                       |
| Space         | Pause/resume animation clock                              |
| , / .         | Slow/speed animation clock                                |
| [ / ]         | Select prev/next (Inspection)                             |
| J/L, I/K, U/O | Translate local X-/X+, Z-/Z+, Y+/Y- (Inspection)          |
| 4/5, 6/7, 8/9 | Rotate yaw-/yaw+, pitch-/pitch+, roll-/roll+ (Inspection) |
| ' / ;         | Increase/decrease edit step scale                         |
| 0 / Shift+0   | Reset selected / reset all                                |
| H             | Print controls                                            |
| M/V/Y/T/`/`   | Toggle tonemapping/vignette/fog/ground-detail/sky         |

`mouse_button_callback` sets `pick_requested` on left-click;
`scroll_callback` accumulates `scroll_delta_y`.

### 6.3 CLI flags

`--capture <frames> <path>`, `--projection <perspective|orthographic>`,
`--shading <flat|gouraud|phong>`, `--ground-resolution <low|high>`,
`--cull <off|manual|gl>`, `--depth-test <on|off>`, `--wireframe`,
`--backface-debug`, `--depth-visualization`, `--mode <patrol|inspection>`,
`--patrol-speed <scale>`, `--tonemapping <on|off>`, `--vignette <on|off>`,
`--fog <on|off>`, `--ground-detail <on|off>`, `--sky <on|off>`,
`--benchmark <frames>`, `--msaa <N>`.

`--gizmos`, `--area-samples`, `--area-jitter`, `--reflection`,
`--test-inspection` were removed with their call sites — see §6.6.

### 6.4 Render-state toggles (`apply_render_state`)

- `cull_mode == CULL_OFF`: `gl.Disable(gl.CULL_FACE)`.
- `CULL_MANUAL`: `gl.Disable(gl.CULL_FACE)` (the shader does its own
  discard instead).
- `CULL_GL`: `gl.Enable(gl.CULL_FACE); gl.CullFace(gl.BACK); gl.FrontFace(gl.CCW)`.
- `depth_test_enabled`: `gl.Enable`/`Disable(gl.DEPTH_TEST)`.
- `wireframe_enabled`: `gl.PolygonMode(gl.FRONT_AND_BACK, gl.LINE`/`gl.FILL)`.

### 6.5 Uniforms uploaded per frame

`u_ViewPosition` (camera.position), `u_AmbientColor`/`u_AmbientStrength`
(constants), `u_ShadingMode`, `u_CullMode`, `u_ViewDirection`
(`cam.Forward`), `u_IsOrthographic`, `u_BackfaceDebug`,
`u_DepthVisualization`, `u_Near`/`u_Far`, `u_SkyColor` (=`CLEAR_COLOR`),
`u_ObjectsOnlyMode`, `u_TonemappingEnabled`, `u_VignetteEnabled`,
`u_Resolution` (framebuffer size), `u_FogEnabled`, `u_Time`
(=`animation_time`), `u_IsSky` (1 during the sky draw, then 0),
`u_IsGround` (1 during the ground draw, then 0).

### 6.6 [PROGRESS-DEMO] state on this branch

`objects_only_mode` forced true, making the shader short-circuit before
reading almost every other uniform. Physically REMOVED from this file
(not just bypassed): `Library/Lights` rig build/update/upload, light
gizmos (`L` key, `--gizmos`), area-light sample count/jitter (`+`/`-`/
`N`, `--area-samples`/`--area-jitter`), the beacon/fence-lamp intensity
animations, ray-traced reflection (`R` key, `--reflection`, proxy
build/upload), and the `--test-inspection` headless turret/searchlight
test. `parse_test_inspection_flag` is left defined but uncalled (dead
code, kept rather than deleted to keep this pass comment-only). Every
removal is marked inline with a `[PROGRESS-DEMO]` comment.

### 6.7 How it connects to the rest of the project

Imports `Library/Camera` (camera, projections, Patrol path math),
`Library/Geometry` (mesh generation/upload for ground and sky),
`Library/Scene` (hierarchy, `Build_Scene`, `Compute_World_Matrices`,
`Draw_Node`, `Default_Material`), `Library/Engine/Debugger` (`GL_Check`),
`Library/Engine/Shader` (`sd.New`/`SetUniform`/`Delete`), and `Debug`
(`capture.Save_Screenshot`). Calls into `Source/Patrol.odin` for `Mode`,
`MODE_NAME`, `Patrol_*_Angle` functions, and speed-scale constants; calls
into `Source/Inspection.odin` for `Build_Selectable_Nodes`,
`Compute_Local_AABB`, `Screen_Point_To_Ray`, `Pick_Node`,
`Apply_Translate`/`Apply_Rotate`/`Reset_Node`, `draw_scene_nodes`,
`Inspection_Highlight_Pulse`, `Print_Controls`, and the edit-step
constants.

---

## 7. `Source/Inspection.odin` — selection, picking, editing

**Purpose:** Implements Inspection Mode's core interactive features:
which scene nodes can be selected, mouse-ray picking against them,
translate/rotate editing of the selected node's transform, a pulsing
highlight tint on the selection, and the printed control list.

**Selectable nodes:** 12 total — the 9 root objects (in `Build_Scene`'s
order) plus 3 named sub-nodes: `"Tank Turret"`,
`"Watchtower Floodlight Head"`, `"Radar Dish"`
(`SELECTABLE_SUB_NODE_NAMES`). These three are singled out because
they're independently movable child nodes worth demonstrating hierarchy
on; other children (headlights, tank barrel/periscope, barracks
windows) are excluded as not independently interesting to edit.
`Build_Selectable_Nodes` builds this list once and panics loudly if a
named sub-node is missing (name/scene drift).

**Mouse picking mechanism:** Three-stage pipeline.

1. `Screen_Point_To_Ray(view, projection, ndc_x, ndc_y)` unprojects one
   NDC point through the inverse of `projection * view` at both the
   near clip plane (z=-1) and far clip plane (z=1), dividing each by
   its own `w`, then returns the world-space ray between them — correct
   for both perspective and orthographic without a special case, since
   it unprojects the actual near point rather than assuming a shared
   camera-position origin.
2. `Ray_Intersects_AABB` is the standard slab method: for each of the 3
   axes, compute the entry/exit `t` against that axis's min/max planes,
   shrink a running `[t_min, t_max]` interval; empty interval = no hit;
   returns the nearest non-negative `t`.
3. `Pick_Node` transforms the ray into each selectable node's LOCAL
   space (via that node's inverse world matrix — cheaper than
   transforming 8 box corners to world space) and returns the index of
   the nearest AABB hit, or -1.

Deliberate adaptation: the "cursor" fed into `Screen_Point_To_Ray` is
always the viewport CENTRE (NDC 0,0), not GLFW's live cursor position —
because Inspection's free-fly camera runs with `glfw.CURSOR_DISABLED`
for unbounded mouse-look, and GLFW documents that mode's reported cursor
position as a virtual accumulator, not a real on-screen pixel;
unprojecting it would pick whatever's under a meaningless number. A
"look at it, click to select it" crosshair pick uses the identical ray
math a true cursor-position pick would.

**Translate/rotate editing:** `Apply_Translate(scene, node_index, local_delta)`
adds to `scene.Nodes[node_index].Local.Position`; `Apply_Rotate` adds to
`.Local.Rotation`; `Reset_Node(scene, node_index, original)` overwrites
`.Local` with a saved `Transform`. All three mutate the node's LOCAL
transform, never world — because `Scene.Compute_World_Matrices`
recomposes `world = parent_world * local` every frame, so editing LOCAL
is sufficient for children (and, on `main`, attached lights) to follow
automatically with no extra propagation step.

**Selection highlight mechanism:** `Inspection_Highlight_Pulse(t)`
returns `0.5 + 0.5*sin(t * 3.0)` — a `[0,1]` breathing factor
(`INSPECTION_HIGHLIGHT_PULSE_RATE = 3.0` rad/s). `draw_scene_nodes`
draws every node in the scene; for the one node whose index equals
`highlighted_node` (or none, if -1), it adds `INSPECTION_HIGHLIGHT_COLOR`
(`{0.7, 1.0, 1.0}`, cyan) scaled by the pulse factor into a COPY of that
node's `Material.EmissionColor` before drawing — the stored material is
never mutated, no second render pass or outline mesh is used.

**Key procedures:**

- `Build_Selectable_Nodes(scene) -> [dynamic]int` — the 12-node list
  described above.
- `Compute_Local_AABB(mesh) -> AABB` — scans a mesh's local-space
  vertices once (at startup, not per frame) for min/max bounds per axis.
- `Print_Controls()` — prints the full key list to stdout (no in-app
  text rendering exists, so this plus the window title are the only
  readouts).

**[PROGRESS-DEMO] state on this branch:** The headless
`--test-inspection` test (`inspection_test_render_and_capture`,
`Run_Inspection_Test`) that used to live at the end of this file is
removed — its entire premise was verifying a LIGHT (the turret
searchlight) tracks the turret through the hierarchy, which depended on
`Library/Lights` (also removed on this branch). `Print_Controls` also
had its light-gizmo/area-light key lines removed.

**How it connects to the rest of the project:** `draw_scene_nodes` is
called once per frame, unconditionally, from `Source/Main.odin`'s main
loop (both modes share this one call). `Screen_Point_To_Ray`/
`Pick_Node` are called from `Main.odin`'s per-frame input handling when
a left-click is pending in Inspection Mode. `Apply_Translate`/
`Apply_Rotate`/`Reset_Node` are called from `Main.odin`'s key-driven
edit-delta accumulation. `Build_Selectable_Nodes`/`Compute_Local_AABB`
run once at startup in `Main.odin`.

### `Source/Inspection_test.odin`

**Purpose:** Unit tests for the ray/AABB picking math — the one piece of
Inspection Mode with no live interactive way to verify it (mouse
clicking needs an actual human) and no analytic cross-check otherwise.
**What it verifies:**

- `Ray_Intersects_AABB` hits a centered unit box at the expected
  distance (t≈4 for a ray at z=5 aimed at a box spanning z=[-1,1]).
- Correctly misses a box off to the side.
- Reports a non-negative `t` when the ray origin starts inside the box.
- Ignores a box entirely behind the ray's direction.
- `Screen_Point_To_Ray` at NDC (0,0) for a camera facing -Z produces a
  ray matching `Camera.Forward` at yaw=pitch=0, with a near-point origin
  on the camera's own forward axis.
- `Pick_Node` returns the NEARER of two boxes along one ray, not just
  any hit.
- `Pick_Node` returns -1 when the ray hits nothing.

---

## 8. `Source/Patrol.odin` — Patrol Mode's animation formulas

**Purpose:** Defines Patrol Mode's animation as pure, side-effect-free
formulas — every `Patrol_*` proc is `(time) -> (angle | factor)`,
reading nothing and mutating nothing. Also defines the app-level `Mode`
enum (`Patrol`/`Inspection`) `Source/Main.odin` switches on with Tab.
The Patrol CAMERA path itself (circle + height bob + drifting look
target) lives separately in `Library/Camera/Camera.odin` since it's
theme-agnostic math with no SENTINEL-specific node knowledge; this file
is deliberately the SENTINEL-specific counterpart (named node/light
animation).

**Mode enum:** `Mode :: enum { Patrol, Inspection }`, with
`MODE_NAME: [Mode]string` for display. Both modes draw through the same
render path; only what drives node/light transforms differs, so every
`Patrol_*` function's output is applied by `Main.odin`'s main loop only
while `current_mode == .Patrol`.

**Key procedures** (all `proc(t: f32) -> f32`, pure):

- `Patrol_Floodlight_Sweep_Angle(t)` = `sin(t * 0.5) * (50° in rad)` —
  sine sweep, rate 0.5 rad/s, ±50° amplitude. Drives the Watchtower
  Floodlight Head's Y rotation.
- `Patrol_Radar_Spin_Angle(t)` = `t * 0.35` — continuous linear rotation
  (not sine-bounded), 0.35 rad/s.
- `Patrol_Beacon_Intensity_Factor(t)` = `pow(max(sin(t * 1.2), 0), 4.0)`
  — one bright half-cycle then one fully-dark half-cycle per period,
  sharpened into a brief flash by the 4th power (a warning-beacon blink,
  not a smooth pulse).
- `Patrol_Turret_Scan_Angle(t)` = `sin(t * 0.15) * (25° in rad)` — sine
  sweep, rate 0.15 rad/s, ±25° amplitude, slower/narrower than the
  floodlight.
- `Patrol_Jeep_Dip_Angle(t)` = `(6° in rad) * (0.5 - 0.5*cos(t * 0.25))`
  — a raised-cosine, staying in [0,1] (unlike a plain sine's [-1,1]):
  rests level at 0, eases down to the full 6° dip, eases back to level,
  never tilts upward past level.
- `Patrol_Fence_Flicker_Factor(t)` = `1.0 + 0.15 * (0.6*sin(t*3.7) + 0.4*sin(t*8.3))`
  — a multiplier centred on 1.0, summing two sine terms at a
  non-integer frequency ratio (3.7:8.3 rad/s) for a semi-irregular
  flicker rather than one clean periodic pulse.

Speed-key bounds: `PATROL_MIN_SPEED_SCALE = 0.1`,
`PATROL_MAX_SPEED_SCALE = 8.0`, `PATROL_SPEED_STEP_FACTOR = 1.25`
(multiplicative per `,`/`.` press).

**[PROGRESS-DEMO] state on this branch:** `Patrol_Beacon_Intensity_Factor`
and `Patrol_Fence_Flicker_Factor` are now unused dead code — their only
caller (`Main.odin`'s per-frame Patrol block, writing into
`light_rig[...].Intensity`) was removed along with `Library/Lights`.
Both procs are left intact (not deleted) and marked with a one-line
`[PROGRESS-DEMO]` comment noting they're orphaned. The 4 remaining procs
(floodlight sweep, radar spin, turret scan, jeep dip) are still actively
called — they drive node ROTATIONS, not light intensities, so they're
unaffected by the Lights removal.

**How it connects to the rest of the project:** `Source/Main.odin`'s
main loop, inside its `if current_mode == .Patrol` block, calls each
`Patrol_*` proc with the shared `animation_time` clock and writes the
result directly into `scene.Nodes[...].Local.Rotation` — this file only
computes values, `Main.odin` is the sole place that mutates state with
them.

---

## 9. `Shaders/Scene.glsl` — the combined vertex+fragment shader

**Purpose:** SENTINEL's single combined vertex+fragment shader source,
compiled/linked by `Library/Engine/Shader.New` from one file split on
`#shader vertex`/`#shader fragment` markers. Implements the full
rasterization lighting pipeline (Blinn-Phong over 4 light types, 3
shading modes), plus back-face-culling and depth-visualisation debug
views, ray-traced reflection off analytic proxy shapes, and a "polish
pass" (fog/vignette/tonemap/procedural ground detail/procedural sky).

**Structure:** Two stages compiled separately (GLSL has no `#include`),
so the `Light` struct, `light_contribution`, `area_light_contribution`,
`hash21`, and `compute_lighting` are each written out TWICE, byte-for-
byte identical except one line. This is deliberate, not copy-paste
drift: Flat/Gouraud shading needs the full lighting result evaluated
once PER VERTEX (vertex-stage copy), while Phong needs it evaluated once
PER FRAGMENT (fragment-stage copy) — the same function genuinely has to
live in both places since each stage runs on different hardware and
can't call into the other.

**Vertex stage:**

- Inputs: `layout(location=0) a_Position`, `layout(location=1) a_Normal`.
- Uniforms read: `u_MVP`, `u_Model`, `u_NormalMatrix`, `u_ShadingMode`,
  `u_BaseColor`/`u_SpecularStrength`/`u_Shininess`/`u_EmissionColor`,
  plus the full lighting-uniform set (`u_Lights[32]`,
  `u_ActiveLightCount`, `u_AreaLightSampleCount`, `u_AreaLightJitter`,
  `u_AmbientColor`, `u_AmbientStrength`, `u_ViewPosition`).
- Outputs/varyings: `v_WorldPosition`, `v_WorldNormal`,
  `flat out vec3 v_FlatColor` (provoking-vertex only),
  `out vec3 v_GouraudColor` (smooth-interpolated).
- `main()`: computes `gl_Position`, `v_WorldPosition`, `v_WorldNormal`
  (normalized `u_NormalMatrix * a_Normal`) always. If
  `u_ShadingMode != SHADING_PHONG`, calls `compute_lighting` once and
  writes the result into BOTH `v_FlatColor` and `v_GouraudColor` (the
  rasterizer's `flat`/smooth interpolation qualifiers are what actually
  differentiate Flat vs Gouraud on the fragment side); otherwise writes
  `vec3(0.0)` to both (Phong ignores them entirely).

**Fragment stage — `main()` control flow, in order:**

1. `u_ObjectsOnlyMode` early-return → `FragColor = vec4(u_BaseColor, 1.0); return;`
   ([PROGRESS-DEMO], branch-only).
2. `u_DepthVisualization` early-return → grayscale linearised depth,
   `return`.
3. `u_IsSky` early-return → `sky_color()` + optional vignette/tonemap,
   `return`.
4. Back-face classification (`is_back_facing`) + `u_CullMode == CULL_MANUAL`
   discard.
5. Shading-mode branch: `SHADING_FLAT` → `v_FlatColor`; `SHADING_GOURAUD`
   → `v_GouraudColor`; else → `compute_lighting(...)`.
6. `u_IsReflectiveSurface && u_RayTracedReflectionEnabled` → Fresnel-
   blend the `trace_reflection` result into `result`.
7. `u_BackfaceDebug && is_back_facing` → override `result` to magenta.
8. Polish-pass tail, fixed order: `apply_ground_detail` (if
   `u_IsGround`) → `apply_fog` (if `u_FogEnabled`) → `apply_vignette`
   (if `u_VignetteEnabled`) → `apply_tonemap_gamma` (if
   `u_TonemappingEnabled`).
9. `FragColor = vec4(result, 1.0)`.

**Lighting model (`compute_lighting`):**
`ambient = u_AmbientStrength * u_AmbientColor * base_color` (one global
fill term, independent of light count, not summed per-light) + `lit`
(sum of every enabled light's `light_contribution`/
`area_light_contribution`) + `emission_color` (added unconditionally, no
light dependency — self-illuminating materials like windows/beacons).
Specular is Blinn-Phong: `half_vector = normalize(to_light + view_direction)`,
`specular_factor = pow(max(dot(normal, half_vector), 0), shininess)`;
specular is tinted by the LIGHT's colour, not the surface's own base
colour.

**Light types handled (`light_contribution` / `area_light_contribution`):**

- **Directional:** `to_light = normalize(-light.direction)`, no
  distance attenuation.
- **Point/Spot:** `attenuation = 1 / (constant + linear*d + quadratic*d²)`.
- **Spot** additionally: `cone_cos = dot(-to_light, normalize(light.direction))`,
  multiplied by `smoothstep(outerConeCos, innerConeCos, cone_cos)` for a
  soft-edged cone.
- **Area:** `area_light_contribution` averages `sample_count` (1–8,
  `u_AreaLightSampleCount`) points across a stratified
  `grid_size × grid_size` grid over the light's quad
  (`light.position + areaU*su + areaV*sv`), each weighted by the
  emitter's own cosine falloff (`dot(-sample_direction, light.direction)`,
  since a flat emissive surface radiates strongest along its own
  normal), then divides by `sample_count` (Monte Carlo 1/N weighting).
  Optional per-sample jitter (`u_AreaLightJitter`) via `hash21`, seeded
  off `gl_FragCoord.xy` in the fragment copy (decorrelates neighbouring
  pixels) vs. `world_position.xz` in the vertex copy (`gl_FragCoord`
  doesn't exist there). Explicitly single-bounce, no shadow/visibility
  test per sample.

**Back-face culling (manual):** `is_back_facing = dot(normal, direction_to_eye) < 0.0`.
`direction_to_eye` differs by projection: perspective uses
`normalize(u_ViewPosition - v_WorldPosition)` (a different direction per
fragment, since the eye is a finite point); orthographic uses the
constant `-normalize(u_ViewDirection)` (every view ray is parallel, so
one direction serves the whole screen). `u_CullMode == CULL_MANUAL`
triggers a `discard`; `CULL_GL` relies on hardware `GL_CULL_FACE` set
from `Source/Main.odin` (the fragment never reaches this shader at all
in that mode); `CULL_OFF` draws everything.

**Depth visualisation:** `depth_ndc = gl_FragCoord.z * 2.0 - 1.0`
recovers NDC z from window-space `[0,1]`. Perspective:
`linear_depth = (2*near*far) / (far + near - depth_ndc*(far-near))`
(inverts the hyperbolic perspective-divide relationship). Orthographic:
`linear_depth = near + (depth_ndc+1)*0.5*(far-near)` (a plain affine
remap, since orthographic has no perspective divide and NDC z is
already linear in view-space distance). Both then normalize to `[0,1]`
via `clamp((linear_depth-near)/(far-near), 0, 1)` for the grayscale
output.

**Ray-traced reflection (`trace_reflection`, `intersect_sphere`/
`intersect_box_local`/`intersect_cylinder_local`):** Still fully present
and unchanged in the shader, even though `Source/Reflection.odin`
(which built/uploaded the `u_Proxies`/`u_ProxyCount` data from Odin) was
removed on this branch — the GLSL code itself is intact but currently
UNREACHABLE/inert in practice since `u_ProxyCount` is never uploaded
(defaults to 0, so `trace_reflection`'s loop never executes and always
falls through to `return u_SkyColor`), and no material ever has
`u_IsReflectiveSurface` set true (no Odin code sets it anymore).
`trace_reflection(ray_origin, ray_dir)` loops over up to `MAX_PROXIES`
(16) `Proxy` shapes, testing each via `intersect_sphere` (analytic
quadratic, world-space) or, for boxes/cylinders, transforming the ray
into the proxy's local space via `proxy.inverseWorld` first
(`intersect_box_local` = slab method; `intersect_cylinder_local` =
infinite-cylinder quadratic in local XZ, clamped to `±half_height`, plus
two end-cap disk tests), correcting the resulting local-space `t` back
to world-space by dividing by `length(local_dir)`. On the nearest hit it
derives an analytic normal per proxy type, casts a hard shadow ray
toward the scene's one `LIGHT_TYPE_DIRECTIONAL` light (found by
scanning `u_Lights`, not a fixed index), darkens the result to 35% if
occluded, and shades the hit point via `compute_lighting` (the same
function every rasterized fragment uses, with a shared
`PROXY_SPECULAR_STRENGTH=0.2`/`PROXY_SHININESS=12.0` material). A miss
returns `u_SkyColor`. Called from `main()`'s reflection branch with a
Fresnel-Schlick blend:
`fresnel = base_reflectance(0.15) + (1-0.15) * pow(1 - dot(normal,-incident), 5)`.

**Polish pass (ground detail, fog, vignette, tonemap, sky):**

- `apply_ground_detail`: two octaves of `value_noise` (coarse `*0.12`
  scale, fine `*1.3` scale, world-space XZ), blended
  `coarse*0.65 + fine*0.35`, multiplies the ground's colour by
  `mix(0.82, 1.18, pattern)`.
- `apply_fog`: `fog_factor = (1 - exp(-distance*0.035)) * 0.85`, mixes
  `color` toward `u_SkyColor`.
- `apply_vignette`: `dist = length(gl_FragCoord.xy/u_Resolution - 0.5) * 1.4`,
  multiplies by `mix(0.55, 1.0, 1-smoothstep(0.5,1.05,dist))` — darkest
  corner drops to 55% brightness.
- `apply_tonemap_gamma`: Reinhard (`color/(color+1)`) then
  `pow(mapped, 1/2.2)` — the ONLY place in the shader that leaves linear
  colour space.
- `sky_color`: gradient `mix(u_SkyColor, zenith_or_nadir, pow(|up|,0.7))`
  by `direction.y`, plus a sparse starfield — one hashed candidate point
  per cell of a 140-unit direction-space grid (`hash31(cell) > 0.997`
  sparsity), jittered within its cell, tested by angular distance
  (`star_radius=0.0035`) so each star stays a constant small size
  regardless of view direction, with a `sin(time*2 + brightness*2π)`
  twinkle.

**hash21/hash31:** `hash21(vec2) = fract(sin(dot(p,(12.9898,78.233)))*43758.5453)`;
`hash31(vec3)` is its 3D sibling with an extra `45.164` term. These two
"sine-fract" hashes are the ONLY source of pseudo-randomness in the
entire file (area-light jitter, `value_noise`'s grid corners, the star
field) — no texture, no lookup table anywhere in this shader.

**[PROGRESS-DEMO] state on this branch:** `u_ObjectsOnlyMode`'s
early-return is the VERY FIRST statement in `main()` — confirmed to run
BEFORE the `u_DepthVisualization` check and BEFORE the `u_IsSky` branch.
This means on this branch, for every fragment including the sky dome
(`u_IsSky=true`), the shader never reaches `sky_color()` at all — the
sky cube currently renders as flat, solid `u_BaseColor` (which
`Source/Main.odin`'s sky material sets to `(0,0,0)`, i.e. solid black),
not a gradient. Depth-visualisation and every other toggle downstream
are likewise unreachable while this uniform is on.

**How it connects to the rest of the project:** Compiled/linked as one
program by `Library/Engine/Shader.New(COMBINED_SHADER_PATH)`, called
once at startup from `Source/Main.odin`. Every `u_*` uniform this file
declares is uploaded per-frame (or per-draw-call, for per-object ones
like `u_BaseColor`/`u_Model`) from `Source/Main.odin`'s main loop via
`Library/Engine/Shader.SetUniform`; `u_Lights[]`/`u_ActiveLightCount`
were previously uploaded by the now-removed `Library/Lights.Upload`, and
`u_Proxies[]`/`u_ProxyCount` by the now-removed `Source/Reflection.odin`'s
`Upload_Proxies` — both uniform blocks are still declared and referenced
in this shader but currently receive no data on this branch.
