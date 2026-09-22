// Package Camera — free-fly camera and projection toggle. Split out from
// `Library/Scene` into its own package per the user's Session 0 decision on
// CLAUDE.md §11 item 7 (see PROGRESS.md).
//
// Roadmap step 2 (CLAUDE.md §9; Prompts.md Session 2): implemented here.
// Extended later by Patrol Mode (roadmap step 9) and Inspection Mode
// (roadmap step 10) — see the notes at the bottom of this file for what
// those steps still need to add.
//
// This package deliberately knows nothing about GLFW: Source/Main.odin owns
// polling key state, reading cursor/scroll deltas, and time-stepping, and
// passes the results in as plain numbers (`Apply_Move`, `Apply_Look_Delta`).
// That keeps Camera's math testable without a window/GL context (see
// Camera_test.odin) and keeps the input-polling/callback plumbing in one
// place (Source/Main.odin) rather than split across packages.
//
// Uses `linalg.matrix4_look_at`, `linalg.matrix4_perspective`, and
// `linalg.matrix_ortho3d` directly (core:math/linalg is allowed — CLAUDE.md
// §2 item 3). NOTE: linalg's orthographic proc is named `matrix_ortho3d`,
// not `matrix4_orthographic` — checked directly against this project's
// installed `core:math/linalg/specific.odin` before writing the code below,
// since no proc of the latter name exists in this Odin build.
//
// Patrol Mode (automatic, roadmap step 9, not yet implemented): the camera
// will instead follow a smooth closed path around the outside of the
// perimeter fence, computed by a formula (e.g. an ellipse/superellipse or
// smoothed polar curve with slight height bobbing), always looking toward
// the base centre or a slowly drifting target — never a stored list of
// waypoints (CLAUDE.md §2 item 5, §7; Plan.md §4). That will likely be a
// `Patrol_Camera_At(time_seconds: f32) -> Camera` proc added alongside the
// free-fly procs below, reusing this same `Camera` struct and
// `View_Matrix`/`Projection_Matrix` (CLAUDE.md §2 item 9 — one render path
// for both modes; only what feeds the camera's transform differs).
//
// Inspection Mode (interactive, roadmap step 10): `Apply_Move` and
// `Apply_Look_Delta` below are already exactly what free-fly needs; step 10
// mainly adds the mode-switch state machine (CLAUDE.md §7 — Patrol ->
// Inspection keeps the current camera pose; Inspection -> Patrol resumes
// without a jarring jump) in Source/Main.odin, not new Camera math.
package Camera

import "core:math"
import la "core:math/linalg"

// -----------------------------------------------------------------------
// Math & coordinate conventions (CLAUDE.md §1.2/§10, roadmap step 1,
// Session 1). This project doesn't hand-derive its math — core:math/linalg
// does — but linalg still has real conventions baked into how its procs
// behave, and every session from here on assumes them. Recorded once, here,
// so nobody re-derives or contradicts them later. Confirmed empirically
// against this project's installed Odin toolchain (see
// Library/Camera/Camera_test.odin and PROGRESS.md), not assumed from docs.
//
// - COORDINATE SYSTEM: right-handed, +X right, +Y up, and in VIEW space the
//   camera looks down -Z (confirmed: matrix4_look_at(eye=(0,0,5),
//   target=origin, up=+Y) puts the origin at view-space z = -5). This is
//   `matrix4_look_at` and `matrix4_perspective`'s default `flip_z_axis =
//   true` behaviour; SENTINEL never overrides that default, so every
//   view/projection matrix in the project agrees with each other and with
//   plain OpenGL's own long-standing convention — nothing about clip space
//   or NDC needs re-deriving once a linalg matrix reaches the GPU.
//
// - VECTOR CONVENTION: vectors are COLUMNS, transformed on the right of a
//   matrix (`p' = M * p`, i.e. `la.mul(M, p)`). Composing transforms
//   therefore reads right-to-left in code but "first this, then that" in
//   effect: `mvp := la.mul(proj, la.mul(view, model))` means "apply `model`
//   first, then `view`, then `proj`" to a point on the right. This matches
//   what `matrix4_translate`/`matrix4_rotate`/`matrix4_scale` themselves
//   already produce — a row-vector convention would silently invert every
//   composition order in the project.
//
// - MATRIX STORAGE / GLSL MAPPING: `Matrix4f32` stores COLUMN-MAJOR in
//   memory — confirmed by reading `la.to_ptr(&m)` back as a flat float
//   array after building a translation matrix: the translation lands in the
//   LAST four floats, i.e. the last COLUMN, exactly where GLSL's own
//   column-major `mat4` expects it. This is why
//   `Library/Engine/Shader.SetUniformMatrix4f32` calls
//   `gl.UniformMatrix4fv(..., transpose = false, la.to_ptr(mat))` — no
//   transpose is ever needed between a linalg matrix and a GLSL uniform,
//   and no future session should add one "just in case".
//
// - ANGLE UNITS: radians everywhere inside linalg (`matrix4_rotate`,
//   `matrix4_perspective`'s fovy, etc.). SENTINEL keeps all angle STATE
//   (yaw/pitch, sweep angles, FOV) in radians internally, converting to/from
//   degrees only at the edges people actually read (an on-screen readout, a
//   CLI flag) with `math.to_radians`/`math.to_degrees` — so no proc in this
//   project is ever silently handed the wrong unit.
//
// - ROTATION DIRECTION: positive angles follow the RIGHT-HAND RULE around
//   the given axis (point the right thumb along the axis; the fingers curl
//   toward positive rotation) — confirmed empirically: rotating (1,0,0) by
//   +90 degrees about (0,1,0) with `matrix4_rotate` yields (0,0,-1), i.e.
//   +X sweeps toward -Z, exactly the right-hand rule applied to +Y in this
//   right-handed system. Every hierarchy rotation later (tower-head sweep,
//   turret spin, radar rotation) uses this same sense, so "positive angle"
//   always means the same physical direction everywhere in the project.
//
// - CLIP-SPACE DEPTH RANGE: `matrix4_perspective`'s default maps view-space
//   near to NDC z = -1 and far to NDC z = +1 (OpenGL's traditional [-1, 1]
//   clip volume, not Direct3D's [0, 1]) — confirmed empirically. SENTINEL
//   never calls `gl.ClipControl`, so this is the depth range the GPU
//   actually uses; the depth-buffer visualisation planned for roadmap step
//   8 must remap from THIS range, not [0, 1].
// -----------------------------------------------------------------------

WORLD_UP :: la.Vector3f32{0, 1, 0}

// Pitch is clamped just short of +/-90 degrees rather than exactly at it:
// at exactly 90 degrees `Right` (cross(Forward, WORLD_UP)) degenerates to
// the zero vector because Forward and WORLD_UP become parallel, which would
// make strafe movement and the view matrix's basis undefined right at the
// limit.
PITCH_LIMIT_RADIANS :: 89.0 * math.PI / 180.0

// A floor on the orthographic half-height so `Zoom_Ortho` can't shrink the
// volume to (or through) zero, which would make `View_Ortho`'s matrix
// singular.
MIN_ORTHO_HALF_HEIGHT :: 0.1

// Every scroll "step" (one notch of a mouse wheel, or one trackpad tick)
// scales the ortho half-height by this factor — <1 so scrolling forward
// (the GLFW convention for "away from the user", i.e. positive y-offset)
// zooms in by shrinking the visible volume.
ORTHO_ZOOM_FACTOR_PER_SCROLL_STEP :: 0.9

Projection_Mode :: enum {
	Perspective,
	Orthographic,
}

// Camera holds everything needed to build a view and a projection matrix
// for either free-fly (Inspection Mode) or, later, a Patrol-Mode path
// (roadmap step 9 — see this file's header). yaw/pitch are the only
// orientation state (no stored quaternion/forward vector) so there is
// exactly one source of truth to keep in sync when applying look input or
// clamping pitch.
Camera :: struct {
	position:          la.Vector3f32,
	yaw:               f32, // radians; forward = (0, 0, -1) at yaw = 0, pitch = 0
	pitch:             f32, // radians; clamped to +/- PITCH_LIMIT_RADIANS
	fov_y:             f32, // radians; perspective vertical field of view
	near:              f32,
	far:               f32,
	projection:        Projection_Mode,
	ortho_half_height: f32, // half-height of the orthographic volume; half-width = this * aspect
	move_speed:        f32, // world units/second at normal (non-sprint) speed
	sprint_multiplier: f32,
	look_sensitivity:  f32, // radians of yaw/pitch per pixel of cursor movement
}

DEFAULT_FOV_Y_DEGREES :: 45.0
DEFAULT_NEAR :: 0.1
DEFAULT_FAR :: 100.0
DEFAULT_ORTHO_HALF_HEIGHT :: 5.0
DEFAULT_MOVE_SPEED :: 4.0
DEFAULT_SPRINT_MULTIPLIER :: 3.0
DEFAULT_LOOK_SENSITIVITY :: 0.0025

// Default_Camera returns a camera at `position`, facing -Z (yaw = pitch =
// 0), with the project's default lens/movement parameters. These are
// small runtime *parameters* (CLAUDE.md §2 item 5), not precomputed scene
// data — nothing about the scene itself is baked in here.
Default_Camera :: proc(position: la.Vector3f32) -> Camera {
	return Camera {
		position          = position,
		yaw               = 0,
		pitch             = 0,
		fov_y             = math.to_radians(f32(DEFAULT_FOV_Y_DEGREES)),
		near              = DEFAULT_NEAR,
		far               = DEFAULT_FAR,
		projection        = .Perspective,
		ortho_half_height = DEFAULT_ORTHO_HALF_HEIGHT,
		move_speed        = DEFAULT_MOVE_SPEED,
		sprint_multiplier = DEFAULT_SPRINT_MULTIPLIER,
		look_sensitivity  = DEFAULT_LOOK_SENSITIVITY,
	}
}

// Camera_Looking_At returns a Default_Camera at `position` with yaw/pitch
// solved so Forward(cam) points at `target`. Closed-form inverse of
// `Forward`'s formula below (derived by hand from the same R_y * R_x
// composition Forward uses, then cross-checked against
// Camera_test.odin's confirmed rotation-direction test) rather than an
// iterative solve, since the forward vector algebraically determines
// yaw/pitch directly. Used once at startup to point the free camera at the
// test scene without hand-picking yaw/pitch by trial and error.
Camera_Looking_At :: proc(position, target: la.Vector3f32) -> Camera {
	cam := Default_Camera(position)
	cam.yaw, cam.pitch = yaw_pitch_looking_at(position, target)
	return cam
}

// yaw_pitch_looking_at solves yaw/pitch so Forward points from `position`
// toward `target` — the closed-form inverse of Forward's own formula
// (see Camera_Looking_At's original header note, moved here). Factored out
// (roadmap step 9, Prompts.md Session 12) so Camera_Looking_At and the new
// Patrol_Camera_Pose below share the ONE derivation instead of two copies
// of the same formula drifting apart.
@(private = "file")
yaw_pitch_looking_at :: proc(position, target: la.Vector3f32) -> (yaw, pitch: f32) {
	direction := la.normalize(target - position)
	pitch = math.asin(clamp(direction.y, -1, 1))
	yaw = math.atan2(-direction.x, -direction.z)
	return
}

// Forward returns the camera's unit-length look direction. Closed form
// (rather than composing la.matrix4_rotate calls every frame) for
// `R_y(yaw) * R_x(pitch) * (0, 0, -1)`, hand-derived from the standard
// right-handed rotation matrices and cross-checked against
// Camera_test.odin's confirmed +X rotated +90 degrees about +Y -> -Z case.
// Already unit length: x^2+y^2+z^2 = cos^2(pitch)*(sin^2+cos^2)(yaw) +
// sin^2(pitch) = 1, so callers never need to re-normalize this specific
// result.
Forward :: proc(cam: ^Camera) -> la.Vector3f32 {
	cos_pitch := math.cos(cam.pitch)
	return la.Vector3f32 {
		-cos_pitch * math.sin(cam.yaw),
		math.sin(cam.pitch),
		-cos_pitch * math.cos(cam.yaw),
	}
}

// Right returns the camera's unit-length local +X (strafe) axis. Unlike
// Forward, this is NOT unit length before normalizing: Forward and
// WORLD_UP are only perpendicular when pitch = 0, so
// |cross(Forward, WORLD_UP)| = sin(angle between them) < 1 at any other
// pitch.
Right :: proc(cam: ^Camera) -> la.Vector3f32 {
	return la.normalize(la.cross(Forward(cam), WORLD_UP))
}

// Up returns the camera's local +Y axis (true up, not WORLD_UP). Already
// unit length: Right and Forward are unit and perpendicular by
// construction, so their cross product needs no re-normalization.
Up :: proc(cam: ^Camera) -> la.Vector3f32 {
	return la.cross(Right(cam), Forward(cam))
}

// View_Matrix builds the camera's view matrix fresh from its current
// position/yaw/pitch every call — never cached (CLAUDE.md §2 item 10's
// "never cache what should be recomputed" spirit applies just as much to
// the camera as to lights).
View_Matrix :: proc(cam: ^Camera) -> la.Matrix4f32 {
	return la.matrix4_look_at(cam.position, cam.position + Forward(cam), WORLD_UP)
}

// Projection_Matrix builds the camera's projection matrix for the given
// viewport aspect ratio (width/height), fresh every call so window resizes
// are never stale (Source/Main.odin re-reads the framebuffer size and
// passes aspect in each frame).
Projection_Matrix :: proc(cam: ^Camera, aspect: f32) -> la.Matrix4f32 {
	switch cam.projection {
	case .Perspective:
		return la.matrix4_perspective(cam.fov_y, aspect, cam.near, cam.far)
	case .Orthographic:
		half_height := cam.ortho_half_height
		half_width := half_height * aspect
		return la.matrix_ortho3d(-half_width, half_width, -half_height, half_height, cam.near, cam.far)
	}
	unreachable()
}

// Apply_Look_Delta turns a raw cursor-position delta (in pixels, as read
// from GLFW between two frames) into a yaw/pitch update, then clamps
// pitch. Sign conventions, both confirmed against the yaw/pitch formula in
// Forward above:
//   - Increasing yaw turns the camera toward -X when facing -Z (yaw = +90
//     sends Forward's (0,0,-1) to (-1,0,0), a LEFT turn given
//     Right = (1,0,0) at yaw = 0). A cursor moving right (positive
//     cursor_delta_x) should turn the camera right, so yaw must DECREASE.
//   - GLFW's cursor Y grows downward, so moving the mouse up yields a
//     NEGATIVE cursor_delta_y; moving the mouse up should pitch the camera
//     up (increase pitch), hence the negation there too.
Apply_Look_Delta :: proc(cam: ^Camera, cursor_delta_x, cursor_delta_y: f32) {
	cam.yaw -= cursor_delta_x * cam.look_sensitivity
	cam.pitch -= cursor_delta_y * cam.look_sensitivity
	cam.pitch = clamp(cam.pitch, -PITCH_LIMIT_RADIANS, PITCH_LIMIT_RADIANS)
}

// Apply_Move advances the camera's position along its own Forward/Right
// axes plus WORLD_UP, scaled by dt_seconds so movement speed is
// independent of frame rate. move_forward/move_right/move_up are each
// expected in [-1, 1] (Source/Main.odin derives them from opposing
// WASD/QE key pairs); the combined direction is re-normalized so moving
// diagonally (e.g. W+D) isn't faster than moving along one axis.
Apply_Move :: proc(cam: ^Camera, move_forward, move_right, move_up, dt_seconds: f32, sprint: bool) {
	if move_forward == 0 && move_right == 0 && move_up == 0 do return

	direction := Forward(cam) * move_forward + Right(cam) * move_right + WORLD_UP * move_up
	direction = la.normalize(direction)

	speed := cam.move_speed
	if sprint do speed *= cam.sprint_multiplier

	cam.position = cam.position + direction * speed * dt_seconds
}

// Toggle_Projection switches between perspective and orthographic. Going
// Perspective -> Orthographic syncs ortho_half_height from the camera's
// current distance to `focus` (typically the scene's centre) so the
// orthographic volume frames roughly the same view perspective was just
// showing at that distance (CLAUDE.md §7): a perspective frustum's
// half-height at a given distance is `distance * tan(fov_y / 2)`, so using
// that same half-height for the ortho volume matches the apparent framing
// at the moment of the switch. Going Orthographic -> Perspective needs no
// equivalent sync since fov_y never changes.
Toggle_Projection :: proc(cam: ^Camera, focus: la.Vector3f32) {
	switch cam.projection {
	case .Perspective:
		distance := la.length(focus - cam.position)
		cam.ortho_half_height = distance * math.tan(cam.fov_y * 0.5)
		cam.projection = .Orthographic
	case .Orthographic:
		cam.projection = .Perspective
	}
}

// Zoom_Ortho scales the orthographic volume by
// ORTHO_ZOOM_FACTOR_PER_SCROLL_STEP raised to `scroll_delta_y` (GLFW's
// scroll-callback y-offset, positive = scrolled away from the user), then
// clamps to MIN_ORTHO_HALF_HEIGHT. A no-op in Perspective mode is the
// caller's choice (Source/Main.odin only calls this while
// cam.projection == .Orthographic); zooming perspective's FOV was not
// asked for and isn't implemented here.
Zoom_Ortho :: proc(cam: ^Camera, scroll_delta_y: f32) {
	cam.ortho_half_height *= math.pow(f32(ORTHO_ZOOM_FACTOR_PER_SCROLL_STEP), scroll_delta_y)
	cam.ortho_half_height = max(cam.ortho_half_height, MIN_ORTHO_HALF_HEIGHT)
}

// -----------------------------------------------------------------------
// Patrol Mode (roadmap step 9, CLAUDE.md §7/§9; Prompts.md Session 12): the
// camera flies a closed, formula-driven path around the OUTSIDE of the
// perimeter fence instead of following WASD/mouse input — this was already
// anticipated at the top of this file (Session 2's own header note) as a
// `Patrol_Camera_At`-shaped addition reusing this same Camera struct and
// View_Matrix/Projection_Matrix, which is exactly what's below. This
// section only knows the PATH's shape and where the camera looks — nothing
// about GLFW, a Mode enum, the shared animation clock, or which Scene
// nodes exist, all of which stay in Source/Patrol.odin and Source/
// Main.odin (the same GLFW-agnostic split this file's header already
// established for free-fly).
// -----------------------------------------------------------------------

// PATROL_RADIUS must clear the perimeter fence's own footprint
// (Library/Scene/Objects.odin's FENCE_HALF_WIDTH/DEPTH = 14, a 28x28
// square) with real margin, at EVERY angle — a circle's distance from its
// own centre is constant, so unlike a shape that bulges outward toward the
// corners, the worst case here is the fence's own CORNER distance
// (14*sqrt(2) ~= 19.8, not just its flat-side distance of 14). 24 clears
// that corner by a comfortable ~4.2 units on every side, not just the
// axis-aligned ones.
//
// A superellipse ("squircle") was tried first, to hug the square fence's
// own shape more closely than a circle — but the standard parametrization
// (x = R*sign(cos)*|cos|^(2/n), z = R*sign(sin)*|sin|^(2/n)) has an
// INFINITE derivative in the parameter itself at each of the 4 axis
// crossings whenever n > 2 (confirmed empirically: Camera_test.odin's
// first attempt at an axis-point test failed by ~0.004 units, not from
// float rounding, but from sqrt's derivative blowing up right at the
// crossing where cos or sin passes through exactly zero). Mathematically
// the underlying CURVE is smooth — only this specific PARAMETRIZATION
// isn't — but a camera whose angle advances linearly in time would still
// visibly "snap" through those 4 points on screen, directly contradicting
// this session's own "smooth closed path" requirement. A plain circle
// (this project's fence footprint is a perfect square, so equal radii on
// both axes) has no such artifact, is simpler, and is explicitly one of
// the task's own suggested shapes ("e.g. ellipse/superellipse") — not a
// downgrade, the right choice once the superellipse's real cost was found.
PATROL_RADIUS :: 24.0

PATROL_HEIGHT :: 9.0
PATROL_HEIGHT_BOB_AMPLITUDE :: 1.2
PATROL_HEIGHT_BOB_RATE :: 0.3 // rad/s, argument to sin()

// A full 2*PI loop takes ~90 seconds at this rate — slow and majestic, but
// still completes more than one full lap within the "2-minute hands-off
// demo" this session's task asks to verify looks good, rather than
// crawling through less than one lap or looping so fast it feels dizzying.
PATROL_ANGULAR_SPEED :: 0.0698 // rad/s (2*PI / 90s)

// The look target drifts slowly near the base centre rather than staying
// perfectly fixed at the origin — a small extra bit of "life" (still a
// pure formula, CLAUDE.md §2 item 5) so the camera's aim isn't perfectly
// rigid relative to its own position on the path. The two rates are a
// non-integer ratio (0.11 : 0.077) specifically so the drift's own path
// never closes on itself on any timescale a viewer would notice, unlike
// using the same rate on both axes (which would just be a shrunk copy of
// an ellipse).
PATROL_LOOK_TARGET_DRIFT_RADIUS :: 2.5
PATROL_LOOK_TARGET_DRIFT_RATE_X :: 0.11
PATROL_LOOK_TARGET_DRIFT_RATE_Z :: 0.077

// Patrol_Path_Position returns the camera's XZ position on the closed path
// for a given ANGLE (not time — Patrol_Camera_Pose below converts time to
// angle once, and Source/Main.odin's Inspection->Patrol handover
// separately needs "the path position at THIS angle" without going
// through time at all, see Patrol_Nearest_Angle). A plain circle of radius
// PATROL_RADIUS — see that constant's own comment for why (a superellipse
// was tried and rejected: it isn't actually smooth in this parameter, and
// this project's square fence footprint has equal clearance on both axes
// anyway, so a circle loses nothing by being simpler).
Patrol_Path_Position :: proc(angle: f32) -> la.Vector3f32 {
	return la.Vector3f32{PATROL_RADIUS * math.cos(angle), 0, PATROL_RADIUS * math.sin(angle)}
}

// Patrol_Look_Target returns the slowly-drifting point the patrol camera
// aims at, in world space, near the base centre (CLAUDE.md §7's "always
// looking toward the base centre or a slowly drifting target" — this picks
// the second, slightly livelier option).
Patrol_Look_Target :: proc(time_seconds: f32) -> la.Vector3f32 {
	return la.Vector3f32{
		math.cos(time_seconds * PATROL_LOOK_TARGET_DRIFT_RATE_X) * PATROL_LOOK_TARGET_DRIFT_RADIUS,
		0,
		math.sin(time_seconds * PATROL_LOOK_TARGET_DRIFT_RATE_Z) * PATROL_LOOK_TARGET_DRIFT_RADIUS,
	}
}

// Patrol_Camera_Pose returns only the THREE fields Patrol Mode actually
// drives (position, yaw, pitch) for the given TIME — deliberately not a
// full Camera, so a caller can never accidentally overwrite the live
// Camera's projection/lens/move-speed fields by assigning a freshly built
// struct over them (Source/Main.odin copies these three fields into the
// one shared `camera` every Patrol frame, which is exactly what keeps a
// live `P` projection toggle intact while patrolling). `time_seconds` is
// usually the shared animation clock, but Source/Main.odin's
// Inspection->Patrol handover passes that clock PLUS a phase offset
// instead, to resume from the nearest path point rather than jumping to
// wherever the raw clock's angle happens to be.
Patrol_Camera_Pose :: proc(time_seconds: f32) -> (position: la.Vector3f32, yaw, pitch: f32) {
	angle := time_seconds * PATROL_ANGULAR_SPEED
	path_position := Patrol_Path_Position(angle)
	height := PATROL_HEIGHT + math.sin(time_seconds*PATROL_HEIGHT_BOB_RATE)*PATROL_HEIGHT_BOB_AMPLITUDE
	position = la.Vector3f32{path_position.x, height, path_position.z}
	yaw, pitch = yaw_pitch_looking_at(position, Patrol_Look_Target(time_seconds))
	return
}

// Patrol_Nearest_Angle finds which angle on the closed path sits nearest a
// given WORLD position — used once, at the moment of an Inspection ->
// Patrol switch, to compute a phase offset so the patrol camera "restarts
// from the nearest path point" (this session's task, CLAUDE.md §7) instead
// of teleporting to wherever the shared clock's raw angle happens to be.
// EXACT, not an approximation, because Patrol_Path_Position is a plain
// circle centred on the origin: for a circle, the nearest point to ANY
// external position lies exactly along the ray from the centre through
// that position, so that ray's own polar angle IS the nearest angle — a
// basic geometric fact, not a heuristic (confirmed for the axis case by
// Camera_test.odin; true at every angle by the same argument, not just
// those four points, unlike the rejected superellipse attempt).
Patrol_Nearest_Angle :: proc(world_position: la.Vector3f32) -> f32 {
	return math.atan2(world_position.z, world_position.x)
}
