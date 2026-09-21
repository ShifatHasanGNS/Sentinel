// Package Scene — SENTINEL-specific: hierarchy, objects, lights, camera.
//
// PACKAGE SPLIT IS TENTATIVE (open item, CLAUDE.md §11 item 7 / Plan.md
// §11.3): whether Scene/hierarchy, Lights, and Camera should each be their
// own package, or grouped as they are here, is not yet decided with the
// user. This `Scene` package + these four files are a reasonable starting
// grouping following Prompts.md's per-file breakdown (Transform.odin,
// Objects.odin, Lights.odin, Camera.odin) — reorganize only once the user
// has actually answered, don't do it silently.
//
// Transform.odin — the hand-rolled hierarchy system (CLAUDE.md §5.3, §9
// roadmap step 3 part 2 / step 4 groundwork; Prompts.md Session 4). No
// scene-graph library (CLAUDE.md §2.4) — but note core:math/linalg IS
// allowed for the matrix/vector math underneath the hierarchy (CLAUDE.md §2
// item 3, updated).
//
// Planned contents:
//   Transform — local translation, rotation, scale, using
//     core:math/linalg's Vector3f32 and rotation helpers directly (no
//     hand-written math package). Rotation representation (yaw/pitch/roll
//     vs. axis-angle via linalg.matrix4_rotate) is a decision to make and
//     document here when implemented.
//   Node — name/id, optional parent index/pointer, local Transform, optional
//     mesh + material (from `Library/Geometry`), list of children.
//   world_matrix(node) — parent world matrix * local matrix (linalg matrix
//     multiplication), computed top-down once per frame in a single pass
//     (cache per frame, don't recompute per light/draw call).
//   Helpers to get a node's world position, and to transform a local
//     direction vector by a node's world matrix ignoring translation
//     (w = 0) — lights (Lights.odin) depend on this to derive world-space
//     position/direction from their parent's current transform.
//   Normal-matrix helper (inverse-transpose of the upper-left 3x3, via
//     linalg.inverse_transpose or equivalent), used when drawing so
//     lighting stays correct under non-uniform scale.
//   Node-selection API (get/set by id, list all) — needed later by
//     Inspection Mode (CLAUDE.md §7, roadmap step 10).
//
// Required hierarchy chains to get right (CLAUDE.md §5.3, §9 roadmap step 5):
//   tower base -> floodlight head -> 2 spot lights
//   jeep -> 2 headlights
//   tank hull -> (headlights) ; hull -> turret -> (searchlight, barrel)
//
// Tests: a 3-level chain (base -> arm -> tip), rotate the arm 90 degrees,
// assert the tip's world position matches a hand-computed value; also that
// rotating the base moves everything downstream.
package Scene
