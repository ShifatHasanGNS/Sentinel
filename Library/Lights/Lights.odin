// Package Lights — light structs, runtime placement, and animation. Split
// out from `Library/Scene` into its own package per the user's Session 0
// decision on CLAUDE.md §11 item 7. Depends on `Library/Scene` (Material,
// Draw_Node — gizmos are drawn through the exact same path every real
// object uses) and `Library/Geometry` (gizmo meshes are built from Cube,
// same as everything else in this project).
//
// Roadmap step 4 (CLAUDE.md §9; Prompts.md Session 7): the `Light` struct
// below (mirrored field-for-field by Shaders/Scene.glsl's `Light` GLSL
// struct — see that file's own comment), a fixed-max uniform-array upload,
// and a TEMPORARY formula-placed rig (Build_Temporary_Rig) so the shader's
// per-type lighting loop has something real to light the scene with before
// roadmap step 5 exists.
//
// What step 4 deliberately does NOT do yet: attach any light to a Scene
// hierarchy node. Every light in Build_Temporary_Rig has a fixed
// world-space position/direction computed once from a formula (a ring
// radius/count, a height) — NOT derived from a parent node's world matrix
// the way CLAUDE.md §5.3 ultimately requires (jeep headlights following the
// jeep, tank turret searchlight following the turret, etc.). That
// attachment — recomputing each attached light's world position/direction
// EVERY frame from Scene.World_Position/World_Direction, never cached
// (CLAUDE.md §2 item 10) — is roadmap step 5's job (Prompts.md Session 8),
// which will most likely replace Build_Temporary_Rig with a real rig built
// from the actual node names Library/Scene/Objects.odin's Session 5/6
// sections already documented (Watchtower Floodlight Head, Jeep Headlight
// Left/Right, Radar Beacon, Tank Hull, Tank Turret, Gun Emplacement, and
// Library/Scene.Fence_Post_Position for the fence lamps) — see PROGRESS.md.
//
// Light rig target (Requirements.md §3, CLAUDE.md §5.2, Plan.md §3): 18-21
// lights across point/spot/area/directional, comfortably exceeding the 9
// objects. This session's TEMPORARY rig alone already reaches 12 (1
// moonlight + 8 point + 3 spot) — deliberately more than the 9 objects even
// before step 5's real rig replaces it, so the "lights > objects" print
// this session adds is already meaningfully true, not just structurally
// ready.
package Lights

import "core:fmt"
import "core:math"
import la "core:math/linalg"
import "core:strings"

import geo "../Geometry"
import scenepkg "../Scene"
import sd "../Engine/Shader"

// MAX_LIGHTS must match Shaders/Scene.glsl's #define MAX_LIGHTS — see that
// file's own comment on why these two "32"s can't be a single shared
// constant across the Odin/GLSL language boundary.
MAX_LIGHTS :: 32

Light_Type :: enum i32 {
	Directional = 0,
	Point       = 1,
	Spot        = 2,
	Area        = 3, // reserved for roadmap step 6 (CLAUDE.md §6.3); unused by the shader until then
}

// Light mirrors Shaders/Scene.glsl's `Light` struct field-for-field (see
// that file for exactly how each field is used in the lighting equation).
Light :: struct {
	Type:                 Light_Type,
	Position:             la.Vector3f32, // world-space; meaningful for Point/Spot
	Direction:            la.Vector3f32, // world-space, normalized; meaningful for Directional/Spot
	Color:                la.Vector3f32,
	Intensity:            f32,
	ConstantAttenuation:  f32,
	LinearAttenuation:    f32,
	QuadraticAttenuation: f32,
	InnerConeCos:         f32,
	OuterConeCos:         f32,
	Enabled:              bool,
}

Make_Directional :: proc(direction, color: la.Vector3f32, intensity: f32) -> Light {
	return Light{Type = .Directional, Direction = la.normalize(direction), Color = color, Intensity = intensity, Enabled = true}
}

// Point_Attenuation_For_Range derives the classic constant/linear/quadratic
// attenuation triple from a single "range" parameter (roughly the distance
// at which the light's contribution has fallen to ~1% of its peak) instead
// of hand-picking three independent magic numbers per light (CLAUDE.md §2
// item 5 — a small formula-driven PARAMETER, not precomputed data). This is
// the standard approximation (Real-Time Rendering / the widely-used
// Ogre3D attenuation table): constant=1, linear=4.5/range,
// quadratic=75/range^2 — checked against that table's own worked examples
// (range 50 -> linear 0.09/quadratic 0.03; range 20 -> linear 0.225/
// quadratic 0.19) before using it here.
Point_Attenuation_For_Range :: proc(range: f32) -> (constant, linear, quadratic: f32) {
	return 1.0, 4.5 / range, 75.0 / (range * range)
}

Make_Point :: proc(position, color: la.Vector3f32, intensity, range: f32) -> Light {
	constant, linear, quadratic := Point_Attenuation_For_Range(range)
	return Light{
		Type = .Point,
		Position = position,
		Color = color,
		Intensity = intensity,
		ConstantAttenuation = constant,
		LinearAttenuation = linear,
		QuadraticAttenuation = quadratic,
		Enabled = true,
	}
}

Make_Spot :: proc(position, direction, color: la.Vector3f32, intensity, range, inner_angle_degrees, outer_angle_degrees: f32) -> Light {
	constant, linear, quadratic := Point_Attenuation_For_Range(range)
	return Light{
		Type = .Spot,
		Position = position,
		Direction = la.normalize(direction),
		Color = color,
		Intensity = intensity,
		ConstantAttenuation = constant,
		LinearAttenuation = linear,
		QuadraticAttenuation = quadratic,
		InnerConeCos = math.cos(math.to_radians(inner_angle_degrees)),
		OuterConeCos = math.cos(math.to_radians(outer_angle_degrees)),
		Enabled = true,
	}
}

// ---------------------------------------------------------------------------
// Temporary demonstration rig (see this file's header for why it's
// temporary and what replaces it at roadmap step 5).
// ---------------------------------------------------------------------------

TEMP_POINT_LIGHT_COUNT :: 8
TEMP_POINT_LIGHT_RADIUS :: 16.0
TEMP_POINT_LIGHT_HEIGHT :: 3.0
TEMP_POINT_LIGHT_RANGE :: 14.0

TEMP_SPOT_LIGHT_COUNT :: 3
TEMP_SPOT_LIGHT_SPREAD :: 9.0 // how far apart the 3 spot positions are placed along X
TEMP_SPOT_LIGHT_HEIGHT :: 10.0
TEMP_SPOT_LIGHT_RANGE :: 18.0

// Build_Temporary_Rig places 1 directional + TEMP_POINT_LIGHT_COUNT point +
// TEMP_SPOT_LIGHT_COUNT spot lights, all by formula (an evenly-spaced ring
// for the points, an evenly-spaced row aimed straight down for the spots —
// a deliberately simple layout distinct from roadmap step 5's real
// fence-lamp-perimeter/hierarchical-attachment formulas, so this session's
// scope stays self-contained). Caller owns the returned array
// (`delete` it when done).
Build_Temporary_Rig :: proc() -> [dynamic]Light {
	lights := make([dynamic]Light, 0, 1 + TEMP_POINT_LIGHT_COUNT + TEMP_SPOT_LIGHT_COUNT)

	// Moonlight: cool, dim directional fill (CLAUDE.md §5.2) — same
	// direction/colour Session 5's placeholder light used, so the base
	// scene's overall look doesn't jump when this session replaces it with
	// a real light array.
	append(&lights, Make_Directional(la.Vector3f32{-0.4, -1.0, -0.3}, la.Vector3f32{0.55, 0.6, 0.75}, 0.6))

	for i in 0 ..< TEMP_POINT_LIGHT_COUNT {
		angle := 2 * math.PI * f32(i) / f32(TEMP_POINT_LIGHT_COUNT)
		position := la.Vector3f32{TEMP_POINT_LIGHT_RADIUS * math.cos(angle), TEMP_POINT_LIGHT_HEIGHT, TEMP_POINT_LIGHT_RADIUS * math.sin(angle)}
		append(&lights, Make_Point(position, la.Vector3f32{1.0, 0.78, 0.45}, 2.2, TEMP_POINT_LIGHT_RANGE))
	}

	for i in 0 ..< TEMP_SPOT_LIGHT_COUNT {
		x_offset := -TEMP_SPOT_LIGHT_SPREAD + 2 * TEMP_SPOT_LIGHT_SPREAD * f32(i) / f32(TEMP_SPOT_LIGHT_COUNT - 1)
		position := la.Vector3f32{x_offset, TEMP_SPOT_LIGHT_HEIGHT, 0}
		append(&lights, Make_Spot(position, la.Vector3f32{0, -1, 0}, la.Vector3f32{1.0, 1.0, 0.95}, 6.0, TEMP_SPOT_LIGHT_RANGE, 12.5, 20.0))
	}

	return lights
}

// Active_Count reports how many lights are actually Enabled — the number
// this session's task means by "active light count" for the printed
// "lights > objects" comparison (Source/Main.odin), as distinct from
// Upload's `u_ActiveLightCount` uniform, which is a SLOT count (see
// Upload's own comment for why those two numbers can differ once a future
// session introduces gaps).
Active_Count :: proc(lights: []Light) -> int {
	count := 0
	for light in lights {
		if light.Enabled do count += 1
	}
	return count
}

// ---------------------------------------------------------------------------
// Uniform upload.
// ---------------------------------------------------------------------------

@(private = "file")
Light_Uniform_Names :: struct {
	Type, Position, Direction, Color, Intensity,
	ConstantAttenuation, LinearAttenuation, QuadraticAttenuation,
	InnerConeCos, OuterConeCos, Enabled: string,
}

@(private = "file")
uniform_names: [MAX_LIGHTS]Light_Uniform_Names
@(private = "file")
uniform_names_ready: bool

// build_uniform_names formats every "u_Lights[i].field" uniform name ONCE
// and clones each into persistent (non-temp) memory, instead of
// re-formatting them with fmt.tprintf on every Upload call. Two reasons
// this matters, not just style: (1) Library/Engine/Shader.Shader.
// UniformLocationCache is a map keyed by the exact string passed to
// SetUniform — a fresh temp-allocated key every frame would make that
// cache miss every single call, defeating its whole purpose; (2) if this
// project's main loop ever starts calling free_all(context.temp_allocator)
// per frame (it doesn't yet, but nothing prevents adding it), a
// temp-allocated key sitting inside that persistent cache map would go
// stale/dangle. Building MAX_LIGHTS*11 names once at first use and reusing
// them for the rest of the program's lifetime is a fixed, one-time cost —
// the same order of magnitude as UniformLocationCache itself, which is
// likewise never freed before process exit.
@(private = "file")
build_uniform_names :: proc() {
	if uniform_names_ready do return

	for i in 0 ..< MAX_LIGHTS {
		prefix := fmt.tprintf("u_Lights[%d]", i)
		uniform_names[i] = Light_Uniform_Names{
			Type                 = strings.clone(fmt.tprintf("%s.type", prefix)),
			Position             = strings.clone(fmt.tprintf("%s.position", prefix)),
			Direction            = strings.clone(fmt.tprintf("%s.direction", prefix)),
			Color                = strings.clone(fmt.tprintf("%s.color", prefix)),
			Intensity            = strings.clone(fmt.tprintf("%s.intensity", prefix)),
			ConstantAttenuation  = strings.clone(fmt.tprintf("%s.constantAttenuation", prefix)),
			LinearAttenuation    = strings.clone(fmt.tprintf("%s.linearAttenuation", prefix)),
			QuadraticAttenuation = strings.clone(fmt.tprintf("%s.quadraticAttenuation", prefix)),
			InnerConeCos         = strings.clone(fmt.tprintf("%s.innerConeCos", prefix)),
			OuterConeCos         = strings.clone(fmt.tprintf("%s.outerConeCos", prefix)),
			Enabled              = strings.clone(fmt.tprintf("%s.enabled", prefix)),
		}
	}

	uniform_names_ready = true
}

// Upload writes `lights` (clamped to MAX_LIGHTS) into the shader's u_Lights
// array plus u_ActiveLightCount. That uniform is set to the number of SLOTS
// uploaded (len(lights) clamped), not the count of Enabled==true ones —
// Shaders/Scene.glsl's loop still checks each light's own `enabled` flag,
// so a disabled light in the middle of the array is correctly skipped
// rather than truncating every light after it. This session's temporary
// rig has no gaps (every light it builds is Enabled), so the two numbers
// happen to be equal today; keeping them conceptually separate now avoids
// a real bug once roadmap step 5 or later toggles individual lights
// on/off (e.g. barracks windows going dark, a work light with no power).
Upload :: proc(shader: ^sd.Shader, lights: []Light) {
	build_uniform_names()

	upload_count := min(len(lights), MAX_LIGHTS)
	for i in 0 ..< upload_count {
		light := lights[i]
		names := uniform_names[i]

		sd.SetUniform(shader, names.Type, i32(light.Type))
		sd.SetUniform(shader, names.Position, light.Position.x, light.Position.y, light.Position.z)
		sd.SetUniform(shader, names.Direction, light.Direction.x, light.Direction.y, light.Direction.z)
		sd.SetUniform(shader, names.Color, light.Color.x, light.Color.y, light.Color.z)
		sd.SetUniform(shader, names.Intensity, light.Intensity)
		sd.SetUniform(shader, names.ConstantAttenuation, light.ConstantAttenuation)
		sd.SetUniform(shader, names.LinearAttenuation, light.LinearAttenuation)
		sd.SetUniform(shader, names.QuadraticAttenuation, light.QuadraticAttenuation)
		sd.SetUniform(shader, names.InnerConeCos, light.InnerConeCos)
		sd.SetUniform(shader, names.OuterConeCos, light.OuterConeCos)

		enabled_value: i32 = 0
		if light.Enabled do enabled_value = 1
		sd.SetUniform(shader, names.Enabled, enabled_value)
	}

	sd.SetUniform(shader, "u_ActiveLightCount", i32(upload_count))
}

// ---------------------------------------------------------------------------
// Debug gizmos (key L, Source/Main.odin) — a small emissive marker at every
// light's current position, plus a direction line for directional/spot
// lights (CLAUDE.md's "no light has a visible bulb" is otherwise true of
// every light here, since none of them are geometry).
// ---------------------------------------------------------------------------

GIZMO_MARKER_SIZE :: 0.35
GIZMO_LINE_THICKNESS :: 0.06
GIZMO_LINE_LENGTH :: 3.5
// A spot/directional light aimed generally downward (direction.y below this
// threshold) gets its line STRETCHED to actually reach Y = 0 instead of the
// fixed GIZMO_LINE_LENGTH above, so the debug view directly shows where
// that light's cone lands — clamped to GIZMO_MAX_GROUND_LINE_LENGTH so a
// light aimed only slightly downward doesn't draw an absurdly long line.
GIZMO_DOWNWARD_THRESHOLD :: -0.05
GIZMO_MAX_GROUND_LINE_LENGTH :: 40.0
// Directional lights have no meaningful world Position (Shaders/Scene.glsl
// never reads one for LIGHT_TYPE_DIRECTIONAL) — their marker is drawn at
// this fixed nominal height above the scene centre purely so the gizmo view
// has SOMETHING to anchor the moonlight's direction line to.
GIZMO_DIRECTIONAL_MARKER_HEIGHT :: 18.0

// Gizmo_Meshes holds TWO meshes, each built and uploaded to the GPU exactly
// ONCE (Build_Gizmo_Meshes) and reused for every light every frame via a
// fresh MODEL MATRIX per light (Draw_Gizmos) — the same "mesh data built
// once, only the transform recomputed every frame" pattern every real Scene
// node already follows. Toggling gizmos on/off never re-uploads a GPU
// buffer.
Gizmo_Meshes :: struct {
	Marker: geo.Mesh, // small cube, drawn at every light's position
	Line:   geo.Mesh, // elongated cube along local -Z, aimed per-light at draw time
}

Build_Gizmo_Meshes :: proc() -> Gizmo_Meshes {
	marker := geo.Cube(GIZMO_MARKER_SIZE, GIZMO_MARKER_SIZE, GIZMO_MARKER_SIZE)
	geo.Upload(&marker)

	line := geo.Cube(GIZMO_LINE_THICKNESS, GIZMO_LINE_THICKNESS, GIZMO_LINE_LENGTH)
	geo.Upload(&line)

	return Gizmo_Meshes{Marker = marker, Line = line}
}

Destroy_Gizmo_Meshes :: proc(g: ^Gizmo_Meshes) {
	geo.Destroy(&g.Marker)
	geo.Destroy(&g.Line)
}

// Gizmo_Material colour-codes a marker by light type (so the debug view
// reads at a glance which gizmo is which) using ONLY EmissionColor — no
// diffuse/specular contribution — so a gizmo stays visible regardless of
// what's actually lighting the scene around it.
@(private = "file")
Gizmo_Material :: proc(light: Light) -> scenepkg.Material {
	color: la.Vector3f32
	switch light.Type {
	case .Directional: color = {0.6, 0.7, 1.0}
	case .Point:        color = {1.0, 0.85, 0.4}
	case .Spot:          color = {1.0, 1.0, 1.0}
	case .Area:          color = {1.0, 0.5, 0.8}
	}
	return scenepkg.Material{BaseColor = color * 0.2, SpecularStrength = 0, Shininess = 1, EmissionColor = color}
}

// direction_rotation builds the rotation that carries a mesh's local -Z
// axis onto world-space `dir`, via the SAME yaw-then-pitch convention
// Library/Camera/Camera.odin's Camera_Looking_At already uses to solve
// yaw/pitch FROM a direction (cam.pitch = asin(clamp(dir.y,-1,1));
// cam.yaw = atan2(-dir.x,-dir.z)) and Library/Scene/Transform.odin's
// Local_Matrix composes with (yaw outer, pitch inner) — reusing an
// already-tested convention instead of hand-deriving a new basis-matrix
// technique for this one gizmo.
@(private = "file")
direction_rotation :: proc(dir: la.Vector3f32) -> la.Matrix4f32 {
	d := la.normalize(dir)
	pitch := math.asin(clamp(d.y, -1, 1))
	yaw := math.atan2(-d.x, -d.z)
	return la.mul(la.matrix4_rotate(yaw, la.Vector3f32{0, 1, 0}), la.matrix4_rotate(pitch, la.Vector3f32{1, 0, 0}))
}

// Draw_Gizmos draws every enabled light's marker (and, for directional/spot
// lights, a direction line) through Scene.Draw_Node — the identical
// per-mesh uniform-upload/draw path every real object and the ground plane
// use (CLAUDE.md §2 item 9). Positions/directions are read straight from
// `lights` every call, never cached, so this is already correct for
// roadmap step 5's lights once they're derived from a moving parent node
// each frame.
Draw_Gizmos :: proc(shader: ^sd.Shader, view, projection: la.Matrix4f32, lights: []Light, gizmos: ^Gizmo_Meshes) {
	for light in lights {
		if !light.Enabled do continue

		marker_position := light.Position
		if light.Type == .Directional {
			marker_position = la.Vector3f32{0, GIZMO_DIRECTIONAL_MARKER_HEIGHT, 0}
		}

		material := Gizmo_Material(light)
		marker_model := la.matrix4_translate(marker_position)
		scenepkg.Draw_Node(shader, view, projection, marker_model, &gizmos.Marker, material)

		if light.Type == .Spot || light.Type == .Directional {
			direction := la.normalize(light.Direction)

			// Stretch the line to the ground for a downward-aimed light (the
			// common case for this session's temporary spots) so the gizmo
			// directly shows where its cone lands, not just which way it
			// points. Scaling the SHARED line mesh's local Z (its long
			// axis) via the model matrix, rather than rebuilding it at a
			// different length, keeps Gizmo_Meshes' "built once, reused via
			// transform only" design intact.
			length := f32(GIZMO_LINE_LENGTH)
			if direction.y < GIZMO_DOWNWARD_THRESHOLD {
				length = clamp(-marker_position.y / direction.y, GIZMO_LINE_LENGTH, GIZMO_MAX_GROUND_LINE_LENGTH)
			}

			line_center := marker_position + direction * (length * 0.5)
			line_scale := la.matrix4_scale(la.Vector3f32{1, 1, length / GIZMO_LINE_LENGTH})
			line_model := la.mul(la.matrix4_translate(line_center), la.mul(direction_rotation(direction), line_scale))
			scenepkg.Draw_Node(shader, view, projection, line_model, &gizmos.Line, material)
		}
	}
}
