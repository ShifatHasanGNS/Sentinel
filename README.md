# SENTINEL — _"One Watchtower, Many Eyes."_

A real-time, night-time Forward Operating Base (FOB) renderer for a
university Computer Graphics course, written in **Odin** with **OpenGL +
GLSL** and **GLFW**. Vector/matrix math uses Odin's own `core:math/linalg`;
no scene-graph library, no precomputed geometry/light-position data —
everything else is generated at runtime.

Implementation follows the session plan in `Prompts.md`, in order, one
session at a time; see `PROGRESS.md` for exactly which roadmap steps are
done. As of the current session, all 9 scene objects, the full hierarchical
light rig (21 lights), barracks-window area-light sampling, and a live
Flat/Gouraud/Phong shading toggle are implemented and running.

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

## Controls

Free-fly camera controls (roadmap step 2) plus the debug/comparison toggles
added through roadmap step 8. Object selection/translate/rotate and the
remaining Inspection Mode state machine arrive in roadmap step 10 and will
be added to this table then, not replace it.

| Key / input      | Action                                                    |
| ---------------- | ---------------------------------------------------------- |
| `W` / `S`        | Move forward / backward (along the camera's full look direction, including pitch) |
| `A` / `D`        | Strafe left / right                                        |
| `Q` / `E`        | Move down / up (world space, independent of look direction) |
| Mouse             | Look (cursor is captured — move the mouse to turn/pitch)    |
| `Shift` (either)  | Sprint (multiplies move speed)                              |
| `P`               | Toggle perspective / orthographic projection                |
| Scroll wheel      | Zoom the orthographic volume (only while in orthographic projection) |
| `L`               | Toggle light gizmos (type-coded markers + aim lines for every active light) |
| `+` / `-` (or numpad `+`/`-`) | Increase / decrease barracks-window area-light sample count (1-8) |
| `J`               | Toggle per-pixel jitter on area-light sampling               |
| `1` / `2` / `3`   | Shading mode: Flat / Gouraud / Phong                        |
| `G`               | Toggle ground-grid resolution (1x1 quad vs. 24x24 subdivided grid) |
| `C`               | Cycle back-face culling: Off -> Manual (shader test) -> GL (hardware) |
| `Z`               | Toggle the depth test (hidden-surface removal)               |
| `X`               | Toggle grayscale linearised-depth visualisation               |
| `F`               | Toggle wireframe (`glPolygonMode`)                            |
| `B`               | Toggle a magenta tint on back-facing fragments (debug aid — see below) |
| `Esc`             | Quit                                                         |

All 6 toggles above (shading mode, cull mode, depth test, depth
visualisation, wireframe, backface-debug tint) are shown together in the
window title, e.g. `SENTINEL - Phong | Cull:GL Depth:On Wire:Off BFDbg:Off
DepthVis:Off` — this project has no on-screen text-rendering pipeline, so
the title bar is the readout.

CLI flags for `--capture` runs (see `Debug/README.md`):

| Flag                         | Effect                                                                 |
| ----------------------------- | ----------------------------------------------------------------------- |
| `--capture <frames> <path>`   | Render `frames` frames, save a screenshot to `path`, then exit          |
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

Interactive input (mouse look, WASD/QE movement, `P`, scroll, `L`, `+`/`-`,
`J`, `1`/`2`/`3`, `G`, `C`/`Z`/`X`/`F`/`B`) is intentionally disabled during
a `--capture` run so captured frames stay reproducible regardless of the
real system cursor/keyboard state — the CLI flags above are the supported
way to change what a capture run looks like instead.

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
two methods are exact.

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

## Syllabus coverage

See `CLAUDE.md` §4 for the full topic-to-implementation mapping. A final
version of this table, with evidence, belongs in this README by Session 16.

## Photon mapping

SENTINEL implements ray tracing (§6.2) and a path-tracing-style sampled area
light (§6.3) in the renderer, but treats photon mapping as a documentation-
only topic (§6.4) since it is fundamentally a batch/offline technique. That
write-up is added in Session 16 and lives in this README or `REPORT.md`.
