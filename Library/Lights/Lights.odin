// Package Lights — light structs, runtime placement, and animation. Split
// out from `Library/Scene` into its own package per the user's Session 0
// decision on CLAUDE.md §11 item 7. Depends on `Library/Scene` (Material,
// Draw_Node, Find_Node, World_Point/World_Direction, and several objects'
// own size constants — see Build_Rig below) and `Library/Geometry` (gizmo
// meshes are built from Cube, same as everything else in this project).
//
// Roadmap step 4 (CLAUDE.md §9; Prompts.md Session 7) built the `Light`
// struct (mirrored field-for-field by Shaders/Scene.glsl's `Light` GLSL
// struct — see that file's own comment), the fixed-max uniform-array
// upload, and a TEMPORARY formula-placed rig with no hierarchy attachment.
//
// Roadmap step 5 (Prompts.md Session 8) REPLACES that temporary rig with
// the real one: every light now stores a ParentNode index plus a
// LocalOffset/LocalDirection, and Update_From_Scene recomputes each
// light's world Position/Direction EVERY FRAME from its parent's current
// world matrix (never cached, CLAUDE.md §2 item 10) — the same "derive
// from a live world matrix" pattern Scene.Draw_Node already uses for mesh
// transforms, now applied to lights. Build_Rig attaches each light to the
// actual Scene node CLAUDE.md §5.3 names: Watchtower Floodlight Head, Jeep
// Headlight Left/Right, Radar Beacon, Tank Hull, Tank Turret, Gun
// Emplacement, Perimeter Fence (via Scene.Fence_Post_Position for the
// lamps). Barracks window area lights are NOT built here — CLAUDE.md §6.3
// needs the sampled-area-light technique roadmap step 6 (Session 9) adds;
// their slots are simply left unused in the meantime (MAX_LIGHTS = 32 has
// comfortable headroom past this session's 18).
//
// Light rig target (Requirements.md §3, CLAUDE.md §5.2, Plan.md §3): 18-21
// lights across point/spot/area/directional, comfortably exceeding the 9
// objects. Build_Rig reaches exactly 18 (1 moonlight + 8 fence lamps + 2
// floodlights + 2 jeep headlights + 2 tank headlights + 1 tank searchlight
// + 1 radar beacon + 1 gun work light) — the low end of that range now,
// with roadmap step 6's 2-3 barracks area lights reaching the rest.
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

// Light mirrors Shaders/Scene.glsl's `Light` struct field-for-field for the
// upload-facing fields (see that file for exactly how each is used in the
// lighting equation), plus three ATTACHMENT fields (roadmap step 5) that
// never reach the shader directly: ParentNode names which Scene node this
// light rides on, and LocalOffset/LocalDirection are its position/aim IN
// THAT NODE'S OWN LOCAL SPACE. Position/Direction below are the derived
// WORLD-space values Update_From_Scene recomputes every frame from those —
// treat them as read-only outputs, not something to set directly (Make_*
// below leave them zero-valued; the first Update_From_Scene call fills
// them in before anything reads them).
Light :: struct {
	Type:                 Light_Type,
	ParentNode:            int,           // Scene.NO_PARENT for a world-fixed light (moonlight)
	LocalOffset:           la.Vector3f32, // local-space position offset from ParentNode's origin; Point/Spot only
	LocalDirection:        la.Vector3f32, // local-space aim, before the parent's own rotation; Spot/Directional only
	Position:             la.Vector3f32, // world-space; meaningful for Point/Spot — RECOMPUTED, see above
	Direction:            la.Vector3f32, // world-space, normalized; meaningful for Directional/Spot — RECOMPUTED, see above
	Color:                la.Vector3f32,
	Intensity:            f32,
	ConstantAttenuation:  f32,
	LinearAttenuation:    f32,
	QuadraticAttenuation: f32,
	InnerConeCos:         f32,
	OuterConeCos:         f32,
	Enabled:              bool,
}

// Make_Directional's `parent` is almost always Scene.NO_PARENT (moonlight
// has no natural parent object and a directional light has no meaningful
// Position anyway), but takes one anyway rather than special-casing
// Directional out of the attachment system entirely — a future light
// (e.g. a searchlight-style directional beam on some future object) could
// still want one.
Make_Directional :: proc(parent: int, local_direction, color: la.Vector3f32, intensity: f32) -> Light {
	return Light{Type = .Directional, ParentNode = parent, LocalDirection = la.normalize(local_direction), Color = color, Intensity = intensity, Enabled = true}
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

Make_Point :: proc(parent: int, local_offset, color: la.Vector3f32, intensity, range: f32) -> Light {
	constant, linear, quadratic := Point_Attenuation_For_Range(range)
	return Light{
		Type = .Point,
		ParentNode = parent,
		LocalOffset = local_offset,
		Color = color,
		Intensity = intensity,
		ConstantAttenuation = constant,
		LinearAttenuation = linear,
		QuadraticAttenuation = quadratic,
		Enabled = true,
	}
}

Make_Spot :: proc(parent: int, local_offset, local_direction, color: la.Vector3f32, intensity, range, inner_angle_degrees, outer_angle_degrees: f32) -> Light {
	constant, linear, quadratic := Point_Attenuation_For_Range(range)
	return Light{
		Type = .Spot,
		ParentNode = parent,
		LocalOffset = local_offset,
		LocalDirection = la.normalize(local_direction),
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

// Update_From_Scene recomputes every light's world-space Position/
// Direction from its ParentNode's CURRENT world matrix (`world_matrices`,
// this frame's Scene.Compute_World_Matrices result) — never cached,
// CLAUDE.md §2 item 10, exactly the requirement that makes a jeep
// headlight follow the jeep and a tank turret searchlight follow the
// turret through its own independent rotation on top of the hull's.
//
// A light with ParentNode == Scene.NO_PARENT (moonlight) is treated as
// parented to an identity transform, so its LocalOffset/LocalDirection
// pass through as its world Position/Direction unchanged — the same
// "no parent = world-fixed" reading Scene.Compute_World_Matrices already
// gives a root node.
Update_From_Scene :: proc(lights: []Light, world_matrices: []la.Matrix4f32) {
	for &light in lights {
		world_matrix := la.MATRIX4F32_IDENTITY
		if light.ParentNode != scenepkg.NO_PARENT {
			world_matrix = world_matrices[light.ParentNode]
		}

		light.Position = scenepkg.World_Point(world_matrix, light.LocalOffset)
		if light.Type == .Spot || light.Type == .Directional {
			// Only Spot/Directional read Direction (Shaders/Scene.glsl's
			// light_contribution); skipping it for Point avoids
			// normalizing a possibly-zero LocalDirection (Make_Point never
			// sets one) into a NaN.
			light.Direction = la.normalize(scenepkg.World_Direction(world_matrix, light.LocalDirection))
		}
	}
}

// ---------------------------------------------------------------------------
// The real light rig (roadmap step 5), attached through the Scene
// hierarchy — see this file's header for the full node list and count.
// ---------------------------------------------------------------------------

FENCE_LAMP_COUNT :: 8
FENCE_LAMP_HEIGHT :: 1.6
FENCE_LAMP_RANGE :: 7.0
FENCE_LAMP_INTENSITY :: 1.4

FLOODLIGHT_RANGE :: 22.0
FLOODLIGHT_INTENSITY :: 6.0
FLOODLIGHT_INNER_ANGLE :: 15.0
FLOODLIGHT_OUTER_ANGLE :: 25.0

HEADLIGHT_RANGE :: 12.0
HEADLIGHT_INTENSITY :: 4.0
HEADLIGHT_INNER_ANGLE :: 10.0
HEADLIGHT_OUTER_ANGLE :: 18.0

SEARCHLIGHT_RANGE :: 20.0
SEARCHLIGHT_INTENSITY :: 6.0
SEARCHLIGHT_INNER_ANGLE :: 10.0
SEARCHLIGHT_OUTER_ANGLE :: 18.0

BEACON_RANGE :: 6.0
BEACON_INTENSITY :: 2.0

WORK_LIGHT_RANGE :: 8.0
WORK_LIGHT_INTENSITY :: 2.0

MOONLIGHT_INTENSITY :: 0.6

// find_node_or_panic looks up a required Scene node by name and panics
// with a specific message if it's missing, rather than letting a bad index
// (Scene.NO_PARENT, -1) silently propagate into Update_From_Scene and
// either crash on an out-of-range slice access somewhere far from the real
// cause, or — worse — get treated as "world-fixed" and place the light at
// the origin. A missing node here means Library/Scene/Objects.odin and
// this rig have drifted out of sync (e.g. a node got renamed) and should
// fail loudly at startup.
@(private = "file")
find_node_or_panic :: proc(scene: ^scenepkg.Hierarchy, name: string) -> int {
	index := scenepkg.Find_Node(scene, name)
	if index == scenepkg.NO_PARENT {
		panic(fmt.tprintf("Library/Lights.Build_Rig: Scene has no node named %q — Objects.odin and this rig have drifted out of sync", name))
	}
	return index
}

// Build_Rig attaches every light to the actual Scene node that carries it
// (CLAUDE.md §5.3's required hierarchy chains), storing only a ParentNode
// + LocalOffset/LocalDirection per light — the ACTUAL world Position/
// Direction is left zero-valued here and filled in by the first
// Update_From_Scene call, every frame after that, never cached (CLAUDE.md
// §2 item 10). Building the rig itself only needs to run once at startup:
// which node a light is parented to doesn't change frame to frame, only
// where that node currently is.
//
// Several lights below duplicate a POSITION FORMULA that also appears in
// Library/Scene/Objects.odin (e.g. the tank hull headlight offset) rather
// than reading a dedicated child node, because those specific parts were
// deliberately built BAKED IN, not as child nodes (Session 5/6's spec
// wording — see Objects.odin's own comments on the tank hull headlights
// and the gun emplacement work-light post for why). Referencing Objects.
// odin's own exported size constants (Scene.TANK_HULL_SIZE and friends)
// for those offsets, rather than re-typing the numbers, keeps this rig
// automatically in sync if that geometry ever changes.
Build_Rig :: proc(scene: ^scenepkg.Hierarchy) -> [dynamic]Light {
	lights := make([dynamic]Light, 0, 18)

	// Moonlight: cool, dim directional fill (CLAUDE.md §5.2), world-fixed
	// (no natural parent object) — same direction/colour Session 5's
	// placeholder and Session 7's temporary rig both used, so the scene's
	// baseline "night" look doesn't jump between sessions.
	append(&lights, Make_Directional(scenepkg.NO_PARENT, la.Vector3f32{-0.4, -1.0, -0.3}, la.Vector3f32{0.55, 0.6, 0.75}, MOONLIGHT_INTENSITY))

	// Perimeter fence lamps: evenly spaced along the fence LOOP by the same
	// Scene.Fence_Post_Position(t) formula Objects.odin's own post-placement
	// loop uses (exported specifically for this, Session 5's own comment) —
	// not tied to individual post positions, so the lamp count is free to
	// differ from the post count. "Perimeter Fence" never moves (no
	// rotation/translation of its own, and nothing in this project's
	// current scope repositions it), but parenting the lamps to it anyway
	// costs nothing and means they'd correctly follow it if a future
	// session ever did.
	fence := find_node_or_panic(scene, "Perimeter Fence")
	for i in 0 ..< FENCE_LAMP_COUNT {
		t := f32(i) / f32(FENCE_LAMP_COUNT)
		post_point := scenepkg.Fence_Post_Position(t)
		offset := post_point + la.Vector3f32{0, FENCE_LAMP_HEIGHT, 0}
		append(&lights, Make_Point(fence, offset, la.Vector3f32{1.0, 0.8, 0.5}, FENCE_LAMP_INTENSITY, FENCE_LAMP_RANGE))
	}

	// Watchtower floodlights: 2 spots, children of the rotating floodlight
	// head — offsets match the head's own 2 lamp-housing boxes
	// (Objects.odin's build_watchtower: `{sign_x*0.3, 0.2, 0}`). Aimed
	// outward and down; roadmap step 9's real Patrol Mode sweep will rotate
	// the HEAD node itself, which both these spots ride along with for
	// free since their offset/direction are local to it.
	floodlight_head := find_node_or_panic(scene, "Watchtower Floodlight Head")
	for side in 0 ..< 2 {
		sign: f32 = -1 if side == 0 else 1
		append(&lights, Make_Spot(floodlight_head, la.Vector3f32{sign * 0.3, 0.2, 0}, la.Vector3f32{0, -0.3, -1}, la.Vector3f32{1.0, 1.0, 0.95}, FLOODLIGHT_INTENSITY, FLOODLIGHT_RANGE, FLOODLIGHT_INNER_ANGLE, FLOODLIGHT_OUTER_ANGLE))
	}

	// Jeep headlights: 2 spots, children of the jeep's own headlight NODES
	// (Session 5 gave these their own child nodes specifically so a light
	// could attach directly, unlike the tank's baked-in ones below) — local
	// offset (0,0,0) since the node's own position already IS the
	// headlight's position; local direction +Z, the jeep's own forward
	// (Objects.odin's build_jeep places both headlights and the windshield
	// at positive local Z).
	jeep_headlight_names := [2]string{"Jeep Headlight Left", "Jeep Headlight Right"}
	for name in jeep_headlight_names {
		node := find_node_or_panic(scene, name)
		append(&lights, Make_Spot(node, la.Vector3f32{0, 0, 0}, la.Vector3f32{0, 0, 1}, la.Vector3f32{1.0, 1.0, 0.9}, HEADLIGHT_INTENSITY, HEADLIGHT_RANGE, HEADLIGHT_INNER_ANGLE, HEADLIGHT_OUTER_ANGLE))
	}

	// Tank headlights: 2 spots, children of the HULL specifically (per the
	// task's own spec — the turret rotates independently and these must
	// NOT follow it). Baked-in offset, not a child node (Objects.odin's
	// build_tank: `{sign*HULL.x*0.35, TREAD_HEIGHT+HULL.y*0.75, HULL.z*0.5-0.15}`);
	// local direction +Z, the hull's own forward (same face the glacis
	// plate slopes toward).
	tank_hull := find_node_or_panic(scene, "Tank Hull")
	for side in 0 ..< 2 {
		sign: f32 = -1 if side == 0 else 1
		offset := la.Vector3f32{sign * scenepkg.TANK_HULL_SIZE.x * 0.35, scenepkg.TANK_TREAD_HEIGHT + scenepkg.TANK_HULL_SIZE.y*0.75, scenepkg.TANK_HULL_SIZE.z*0.5 - 0.15}
		append(&lights, Make_Spot(tank_hull, offset, la.Vector3f32{0, 0, 1}, la.Vector3f32{1.0, 1.0, 0.9}, HEADLIGHT_INTENSITY, HEADLIGHT_RANGE, HEADLIGHT_INNER_ANGLE, HEADLIGHT_OUTER_ANGLE))
	}

	// Tank turret searchlight: 1 spot, child of the TURRET (per the task's
	// spec — the clearest demonstration in the whole scene that a light
	// tracks its parent through an INDEPENDENT rotation on top of the
	// hull's own). Offset matches the searchlight housing baked into the
	// turret mesh (Objects.odin: `{-0.5, TURRET.y*0.5+0.1, 0}`); direction
	// +Z, the turret's own forward (matches the barrel).
	tank_turret := find_node_or_panic(scene, "Tank Turret")
	append(&lights, Make_Spot(tank_turret, la.Vector3f32{-0.5, scenepkg.TANK_TURRET_SIZE.y*0.5 + 0.1, 0}, la.Vector3f32{0, 0, 1}, la.Vector3f32{1.0, 1.0, 0.95}, SEARCHLIGHT_INTENSITY, SEARCHLIGHT_RANGE, SEARCHLIGHT_INNER_ANGLE, SEARCHLIGHT_OUTER_ANGLE))

	// Radar beacon: 1 point, child of the "Radar Beacon" node itself
	// (already its own child node of "Radar Mast", Session 5) — offset
	// (0,0,0), the node's own position already IS the beacon.
	radar_beacon := find_node_or_panic(scene, "Radar Beacon")
	append(&lights, Make_Point(radar_beacon, la.Vector3f32{0, 0, 0}, la.Vector3f32{1.0, 0.2, 0.2}, BEACON_INTENSITY, BEACON_RANGE))

	// Gun emplacement work light: 1 point, on its post — baked-in offset,
	// not a child node (Objects.odin's build_gun_emplacement: the post sits
	// at `{GUN_RING_RADIUS+0.5, GUN_WORK_LIGHT_POST_HEIGHT*0.5, 0}`
	// centred, so its TOP — where a work light would actually sit — is at
	// full GUN_WORK_LIGHT_POST_HEIGHT).
	gun_emplacement := find_node_or_panic(scene, "Gun Emplacement")
	append(&lights, Make_Point(gun_emplacement, la.Vector3f32{scenepkg.GUN_RING_RADIUS + 0.5, scenepkg.GUN_WORK_LIGHT_POST_HEIGHT, 0}, la.Vector3f32{1.0, 0.9, 0.7}, WORK_LIGHT_INTENSITY, WORK_LIGHT_RANGE))

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
