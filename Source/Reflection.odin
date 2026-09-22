// Reflection.odin — the ray-traced reflection system's CPU-side half
// (roadmap step 11, CLAUDE.md §6.2; Prompts.md Session 14). Shaders/
// Scene.glsl's fragment stage does the actual ray casting; this file's
// only job is building the compact PROXY ARRAY those rays test against,
// fresh from live object transforms every frame (CLAUDE.md §2 item 10 —
// the same "never cache scene data, recompute from the live world matrix"
// rule this project already applies to lights and mesh transforms, now
// applied to reflection proxies too), and uploading it.
//
// This session's own decision (the user, after seeing scouting captures
// of both candidates and being shown the tradeoffs): EVERY glass surface
// is reflective, not CLAUDE.md §6.2's originally-scoped single surface —
// the jeep windshield, the tank periscope (re-angled in Library/Scene/
// Objects.odin so it aims outward instead of at the sky), and all 3
// barracks windows. See PROGRESS.md's Session 14 entry for the full
// reasoning and PROGRESS.md's open-items table for the resolved decision.
package main

import "core:fmt"
import la "core:math/linalg"
import "core:strings"

import scenepkg "../Library/Scene"
import sd "../Library/Engine/Shader"

// REFLECTIVE_NODE_NAMES are the nodes whose Material.Reflective gets set
// true once, at startup (Source/Main.odin, right after Build_Scene) — not
// a build-time Objects.odin concern (Library/Scene must stay agnostic
// about which of ITS nodes a later session decides to ray-trace), the
// same "Source decides, by name, after the fact" split Patrol/Inspection's
// own node lookups already use.
REFLECTIVE_NODE_NAMES :: [5]string{"Jeep Windshield", "Tank Periscope", "Barracks Window 1", "Barracks Window 2", "Barracks Window 3"}

// MAX_PROXIES must match Shaders/Scene.glsl's #define MAX_PROXIES — same
// cross-language sync situation as MAX_LIGHTS (Library/Lights.odin's own
// header comment).
MAX_PROXIES :: 16

Proxy_Type :: enum i32 {
	Sphere   = 0,
	Box      = 1,
	Cylinder = 2,
}

// Proxy mirrors Shaders/Scene.glsl's `Proxy` struct field-for-field.
// InverseWorld is the WORLD -> LOCAL transform (Box/Cylinder tests happen
// in the proxy's own local space, where it's simply axis-aligned — the
// same "transform the ray into local space instead of transforming the
// shape into world space" trick Source/Inspection.odin's mouse-picking
// AABB test already uses); Center is redundant with InverseWorld for
// Box/Cylinder (their local-space test never reads it) but is what Sphere
// tests use directly, since a sphere is identical in local and world
// space and doesn't need the extra matrix multiply.
Proxy :: struct {
	Type:         Proxy_Type,
	Center:       la.Vector3f32,
	InverseWorld: la.Matrix4f32,
	HalfExtents:  la.Vector3f32, // Box: local half-size XYZ. Cylinder: (radius, half-height, unused). Sphere: (radius, unused, unused).
	Color:        la.Vector3f32,
}

// proxy_def is a FIXED description of one proxy shape — which node it
// rides on, its type, a local-space offset from that node's own origin,
// and its half-extents/color. Resolved to a node INDEX once at startup
// (Build_Proxy_Defs); Build_Proxies below re-derives every proxy's actual
// Center/InverseWorld from that node's CURRENT world matrix every single
// frame, so a proxy always tracks wherever its real object currently is —
// static placement, Patrol animation, or a live Inspection-Mode edit, all
// the same code path. Exported (not file-private) because Source/
// Main.odin holds the resolved `[11]Proxy_Def` between Build_Proxy_Defs'
// one-time call and every frame's Build_Proxies call.
Proxy_Def :: struct {
	node_name:    string,
	node_index:   int, // resolved once by Build_Proxy_Defs; scenepkg.NO_PARENT until then
	type:         Proxy_Type,
	local_offset: la.Vector3f32,
	half_extents: la.Vector3f32,
	color:        la.Vector3f32,
}

// Build_Proxy_Defs resolves every proxy_def's node name to a Scene node
// index ONCE at startup — a compact, hand-picked approximation of the
// scene's OTHER 8 objects (every object except whichever one owns the
// reflective surface currently being shaded, which Shaders/Scene.glsl's
// trace_reflection skips via its own hit-index check to avoid a glass
// surface immediately reflecting its own housing at t~=0), not a literal
// per-triangle stand-in — CLAUDE.md §2 item 6's spirit ("standard
// complexity", not photorealism) applied to reflection proxies exactly as
// it already applies to the visible geometry itself. The Perimeter Fence
// is deliberately NOT included: a thin, mostly-flat loop around the whole
// base contributes little to a close-up reflection and would need its own
// per-segment proxy list to approximate honestly, not worth the uniform
// budget for this demo.
Build_Proxy_Defs :: proc(scene: ^scenepkg.Hierarchy) -> [11]Proxy_Def {
	defs := [11]Proxy_Def{
		{"Watchtower", 0, .Cylinder, {0, scenepkg.TOWER_HEIGHT * 0.5, 0}, {0.4, scenepkg.TOWER_HEIGHT * 0.5, 0.4}, scenepkg.COLOR_TOWER},
		{"Watchtower", 0, .Box, {0, scenepkg.TOWER_HEIGHT + 0.3, 0}, {scenepkg.TOWER_PLATFORM_SIZE * 0.5, 0.5, scenepkg.TOWER_PLATFORM_SIZE * 0.5}, scenepkg.COLOR_TOWER},
		{"Jeep", 0, .Box, {0, scenepkg.JEEP_WHEEL_RADIUS + scenepkg.JEEP_BODY_SIZE.y*0.5, 0}, scenepkg.JEEP_BODY_SIZE * 0.5, scenepkg.COLOR_JEEP},
		{"Sandbag Bunker", 0, .Box, {0, scenepkg.BUNKER_ROW_HEIGHT * 3, 0}, {scenepkg.BUNKER_HALF_WIDTH, scenepkg.BUNKER_ROW_HEIGHT * 3, scenepkg.BUNKER_HALF_DEPTH}, scenepkg.COLOR_SANDBAG},
		{"Radar Mast", 0, .Cylinder, {0, scenepkg.RADAR_MAST_HEIGHT * 0.5, 0}, {0.15, scenepkg.RADAR_MAST_HEIGHT * 0.5, 0.15}, scenepkg.COLOR_RADAR_MAST},
		{"Radar Mast", 0, .Sphere, {0, scenepkg.RADAR_MAST_HEIGHT, 0}, {scenepkg.RADAR_DISH_RADIUS, 0, 0}, scenepkg.COLOR_RADAR_DISH},
		{"Barracks Hut", 0, .Box, {0, scenepkg.BARRACKS_SIZE.y * 0.5, 0}, scenepkg.BARRACKS_SIZE * 0.5, scenepkg.COLOR_BARRACKS},
		{"Cargo Crate Stack", 0, .Box, {0, scenepkg.CRATE_BASE_SIZE * 1.5, 0}, {scenepkg.CRATE_BASE_SIZE * 1.2, scenepkg.CRATE_BASE_SIZE * 1.5, scenepkg.CRATE_BASE_SIZE * 1.2}, scenepkg.COLOR_CRATE},
		{"Tank Hull", 0, .Box, {0, scenepkg.TANK_TREAD_HEIGHT + scenepkg.TANK_HULL_SIZE.y*0.5, 0}, scenepkg.TANK_HULL_SIZE * 0.5, scenepkg.COLOR_TANK},
		{"Tank Turret", 0, .Box, {0, 0, 0}, scenepkg.TANK_TURRET_SIZE * 0.5, scenepkg.COLOR_TANK},
		{"Gun Emplacement", 0, .Sphere, {0, scenepkg.GUN_TRIPOD_HEIGHT * 0.5, 0}, {scenepkg.GUN_RING_RADIUS * 0.6, 0, 0}, scenepkg.COLOR_SANDBAG},
	}

	for &def in defs {
		index := scenepkg.Find_Node(scene, def.node_name)
		if index == scenepkg.NO_PARENT {
			panic("Source/Reflection.odin: Build_Proxy_Defs found a node name with no matching Scene node — Objects.odin and this list have drifted out of sync")
		}
		def.node_index = index
	}

	return defs
}

// Build_Proxies recomputes every proxy's Center/InverseWorld from `defs`'
// node's CURRENT world matrix — called every frame (Source/Main.odin),
// never cached, so a proxy always reflects wherever its real object
// currently is: static placement, a live Patrol animation (the turret's
// own scan, for instance), or a mid-demo Inspection-Mode edit.
Build_Proxies :: proc(defs: []Proxy_Def, world_matrices: []la.Matrix4f32) -> [dynamic]Proxy {
	proxies := make([dynamic]Proxy, 0, len(defs))
	for def in defs {
		world := la.mul(world_matrices[def.node_index], la.matrix4_translate(def.local_offset))
		append(&proxies, Proxy{
			Type         = def.type,
			Center       = scenepkg.World_Position(world),
			InverseWorld = la.matrix4_inverse(world),
			HalfExtents  = def.half_extents,
			Color        = def.color,
		})
	}
	return proxies
}

@(private = "file")
Proxy_Uniform_Names :: struct {
	Type, Center, InverseWorld, HalfExtents, Color: string,
}

@(private = "file")
proxy_uniform_names: [MAX_PROXIES]Proxy_Uniform_Names
@(private = "file")
proxy_uniform_names_ready: bool

// build_proxy_uniform_names formats every "u_Proxies[i].field" name ONCE,
// the exact same reasoning (and the exact same UniformLocationCache-
// missing-every-frame failure mode it avoids) as Library/Lights.odin's own
// build_uniform_names — see that proc's comment for the full explanation,
// not repeated here.
@(private = "file")
build_proxy_uniform_names :: proc() {
	if proxy_uniform_names_ready do return

	for i in 0 ..< MAX_PROXIES {
		prefix := fmt.tprintf("u_Proxies[%d]", i)
		proxy_uniform_names[i] = Proxy_Uniform_Names{
			Type         = strings.clone(fmt.tprintf("%s.type", prefix)),
			Center       = strings.clone(fmt.tprintf("%s.center", prefix)),
			InverseWorld = strings.clone(fmt.tprintf("%s.inverseWorld", prefix)),
			HalfExtents  = strings.clone(fmt.tprintf("%s.halfExtents", prefix)),
			Color        = strings.clone(fmt.tprintf("%s.color", prefix)),
		}
	}

	proxy_uniform_names_ready = true
}

// Upload_Proxies writes `proxies` (clamped to MAX_PROXIES) into the
// shader's u_Proxies array plus u_ProxyCount.
Upload_Proxies :: proc(shader: ^sd.Shader, proxies: []Proxy) {
	build_proxy_uniform_names()

	upload_count := min(len(proxies), MAX_PROXIES)
	for i in 0 ..< upload_count {
		proxy := proxies[i]
		names := proxy_uniform_names[i]

		sd.SetUniform(shader, names.Type, i32(proxy.Type))
		sd.SetUniform(shader, names.Center, proxy.Center.x, proxy.Center.y, proxy.Center.z)
		inverse_world := proxy.InverseWorld
		sd.SetUniform(shader, names.InverseWorld, &inverse_world)
		sd.SetUniform(shader, names.HalfExtents, proxy.HalfExtents.x, proxy.HalfExtents.y, proxy.HalfExtents.z)
		sd.SetUniform(shader, names.Color, proxy.Color.x, proxy.Color.y, proxy.Color.z)
	}

	sd.SetUniform(shader, "u_ProxyCount", i32(upload_count))
}
