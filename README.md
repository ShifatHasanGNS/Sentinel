# SENTINEL — _"One Watchtower, Many Eyes."_

A real-time, night-time Forward Operating Base (FOB) renderer for a
university Computer Graphics course, written in **Odin** with **OpenGL +
GLSL** and **GLFW**. Vector/matrix math uses Odin's own `core:math/linalg`;
no scene-graph library, no precomputed geometry/light-position data —
everything else is generated at runtime.

Implementation follows the session plan in `Prompts.md`, in order, one
session at a time; see `PROGRESS.md` for exactly which roadmap steps are
done. As of the current session, all 9 scene objects, the full hierarchical
light rig (21 lights), barracks-window area-light sampling, back-face
culling/hidden-surface-removal demos, a formula-driven Patrol Mode, and a
full Inspection Mode (object selection, mouse picking, translate/rotate
editing) are implemented and running.

Note: `CLAUDE.md` §8/§13 sketch `Engine/`, `Geometry/`, and `Scene/` as
top-level siblings of `Source/`. This repo instead nests them one level
deeper under `Library/`, so the split is "executable (`Source/`) vs. library
code (`Library/*`)" rather than a flat list of packages at the root — a
deliberate, user-requested deviation from that suggested layout, not a
silent one. There is no `Math` package: `core:math/linalg` is allowed
directly (CLAUDE.md §2 item 3, updated from the project's original
hand-written-math constraint — see PROGRESS.md). Folder and Odin file names
throughout this repo use PascalCase, also by request.

## Start here

1. Read `CLAUDE.md` first — it is the authoritative guide for any coding
   assistant working in this repo, and states the hard constraints (§2) that
   override everything else.
2. Read `Requirements.md` (instructor + syllabus constraints) and `Plan.md`
   (design rationale) — source-of-truth documents `CLAUDE.md` defers to.
3. Read `PROGRESS.md` for the current session-to-session status (empty/fresh
   right now — this is session 0's job to fill in).
4. Follow `Prompts.md` session by session, starting with **Session 0**.

## Repository layout

```
Sentinel/
├── CLAUDE.md            # assistant instructions + hard constraints (read first)
├── Requirements.md      # instructor + syllabus constraints
├── Plan.md               # design plan and rationale
├── Prompts.md            # paste-ready per-session prompts, in build order
├── PROGRESS.md           # session-to-session handoff log (fill in as you go)
├── Library/               # library code, never built directly — consumed by Source/
│   ├── Engine/             # theme-agnostic OpenGL wrapper (from Engine.zip, audited)
│   │   ├── Shader/           # compile/link, uniform upload (core:math/linalg, as provided)
│   │   ├── VertexBuffer/
│   │   ├── IndexBuffer/
│   │   ├── VertexArray/
│   │   ├── VertexBufferLayout/
│   │   ├── Renderer/
│   │   └── Debugger/
│   ├── Geometry/           # theme-agnostic: cube/tetrahedron/plane generators + Append_Mesh
│   ├── Scene/              # SENTINEL-specific: transform hierarchy + the 9 objects
│   ├── Camera/             # SENTINEL-specific: free-fly + Patrol-Mode camera, projections
│   └── Lights/             # SENTINEL-specific: light structs, runtime placement/animation
├── Source/                 # main package: window, main loop, mode switching, input
├── Shaders/                 # hand-written GLSL, one combined file (see below)
└── Debug/                   # self-verification: --capture screenshot tooling
```

## Build / run

Confirmed on macOS (Apple Silicon) with the local Odin dev toolchain (see
`PROGRESS.md` "Environment" for exact versions):

```sh
odin build Source -out:Sentinel && ./Sentinel
# or, build-and-run in one step (note the `--` before program args):
odin run Source -out:Sentinel -- --capture 5 Debug/Captures/session0.bmp
```

`--capture <frames> <path>` renders that many frames, saves a screenshot,
and exits — see `Debug/README.md`.

## Modes (roadmap steps 9-10)

SENTINEL starts in **Patrol Mode** — a fully hands-off, formula-driven tour
(CLAUDE.md §7's "zero input required" framing) — and `Tab` switches to
**Inspection Mode**, the instructor's free-fly-plus-editing mode. Both modes
draw through the exact same render path (CLAUDE.md §2 item 9); only the
camera and a handful of node/light transforms are driven differently:

- **Patrol**: the camera flies a smooth circular path around the outside of
  the perimeter fence (with a gentle height bob), always looking toward a
  slowly drifting point near the base centre. The watchtower floodlight
  sweeps, the radar dish spins continuously, the beacon blinks, and three
  optional "life touches" run: the tank turret slowly scans, the jeep's
  headlights dip, and one fence lamp flickers. The tank hull and jeep root
  stay static, as asked.
- **Inspection**: free-fly camera (WASD/mouse/QE/Shift, `P`, scroll-zoom,
  unchanged from roadmap step 2) plus full object selection and editing
  (roadmap step 10, below).
- **Patrol's own animation drivers are frozen (not toggleable) the instant
  you switch to Inspection** — a deliberate decision, not an oversight:
  the floodlight/radar/beacon/turret-scan/jeep-dip/fence-flicker writes
  are gated to `current_mode == .Patrol` in `Source/Main.odin`'s main
  loop, so switching to Inspection simply stops writing them (they hold
  their last value, they don't reset to a rest pose) rather than fighting
  whatever the instructor is manually editing on the very same nodes.
  `animation_time` itself keeps advancing in the background either way
  (pausable only by `Space`), so resuming Patrol later doesn't feel stuck.
- Switching **Patrol -> Inspection** keeps the camera exactly where Patrol
  left it (both modes share one Camera value, so there's nothing to hand
  off). Switching **Inspection -> Patrol** solves a phase offset so the
  path "resumes from the nearest point" to wherever the free camera was,
  instead of jumping to wherever the shared clock's raw angle happens to be
  (`Library/Camera.Patrol_Nearest_Angle` — exact for this project's
  circular path, not an approximation).
- `Space` pauses the shared animation clock that drives every Patrol
  animation (works in either mode); `,`/`.` rescale its speed
  multiplicatively (x0.8 / x1.25 per press, clamped to [0.1x, 8x]).

## Inspection Mode: selection and editing (roadmap step 10)

12 nodes are selectable: the 9 root objects, plus 3 independently-movable
sub-nodes (Tank Turret, Watchtower Floodlight Head, Radar Dish) — see
`Source/Inspection.odin`'s `Build_Selectable_Nodes`. `[`/`]` cycle through
them; the selection also shows in the window title (`Sel:<name>`) and as a
pulsing cyan tint on the selected node, drawn through the exact same
`Scene.Draw_Node` path every other mesh uses (a temporarily brightened copy
of that node's own material, not a second render pass or an outline mesh).

**Mouse picking** is implemented for real — a genuine ray unprojected
through the inverse view-projection matrix at both the near and far planes,
tested against each selectable node's own local-space AABB (`Source/
Inspection.odin`'s `Screen_Point_To_Ray`/`Ray_Intersects_AABB`/`Pick_Node`,
covered by 7 unit tests in `Source/Inspection_test.odin`) — with one
deliberate, documented adaptation: it picks whatever's at the **viewport
centre**, not GLFW's live cursor position. Inspection's free-fly camera
runs with the cursor in `glfw.CURSOR_DISABLED` mode for unbounded mouse-
look, and GLFW's own docs describe the position reported in that mode as a
virtual accumulator, not a real on-screen pixel — unprojecting it would
pick whatever's under a meaningless number, not whatever's visually under
the cursor. A "look at it, left-click to select it" crosshair pick uses the
exact same ray/inverse-projection math a true cursor-position pick would,
and is a standard convention for exactly this kind of captured-cursor
camera.

Translate/rotate operate on the selected node's **LOCAL** transform, so
children and attached lights follow automatically — no separate "move the
light too" step exists because `Scene.Compute_World_Matrices` and
`Lights.Update_From_Scene` already recompute everything from local
transforms fresh every frame (CLAUDE.md §2 item 10, §5.3). Verified with
the tank specifically: rotating **Tank Hull** carries the turret (and
everything on it) with it; rotating **Tank Turret** afterward moves only
the turret, independently — both hull headlights and the turret searchlight
track correctly through either edit (see `Source/Inspection.odin`'s
headless test, and the `--test-inspection` section below).

| Key / input      | Action                                                    |
| ---------------- | ---------------------------------------------------------- |
| `[` / `]`         | Select previous / next object                               |
| Left click        | Pick the object at the screen centre (see above)             |
| `I` / `K`         | Translate selected object: local Z- / Z+                     |
| `J` / `L`         | Translate selected object: local X- / X+                     |
| `U` / `O`         | Translate selected object: local Y- / Y+ (up/down)            |
| `4` / `5`         | Rotate selected object: yaw- / yaw+ (local Y axis)            |
| `6` / `7`         | Rotate selected object: pitch- / pitch+ (local X axis)        |
| `8` / `9`         | Rotate selected object: roll- / roll+ (local Z axis)           |
| `;` / `'`         | Decrease / increase the translate+rotate step size (x0.8 / x1.25) |
| `0`               | Reset the selected object to its original transform           |
| `Shift`+`0`       | Reset **all** objects to their original transforms            |
| `H`               | Print the full control list to the console                    |

All of the above only take effect in Inspection Mode — pressed during
Patrol, they're discarded (not queued) rather than replaying once you
switch modes later.

**A key was deliberately moved:** area-light jitter is now `N`, not `J` —
this session's task names `IJKL` specifically for the translate cluster,
and `J` was already claimed by Session 9's jitter toggle. Reassigned, not
silently dropped; the printed control list and this table are both
up to date.

## Controls

Free-fly camera, Patrol/Inspection mode, and the debug/comparison toggles
from roadmap step 8. See the section above for the Inspection-only
selection/editing keys.

| Key / input      | Action                                                    |
| ---------------- | ---------------------------------------------------------- |
| `Tab`             | Switch Patrol <-> Inspection Mode                           |
| `Space`           | Pause / resume the shared animation clock (either mode)      |
| `,` / `.`         | Slow down / speed up the shared animation clock (x0.8 / x1.25 per press) |
| `W` / `S`        | (Inspection) Move forward / backward (along the camera's full look direction, including pitch) |
| `A` / `D`        | (Inspection) Strafe left / right                            |
| `Q` / `E`        | (Inspection) Move down / up (world space, independent of look direction) |
| Mouse             | (Inspection) Look (cursor is captured — move the mouse to turn/pitch) |
| `Shift` (either)  | (Inspection) Sprint (multiplies move speed)                  |
| `P`               | Toggle perspective / orthographic projection (either mode)   |
| Scroll wheel      | Zoom the orthographic volume (only while in orthographic projection; either mode) |
| `L`               | Toggle light gizmos (type-coded markers + aim lines for every active light) |
| `+` / `-` (or numpad `+`/`-`) | Increase / decrease barracks-window area-light sample count (1-8) |
| `N`               | Toggle per-pixel jitter on area-light sampling (moved from `J`, see above) |
| `1` / `2` / `3`   | Shading mode: Flat / Gouraud / Phong                        |
| `G`               | Toggle ground-grid resolution (1x1 quad vs. 24x24 subdivided grid) |
| `C`               | Cycle back-face culling: Off -> Manual (shader test) -> GL (hardware) |
| `Z`               | Toggle the depth test (hidden-surface removal)               |
| `X`               | Toggle grayscale linearised-depth visualisation               |
| `F`               | Toggle wireframe (`glPolygonMode`)                            |
| `B`               | Toggle a magenta tint on back-facing fragments (debug aid — see below) |
| `R`               | Toggle ray-traced reflection on the 5 glass surfaces (see below) |
| `M`               | Toggle tonemapping + gamma correction (see Polish pass below) |
| `V`               | Toggle vignette                                              |
| `Y`               | Toggle night fog/haze                                        |
| `T`               | Toggle ground procedural detail (dirt/gravel)                |
| `/`               | Toggle sky gradient + procedural stars                       |
| `Esc`             | Quit                                                         |

Mode, selected-object name (Inspection only), shading mode, animation pause
state/speed, every roadmap-step-8 toggle, reflection, all 5 polish
toggles, and a live FPS readout are all shown together in the window
title, e.g. `SENTINEL - Inspection - Phong | Speed:1.00x Cull:GL Depth:On
Wire:Off BFDbg:Off DepthVis:Off Refl:On Tone:On Vig:On Fog:On Grnd:On
Sky:On FPS:60 Sel:Tank Turret` — this project has no on-screen text-
rendering pipeline, so the title bar (plus `H`'s printed list) is the
readout.

CLI flags for `--capture` runs (see `Debug/README.md`):

| Flag                         | Effect                                                                 |
| ----------------------------- | ----------------------------------------------------------------------- |
| `--capture <frames> <path>`   | Render `frames` frames, save a screenshot to `path`, then exit          |
| `--test-inspection <prefix>`  | Run the headless rotate-the-turret test (see below) instead of the normal loop |
| `--mode <patrol\|inspection>` | Starting Mode (default `patrol`)                                        |
| `--patrol-speed <scale>`      | Starting animation clock speed multiplier (default `1.0`)               |
| `--projection <perspective\|orthographic>` | Starting projection mode (default `perspective`) |
| `--gizmos`                    | Start with light gizmos visible                                        |
| `--area-samples <N>`          | Starting barracks-window area-light sample count, 1-8 (default 4)      |
| `--area-jitter`               | Start with area-light per-pixel jitter enabled                         |
| `--shading <flat\|gouraud\|phong>` | Starting shading mode (default `phong`)                          |
| `--ground-resolution <low\|high>` | Starting ground-grid resolution (default `low`, i.e. 1x1)         |
| `--cull <off\|manual\|gl>`    | Starting cull mode (default `gl`)                                      |
| `--depth-test <on\|off>`      | Starting depth-test state (default `on`)                               |
| `--wireframe`                 | Start with wireframe on                                                |
| `--backface-debug`            | Start with the magenta back-face tint on                               |
| `--depth-visualization`       | Start with the grayscale depth view on                                 |
| `--reflection <on\|off>`      | Starting ray-traced reflection state (default `on`)                    |
| `--tonemapping <on\|off>`     | Starting tonemapping + gamma state (default `on`)                       |
| `--vignette <on\|off>`        | Starting vignette state (default `on`)                                 |
| `--fog <on\|off>`             | Starting night fog/haze state (default `on`)                           |
| `--ground-detail <on\|off>`   | Starting ground procedural detail state (default `on`)                 |
| `--sky <on\|off>`             | Starting sky gradient + stars state (default `on`)                     |
| `--benchmark <frames>`        | Disables vsync, measures `frames` frames (first 10 excluded as warm-up), prints avg/min/max frame time + FPS, then exits — see Polish pass below |
| `--msaa <N>`                  | Requests an N-sample multisampled framebuffer (e.g. `--msaa 4`) — START-ONLY, no live key; see Polish pass below for why |

Interactive input (`Tab`, `Space`, `,`/`.`, mouse look, WASD/QE movement,
`P`, scroll, `L`, `+`/`-`, `N`, `1`/`2`/`3`, `G`, `C`/`Z`/`X`/`F`/`B`, `R`,
`M`/`V`/`Y`/`T`/`/`, and every Inspection selection/editing key) is
intentionally disabled during a
`--capture` run so captured frames stay reproducible regardless of the real
system cursor/keyboard state — the CLI flags above are the supported way to
change what a capture run looks like instead.

## Headless Inspection test (`--test-inspection`)

```sh
./Sentinel --test-inspection Debug/Captures/turret_test
```

Runs a scripted sequence through the SAME code paths the interactive
controls use (`Apply_Rotate`, `Scene.Compute_World_Matrices`,
`Lights.Update_From_Scene`, `draw_scene_nodes`) rather than a separate
mock: selects Tank Turret, records the turret searchlight's world position
and its distance from the turret's own pivot, renders `<prefix>_before.bmp`,
rotates the turret 90 degrees about its local Y axis, re-records both
values, renders `<prefix>_after.bmp`, and asserts two things — the
searchlight moved by more than a small threshold (it isn't a no-op), and
its distance from the turret's pivot barely changed (it moved like a
rotation about that pivot, not some unrelated translation). Prints
`PASS`/`FAIL` with the actual numbers and exits `0`/`1`.

## Back-face culling and hidden-surface removal (roadmap step 8)

Two syllabus topics, both demonstrable live (`Shaders/Scene.glsl`,
`Source/Main.odin`):

**Back-face culling** solves a wasted-work problem: on a closed, watertight
object, roughly half of every triangle faces AWAY from the camera and can
never be seen no matter what — drawing it anyway (shading it, testing it
against the depth buffer) is pure waste. SENTINEL implements it two ways so
they can be compared directly (`C` key, or `--cull`):
- **Manual** — the fragment shader computes `dot(face normal, direction to
  the eye)` for every fragment and `discard`s the ones facing away
  (`is_back_facing` in `Scene.glsl`'s fragment `main()`). "Direction to the
  eye" is NOT the same formula in both projections: in perspective the eye
  is a finite point, so the direction varies per fragment
  (`normalize(u_ViewPosition - world_position)`); in orthographic every view
  ray is parallel, so it's one constant vector (the negated camera forward)
  for the whole screen. This reaches the exact same final image as hardware
  culling (confirmed below) but costs almost nothing less than drawing
  everything — the rasterizer and fragment shader still run for every
  back-facing fragment right up until the `discard`.
- **GL (hardware)** — `gl.Enable(gl.CULL_FACE)`. The GPU's rasterizer
  classifies a triangle by its projected winding order and throws away a
  back-facing one BEFORE the fragment shader ever runs for it. This is
  where the real performance saving is. A startup log line
  (`count_back_facing_triangles`, `Source/Main.odin`) estimates this
  concretely for one object (the watchtower): from the default camera pose,
  114 of its 228 triangles (~50%) are back-facing — hardware culling skips
  fragment-shader work for roughly half of it, for free.

Verified pixel-for-pixel: capturing the same frame under Manual and GL
culling and diffing the two BMPs shows them identical across 99.97% of
pixels (2,560x1,440); the only differing pixels (1,153 of them) sit exactly
on the radar dish's silhouette — the one object with smooth, per-vertex
normals (`Geometry.Smooth_Cylinder_Normals`) rather than the flat, per-face
normals every other object uses. That's expected, not a bug: a per-fragment
*normal* dot-product test and a per-triangle *winding* test are two related
but not identical measurements, and they can disagree by a pixel right at a
smoothly-curved silhouette edge where the interpolated normal doesn't quite
match the true triangle plane. On every flat-faced object in the scene the
two methods are exact. Re-verified the same way under `--projection
orthographic` specifically (direction-to-eye uses a different, constant-
per-screen formula there — see below): same story, same object, same
~0.03% of pixels.

**Debug view (`B`, `--backface-debug`):** independent of `C`, tints a
back-facing fragment magenta instead of its normal shaded colour. Most
useful together with culling **Off** and the depth test **Off** (`Z`) —
with nothing removing back faces AND nothing ordering overlapping
triangles correctly, the image becomes a genuinely confusing jumble of
front and back surfaces in arbitrary draw order (see
`Debug/Captures/session11_crate_broken.png` vs.
`session11_crate_normal.png` for a close-up of a simple crate box breaking
apart this way); the magenta tint (`session11_crate_broken_debug.png`)
identifies exactly which triangles are responsible.

**Hidden-surface removal** solves a different problem: even among the
FRONT-facing triangles a camera can see, which one is actually nearest for
a given pixel? SENTINEL uses the GPU's own depth (z-)buffer — enabled by
default, toggleable with `Z` (`--depth-test`) — which for every fragment
compares its own depth against whatever's already been written to that
pixel and keeps only the nearer one, regardless of draw order. Turning it
off (together with culling) is exactly the "looks visibly wrong" state
above.

**Depth visualisation (`X`, `--depth-visualization`)** replaces the lit
image with a grayscale picture of the depth buffer itself — near = dark,
far = light — so the z-buffer's actual per-fragment values are visible, not
just their effect. The linearisation is hand-derived in `Scene.glsl`'s
fragment `main()`, not sampled from a second depth-texture pass:
`gl_FragCoord.z` is window-space depth in `[0, 1]` (OpenGL's own
`glDepthRange` default), first mapped back to this project's NDC convention
(`Library/Camera/Camera.odin`'s documented near -> -1, far -> +1), then
un-projected. Perspective's NDC z is a *hyperbolic* function of view-space
distance (the projection matrix divides by `w = -view_z`), so that specific
formula is inverted; orthographic has no such divide, so NDC z is already
linear and only needs an affine remap back to `[near, far]` — two different
formulas for two different reasons, picked by `u_IsOrthographic`.

**Wireframe (`F`, `--wireframe`)** — `gl.PolygonMode(gl.FRONT_AND_BACK,
gl.LINE)` — draws only triangle edges, the classic way to inspect a mesh's
actual triangulation (segment counts, winding, where Append_Mesh seams
land) independent of shading.

See `Debug/Captures/session11_*.png` for the captured comparison set: the
default view (`session11_default.png`), Manual vs. GL culling
(`session11_cull_manual.png`/`session11_cull_gl.png`), the depth
visualisation (`session11_depth_vis.png`), wireframe
(`session11_wireframe.png`), and the crate close-up sequence described
above.

## Ray-traced reflection (roadmap step 11)

Five glass surfaces in the scene — the jeep windshield, the tank
periscope, and all 3 barracks windows — are genuinely ray-traced, not
faked with a reflection cubemap or screen-space trick, toggleable live
with `R` (or `--reflection on|off`, default on).

Every frame, `Source/Reflection.odin` rebuilds a compact array of up to 11
proxy shapes (spheres, boxes, capped cylinders) approximating the scene's
other 8 objects, fresh from their live world transforms — never cached, so
a proxy always tracks wherever its real object currently is, whether
that's a static placement, an ongoing Patrol animation, or a mid-demo
Inspection-Mode edit. For a fragment on one of the 5 reflective surfaces,
`Shaders/Scene.glsl` casts the classic ray-tracing pipeline explicitly:

- **Primary ray** — implicit; the fragment being shaded IS a rasterized
  primary ray's hit point.
- **Secondary (reflection) ray** — cast explicitly via GLSL's `reflect()`
  around the surface normal.
- **Intersection tests** — analytic (closed-form) ray-sphere, ray-box
  (slab method, in the proxy's own local space), and ray-capped-cylinder
  tests against every proxy; the nearest hit wins. No acceleration
  structure needed at this object count (~11 proxies, a plain loop).
- **Shading at the hit** — the hit point is shaded with the exact same
  lighting function every rasterized fragment already uses, not a
  separate reflection-only model.
- **Bonus: a hard shadow ray** from the hit point toward the moonlight,
  against the same proxy array — free reuse of the same intersection
  routines, darkening a reflection that's itself in shadow.

A miss (or nothing within range) returns a flat night-sky colour. The
result is blended against the surface's own rasterized colour with a
Fresnel-Schlick approximation — more reflective at a grazing viewing
angle, less reflective straight-on, the same effect that makes a lake look
like a mirror far away but see-through right at your feet.

**Scope note:** originally planned as a single surface (CLAUDE.md §6.2),
extended to all 5 glass surfaces by explicit user decision this session —
see `PROGRESS.md`'s Session 14 entry for the reasoning. The effect is
verified correct (proxy data, intersection math, and the per-frame
tracking are each independently checked — see `Source/Reflection_test.odin`
and PROGRESS.md) but is visually subtle in places: the windshield's and
periscope's own outward-facing orientation means their reflection rays
often miss the proxy cluster entirely, and the barracks windows' warm
emissive glow (they're also §6.3 area lights) tends to outweigh the
blended reflection. `Debug/Captures/session14_reflection_on.png` vs.
`session14_reflection_off.png` (a grazing angle on the barracks windows)
shows a real, measurable difference.

## Polish pass

A set of purely visual finishing touches, every one independently
toggleable (live key + `--flag <on|off>`, default ON) so none of them can
ever obstruct verifying a required feature — turning ALL of them off
reproduces this project's exact pre-polish output byte-for-byte (see
`PROGRESS.md`'s Polish pass entry for the pixel-diff evidence).

- **Tonemapping + gamma (`M`)** — Reinhard (`color/(color+1)`) compresses
  unbounded-bright values (overlapping spotlights, emissive glass) with a
  smooth shoulder instead of a hard clip, then a standard 2.2 gamma power
  re-encodes for display. Every colour in this shader is authored and
  mixed in LINEAR space throughout; this is the ONE place that leaves it.
- **Vignette (`V`)** — a subtle screen-space darkening toward the corners
  (down to 55% brightness at the extreme corner, never near-black).
- **Night fog/haze (`Y`)** — exponential distance fog toward the same sky
  colour a reflection miss already uses, softening the fence line and
  beyond without ever fully flattening anything into one flat colour.
- **Ground procedural detail (`T`)** — two octaves of hash-based value
  noise (reusing the same `hash21` function this shader's area-light
  jitter already relies on, CLAUDE.md §2 item 5's "formula, not texture"
  rule) tint the ground plane with a patchy dirt/gravel look.
- **Sky gradient + procedural stars (`/`)** — an oversized `Geometry.Cube`
  (still one of the three base primitives), re-centred on the camera every
  frame and drawn first as a skybox. A direction-based gradient plus a
  sparse, twinkling procedural starfield — every star a small hashed POINT
  within a direction-space grid cell (not the whole cell lit solid, which
  looked blocky from a near-vertical view — caught and fixed via a
  dedicated straight-up test capture, `Debug/Captures/
  polish_sky_stars.png`).
- **Live FPS readout (window title)** — a rolling average over 0.5s, no
  dedicated toggle since it draws nothing into the framebuffer for a
  toggle to obstruct.
- **`--benchmark <frames>`** — disables vsync, measures steady-state frame
  time (excluding a 10-frame warm-up), reports avg/min/max ms and FPS and
  whether the 60 FPS (16.7ms) budget is held. Result on this machine:
  **67.1 FPS average (14.9ms), 1.77ms of budget to spare** at 2560x1440 in
  Patrol Mode — comfortably over target, no optimisation pass needed.
- **`--msaa <N>`** — multisample anti-aliasing. The one item here that's
  genuinely START-ONLY, not a live key: the sample count is baked into the
  GL context's default framebuffer at window-creation time, and OpenGL has
  no call to change it afterward without recreating the window.

**Not implemented: full bloom** (threshold + blur + composite via extra
framebuffers). CLAUDE.md §6.1 already lists it as "nice-to-have only";
it's also the one candidate needing genuinely new `Engine` infrastructure
(an FBO/render-target abstraction this project doesn't have yet) rather
than a shader-only addition — cut in favour of not rushing new engine
architecture for a nice-to-have, especially once tonemapping was already
handling bloom's usual "blown-out highlights" motivation. See
`PROGRESS.md`'s Polish pass entry for the full reasoning.

## Syllabus coverage

See `CLAUDE.md` §4 for the full topic-to-implementation mapping. A final
version of this table, with evidence, belongs in this README by Session 16.

## Photon mapping

SENTINEL implements ray tracing (§6.2) and a path-tracing-style sampled area
light (§6.3) in the renderer, but treats photon mapping as a documentation-
only topic (§6.4) since it is fundamentally a batch/offline technique. That
write-up is added in Session 16 and lives in this README or `REPORT.md`.
