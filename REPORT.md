# REPORT.md — SENTINEL Rendering Techniques

This document covers the parts of the syllabus that are more naturally
explained in prose than shown in a control-scheme table: how SENTINEL's
four rendering techniques (rasterization, ray tracing, path tracing,
photon mapping) relate to each other and to the code, an honest
photon-mapping extension write-up (not implemented — see why below), and
plain-language explanations of the core graphics concepts, written to
double as viva notes. Every explanation below names the actual file and
procedure it's talking about, not just the concept in the abstract.

See `README.md` for controls, build steps, and the full syllabus-topic
table; see `PROGRESS.md` for the session-by-session build history and
verification evidence behind every claim made here.

---

## 1. Rasterization vs. ray tracing vs. path tracing vs. photon mapping

All four answer the same underlying question — "what colour does this
pixel/surface point actually see?" — but differ in *how they find out*,
and each one appears in SENTINEL at the scope that's actually honest for a
real-time renderer at this object count, not faked at a scope it can't
really support.

| Technique | Core idea | Cost model | Where it lives in SENTINEL |
| --- | --- | --- | --- |
| **Rasterization** | Project every triangle to screen space, fill the pixels it covers, shade each covered pixel independently. No notion of "what else is in the scene" beyond the depth buffer. | Cost scales with triangle/fragment count. Real-time at any reasonable scene size — this is why every interactive renderer (games, SENTINEL's own baseline) uses it. | The baseline for 100% of every frame: `Shaders/Scene.glsl`'s vertex/fragment pipeline, `compute_lighting`, both Modes. |
| **Ray tracing** | Explicitly cast a ray from a point (not necessarily the eye) in some direction and ask "what does it hit?" via geometric intersection tests. Naturally answers reflections/refractions/shadows that rasterization can't see past the current pixel's own surface. | Cost scales with (rays cast) x (objects tested per ray), which is why a full-scene ray tracer needs an acceleration structure (BVH, kd-tree) at any real object count — SENTINEL's ~11-proxy scene doesn't. | Scoped to 5 reflective glass surfaces: `Source/Reflection.odin` (proxy shapes) + `Shaders/Scene.glsl`'s `trace_reflection` (the actual ray casts). Genuinely ray-traced, not a cubemap or screen-space trick — just deliberately NOT applied to the whole frame, because nothing else in this scene needs it and doing so would cost real performance margin (see `PROGRESS.md`'s benchmark numbers) for no visible gain. |
| **Path tracing** | Monte Carlo integration of the full rendering equation: for each shading point, sample many random directions (or many points across an area light), average the results, and let noise converge to the correct answer over many samples/frames. The general technique behind physically-based light transport, including indirect (bounced) light. | Cost scales with (samples per pixel) x (bounces per sample), which is why offline path tracers render for minutes-to-hours per frame and real-time ones need denoising/temporal accumulation tricks SENTINEL doesn't attempt. | Scoped to one bounded piece: the barracks window area lights sample 4-8 points across each window's current world-space quad every frame and average their Blinn-Phong contribution (`Shaders/Scene.glsl`'s `area_light_contribution`) — single bounce (direct light only), fixed sample count, optionally jittered per-pixel (`N` key) so the sampling pattern doesn't look like a rigid grid. This is exactly path tracing's *direct-light sampling step*, just not extended to indirect bounces or unbounded sample counts. |
| **Photon mapping** | A two-pass, *offline* global-illumination technique: emit photons from every light, trace and store where they land (with bounces) in a spatial structure, then gather nearby stored photons at render time to estimate indirect light density at any point. | Cost is dominated by the emission pass (however many photons are needed for the stored map to be dense enough) and is fundamentally NOT per-frame — the map is built once, offline, then reused. | **Not implemented.** Documented only — see §2 below for the full extension this project would need, and why building even a scaled-down live version would contradict CLAUDE.md's own "recomputed every frame, nothing cached as static data" rule (§2 item 10) that governs everything else in this codebase. |

The throughline: SENTINEL's answer to "how do ray/path/photon-mapping
topics fit a real-time OpenGL rasterizer" is *scope each one down to
exactly the piece that's genuinely real-time-honest at this object count*,
rather than either skipping the topic or faking a technique's effect
without actually implementing its mechanism. Reflection is really ray
tracing, just on 5 surfaces instead of the whole frame. The area lights
are really Monte Carlo sampling, just for direct light only. Photon
mapping is the one topic that has no honest real-time-at-this-scope
version — so it gets documented instead of faked.

---

## 2. Photon Mapping — how SENTINEL would extend

### 2.1 Why it's not implemented in the renderer

Photon mapping (Jensen, 1996) is fundamentally a **batch/offline**
technique: it has two distinct passes that must run in sequence, and the
first pass has no notion of "the camera" or "this frame" at all — it's
scene-wide and light-driven, not view-driven. Baking even a coarse version
of that into a 60 FPS interactive loop would mean either (a) rebuilding
the whole photon map every single frame, which is far too expensive for
real-time at any reasonable photon count, or (b) building it once and
reusing it, which would directly violate the "never calculate something
once and reuse it as though it were static data" rule (`CLAUDE.md` §2 item
10) that this project holds every light position and geometry transform to
consistently elsewhere. Neither option is honest, so rather than fake a
watered-down version that technically runs at 60 FPS but doesn't actually
demonstrate the real technique, this section documents how it would
genuinely work and what would need to change.

### 2.2 The four stages

**1. Photon emission.** For every light in the scene (`Library/Lights`'
21 active `Light`s — point, spot, area, directional), emit some number of
photons in random directions weighted by that light's own emission
profile: a point/spot light emits uniformly (spot lights clipped to their
cone) from a single origin, an area light (the 3 barracks windows) emits
from random points across its surface, a directional light (moonlight)
emits a bundle of parallel photons from outside the scene's bounding
volume. Each photon carries a starting energy/colour derived from that
light's own intensity and colour, divided by however many photons that
light was given — the same "spread this light's total energy across N
samples" idea `area_light_contribution` already uses for its 4-8 direct
samples, just applied per-photon instead of per-pixel-sample.

**2. Photon tracing (bounces).** Each photon is traced through the scene
like a ray: intersect it against the scene geometry (the SAME analytic
proxy shapes `Source/Reflection.odin` already builds for ray-traced
reflection would be a natural reuse here — spheres/boxes/cylinders
standing in for the 9 real objects), and at each hit, probabilistically
decide whether it's absorbed, reflected (diffuse or specular, by the
surface's own material), or transmitted, using Russian roulette weighted
by the surface's reflectance — the same deterministic-hash-as-a-source-
of-pseudo-randomness idea `Shaders/Scene.glsl`'s `hash21`/`hash31`
already use for area-light jitter and the procedural starfield, just
driving a bounce/absorb DECISION per photon instead of a sample offset or
a star's existence. Photons that survive a bounce continue; the ones that
don't are done. A handful of bounces (2-4) is typical — diminishing
returns set in fast since each
bounce loses energy.

**3. Spatial storage.** Every point where a photon lands (not just where
it stops — every bounce point along its path) gets stored, with its
incoming direction and remaining energy, in a spatial data structure built
for fast "find the K nearest stored photons to this query point" lookups —
classically a **kd-tree** (Jensen's own choice; balanced, good for static
point clouds) or, for something simpler to implement and update, a
**uniform hash grid** keyed by a quantized world-space cell (conceptually
close to how this shader's own `sky_color`/`apply_ground_detail` already
bucket a continuous position into a discrete cell via `floor(position *
scale)`, just using that bucketing for spatial photon lookup instead of
procedural noise). Either way, this structure is built ONCE, after all
photons finish tracing — it is precisely the kind of precomputed,
cached-as-static-data structure `CLAUDE.md` §2 items 5/10 forbid
everywhere else in this project, which is the other half of why this stays
documentation-only rather than a "just cache it and call it done"
shortcut.

**4. The gather pass (density estimation).** At actual render time, for
each shading point (in SENTINEL's case, that would be every fragment,
same as `compute_lighting` runs today), query the spatial structure for
the K nearest stored photons within some search radius, and estimate the
incoming indirect light as a **density estimate**: sum those photons'
energy, weighted by how close each one actually is, and divide by the
search disc's area (`irradiance ≈ Σ photon_energy / (π * radius²)`,
Jensen's own formula, essentially "how much light energy landed per unit
area near here"). This estimate gets ADDED to the existing direct-light
result `compute_lighting` already computes — photon mapping is normally
used for indirect light only, with direct light still handled by ordinary
shading (exactly what SENTINEL's rasterization pipeline already does), so
integrating it here would extend `compute_lighting`'s `return ambient +
lit + emission_color` line to `ambient + lit + indirect_estimate +
emission_color`, not replace anything already working.

### 2.3 A concrete example in this scene

The watchtower's floodlights emit thousands of photons toward the ground.
Most travel a straight line and are absorbed on the first hit (the ground
plane, an object's flat side). Some, especially near-grazing ones, hit the
**sandbag bunker**'s own low, wide, diffuse (rough) surface and bounce off
in a scattered new direction rather than being absorbed outright — a
diffuse surface reflects a photon in a random direction weighted by its
own normal, not a mirror reflection. A photon that bounces this way and
happens to travel toward the nearby **cargo crate stack** lands on one of
the crates' faces and gets stored there. At the gather pass, any fragment
on that crate face near enough to several such stored bounce-photons picks
up a small amount of extra warm light — light that never traveled
directly from the floodlight to the crate (there's no direct line of
sight past the bunker at some angles) but arrived indirectly, via the
bunker's own surface acting as a secondary, dimmer light source. This is
the kind of soft, colour-bleeding indirect illumination (light picking up
a hint of the bunker's own sandbag colour on its way to the crate)
rasterization and the ray-traced reflection pass both fundamentally
cannot produce — ray tracing in this project only follows a SPECULAR
mirror bounce off glass, never a diffuse bounce off an ordinary matte
surface, and rasterization's `compute_lighting` only ever evaluates light
arriving directly from a light source, never light arriving secondhand
off another object.

### 2.4 What would actually need to change

- A new build-time-adjacent (not per-frame) pass, run once at program
  start or on demand, not from inside the main render loop.
- A photon data structure (kd-tree or hash grid) and its own memory
  budget, sized by target photon count.
- Reusing `Source/Reflection.odin`'s existing proxy shapes for photon/
  scene intersection tests, extended with per-material diffuse/specular/
  absorption probabilities (today's `Proxy` struct only carries a colour,
  not a full material split).
- A gather step added inside `compute_lighting`, reading the spatial
  structure built in the offline pass.
- Explicit acceptance that the photon map goes stale the instant a light
  or object moves (Patrol animation, an Inspection-Mode edit) — a real
  implementation would need either a "rebuild on demand" trigger tied to
  scene edits, or would only be valid for a genuinely static lighting
  setup, unlike literally everything else in this renderer.

---

## 3. Viva notes — plain-language explanations

### 3.1 Back-face culling

**The problem:** on a closed, solid object, roughly half of its triangles
always face away from the camera — you're looking at the object from
outside, so the far side's triangles point away from you no matter how
you turn. They can never be visible. Shading them (running the fragment
shader, testing the depth buffer) is pure wasted GPU work.

**The trick:** every triangle has a *winding order* — the order its 3
vertices are listed in, clockwise or counter-clockwise, AS SEEN FROM
WHICHEVER SIDE YOU'RE LOOKING AT IT. SENTINEL's convention (stated once,
`Library/Geometry/Geometry.odin`'s header) is CCW = front-facing. When a
mesh is built so every triangle winds CCW as seen from *outside* the
object, a triangle currently winding CW on screen must be a BACK face —
you're seeing its far side, which reversed its apparent winding. The GPU
can test this purely from 2D screen-space vertex order, no lighting or
depth needed.

**Two ways, both in SENTINEL, directly comparable (`C` key):**
- **Manual** (`Shaders/Scene.glsl`, `u_CullMode == CULL_MANUAL`): the
  fragment shader itself computes `dot(face normal, direction to the
  eye)` — negative means the surface faces away from the camera — and
  `discard`s that fragment. This produces the correct final image, but the
  GPU still had to rasterize the triangle and run the fragment shader
  before throwing the result away, so it costs almost nothing less than
  not culling at all.
- **Hardware / GL** (`gl.Enable(gl.CULL_FACE)`, `Source/Main.odin`'s
  `apply_render_state`): the GPU's rasterizer checks the SAME winding
  logic, but before the fragment shader ever runs — a back-facing triangle
  never reaches shading at all. This is where the real performance win is
  (SENTINEL measures roughly half the watchtower's own triangles as
  back-facing from a typical view — see `README.md`'s culling section).

Both methods produce the identical final image (verified pixel-for-pixel,
`README.md`'s culling section) because they're testing the same underlying
fact two different ways — one confirms the other is correct.

### 3.2 Hidden surface removal (the z-buffer / depth buffer)

**A different problem from culling:** even among triangles that DO face
the camera, several can overlap the same pixel at different depths (one
object standing in front of another). Which one should that pixel
actually show?

**The z-buffer's answer:** alongside the colour image, the GPU keeps a
second image, the same resolution, where every pixel stores the depth
(distance from the camera) of whatever's currently the nearest thing drawn
there. When a new fragment wants to write pixel (x, y), the GPU compares
its own depth to what's already stored: closer wins and overwrites both
colour and depth, farther is silently discarded. This works regardless of
DRAW ORDER — you don't have to sort objects back-to-front by hand, unlike
older painter's-algorithm approaches, which break on overlapping/
interpenetrating geometry that has no single valid sort order.

**In SENTINEL:** enabled by default, toggleable (`Z`,
`Source/Main.odin`'s `apply_render_state` -> `gl.Enable(gl.DEPTH_TEST)`).
Turning it off alongside culling produces a genuinely confusing image —
whichever triangle happens to be drawn LAST wins a pixel regardless of
which is actually nearer (`README.md`'s culling section has a captured
example). `X` replaces the normal shaded image with a grayscale picture of
the depth buffer's own values (near = dark, far = light) so the buffer's
actual contents are visible directly, not just their effect —
`Shaders/Scene.glsl`'s `u_DepthVisualization` branch hand-derives the
depth linearisation rather than sampling a second pass.

### 3.3 Blinn-Phong components: ambient, diffuse, specular, emission

Blinn-Phong is a *local* illumination model — it computes how much light
reaches a surface point directly from each light source, with no bounces
between objects (see §1's comparison against path/photon mapping, which
DO model bounces). `Shaders/Scene.glsl`'s `compute_lighting` sums four
independent terms:

- **Ambient** — a flat, tiny, everywhere-constant amount of light
  (`u_AmbientColor * u_AmbientStrength`), standing in for all the indirect
  bounced light this local model can't actually compute (that's what §2's
  photon mapping extension would replace this crude constant with). Keeps
  areas with no direct light from going pure black.
- **Diffuse** — light scattered EQUALLY in all directions off a rough
  (matte) surface, so its brightness only depends on the ANGLE between the
  surface normal and the direction to the light (`max(dot(normal,
  light_direction), 0)`, Lambert's cosine law) — NOT on where the camera
  is. A wall lit from the side is dimmer than one lit head-on, from any
  viewing angle.
- **Specular** — the bright highlight a shiny (glossy) surface shows, which
  DOES depend on where the camera is (a highlight moves as you move your
  head). Blinn-Phong's specific trick (vs. classic Phong) is comparing the
  light direction and view direction's HALF-VECTOR against the normal,
  rather than the true mirror-reflection direction against the view
  direction directly — cheaper to compute and a close visual match.
  Tinted by the LIGHT's colour, not the surface's own base colour (a
  glass highlight is white/light-coloured regardless of what's behind the
  glass — the real-world reason specular reflectance is usually
  colour-neutral for the dielectric materials used throughout this
  scene).
- **Emission** — light a surface appears to give off BY ITSELF, independent
  of any light source at all (a lit window, a lamp's own bulb housing,
  the tank's glowing instrument panel). Just added on top, unaffected by
  any light's position or the surface's own normal.

### 3.4 Light types

SENTINEL implements all four types the syllabus lists (`Library/Lights`),
each computed fresh every frame from its parent object's LIVE transform
(never a fixed world-space position — CLAUDE.md §2 item 10), so an
attached light correctly follows a moving/rotating parent:

- **Point** — an omnidirectional bulb (fence lamps, the radar beacon, the
  gun emplacement work light): equal brightness in every direction from
  one world position, falling off with distance (inverse-square-style
  attenuation).
- **Spot** — a point light additionally clipped to a cone (watchtower
  floodlights, jeep/tank headlights, the turret searchlight): brightness
  falls off both with distance AND with angle away from the cone's own
  aim direction, so it reads as an actual beam rather than a bare bulb.
- **Area** — a light with actual physical EXTENT rather than a single
  point (the 3 barracks windows) — see §1's path-tracing entry for how
  SENTINEL approximates this honestly (multi-point sampling across the
  window's real world-space quad every frame) rather than reaching for a
  precomputed LTC lookup texture, which CLAUDE.md's "no lookup textures"
  rule (§2 item 5) explicitly rules out.
- **Directional** — modelling a source infinitely far away (moonlight): no
  position at all, just a single constant direction every point in the
  scene receives light from equally, with no distance falloff (the sun/
  moon is effectively the same distance from every object in a scene this
  size).

### 3.5 Shading methods: Flat, Gouraud, Phong

All three compute the SAME underlying Blinn-Phong lighting equation (§3.3)
— they differ only in WHERE in the pipeline it's evaluated, and how many
times per triangle (toggle keys `1`/`2`/`3`, `Shaders/Scene.glsl`):

- **Flat** — lighting computed ONCE per triangle (using one face normal),
  and that single colour is used for the whole triangle, no interpolation
  at all (GLSL's `flat` qualifier on the colour varying). Produces
  visible, hard facets between triangles — an honest, deliberate look for
  this project's low-poly aesthetic, not a bug.
- **Gouraud** — lighting computed ONCE PER VERTEX (in the vertex shader,
  using each vertex's own normal), then the resulting COLOURS are smoothly
  interpolated across the triangle's interior. Cheaper than Phong (fewer
  lighting evaluations) but has a well-known failure mode: a small, bright
  light whose hot centre falls INSIDE a large triangle, nowhere near any
  of its 3 corners, can go almost entirely missed — none of the 3 corner
  colours being interpolated were ever near that bright spot. SENTINEL
  demonstrates this directly: the ground plane's resolution toggle (`G`,
  1 giant quad vs. a 24x24 subdivided grid) shows a spotlight's hot centre
  nearly vanishing under Gouraud on the coarse grid, and reappearing once
  the grid is fine enough to actually have a vertex near the light.
- **Phong** — lighting computed PER FRAGMENT (per PIXEL, in the fragment
  shader), using a smoothly-interpolated NORMAL (not a precomputed
  colour). The most expensive of the three (one full lighting evaluation
  per pixel rather than per vertex) but immune to Gouraud's "missed the
  hot spot" problem, since it never throws away spatial detail by
  interpolating colour instead of the underlying normal.

### 3.6 Projections: perspective vs. orthographic

Both convert 3D camera-space coordinates into the 2D image, but answer
"how does depth affect apparent size" completely differently (toggle `P`,
`Library/Camera/Camera.odin`'s `Projection_Matrix`):

- **Perspective** — mimics how human vision and real cameras work: objects
  farther away appear smaller (parallel lines, like the fence's two long
  sides, visually converge toward a vanishing point). Mathematically, this
  comes from dividing by depth (the projection matrix's bottom row
  produces a `w` component equal to `-view_z`, and the GPU automatically
  divides every other coordinate by `w` before rasterizing) — this is
  exactly why perspective's depth-buffer VALUES are a hyperbolic, not
  linear, function of true distance (`Shaders/Scene.glsl`'s depth-
  visualisation branch has to un-hyperbola them by hand to show a
  genuinely linear grayscale image).
- **Orthographic** — no perspective divide at all: object size on screen
  is completely independent of distance from the camera, so parallel
  lines stay visually parallel no matter how far they extend (useful for
  technical/inspection views where you want to judge true relative size
  and alignment without perspective distortion misleading you). This is
  also why orthographic's own depth values ARE already linear in distance
  — no divide happened, so no un-hyperbola-ing is needed, just an affine
  remap to `[0, 1]` — and why manual back-face culling needs a DIFFERENT
  "direction to the eye" formula under orthographic (`Shaders/Scene.glsl`'s
  `u_IsOrthographic` branch): every view ray is parallel under
  orthographic (one constant direction for the whole screen), whereas
  under perspective every ray fans out from one real eye point (a
  different direction per fragment).
