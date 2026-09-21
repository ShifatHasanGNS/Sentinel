// Package Lights — light structs, runtime placement, and animation. Split
// out from `Library/Scene` into its own package per the user's Session 0
// decision on CLAUDE.md §11 item 7 (was previously tentative — see
// PROGRESS.md). Depends on `Library/Scene`'s transform/node hierarchy to
// derive world-space position/direction from a parent node each frame.
//
// Roadmap steps 4–6 (CLAUDE.md §9; Prompts.md Sessions 7–9). Must satisfy
// "active light count > object count" (Requirements.md §3, CLAUDE.md §3) —
// this plan targets 18–21 lights against 9 objects (CLAUDE.md §5.2).
//
// Planned Light struct (mirrored by a matching GLSL uniform-array layout in
// Shaders/Scene.glsl's fragment stage): type (directional | point | spot | area), a
// local-space offset + local direction (core:math/linalg Vector3f32 —
// allowed, CLAUDE.md §2 item 3), a parent node id (or none, for world-fixed
// lights like moonlight), colour, intensity, attenuation
// (constant/linear/quadratic), spot inner/outer cone angles with smooth
// falloff, and an enabled flag. Every frame, world position/direction is
// DERIVED from the parent's current world matrix via `Library/Scene`'s
// transform helpers — never stored as a world-space constant and never computed once
// then cached (CLAUDE.md §5.3, §9 roadmap step 5, §2 item 10 — instructor
// hard constraint: illumination is real-time, same as geometry) — this is
// what makes attached lights follow a moved or rotated parent (e.g. jeep
// headlights, tank turret searchlight).
//
// Planned light rig (Requirements.md §3, CLAUDE.md §5.2, Plan.md §3), all
// placed by runtime formula, never a literal position table:
//   Watchtower floodlights      — 2 spot,  child of the rotating tower head.
//   Perimeter fence lamps       — 6-8 point, evenly spaced along the fence
//                                  loop by formula.
//   Jeep headlights             — 2 spot,  child of the jeep.
//   Tank headlights             — 2 spot,  child of the HULL only.
//   Tank turret searchlight     — 1 spot,  child of the TURRET (not hull) —
//                                  the key nested-transform test.
//   Radar beacon                — 1 point, intensity driven by a runtime
//                                  sine function (no blink lookup table).
//   Barracks windows            — 2-3 area (sampled, CLAUDE.md §6.3): each
//                                  frame, sample 4-8 points across the
//                                  window's current world-space quad and
//                                  average their contribution — a simplified
//                                  single-bounce Monte Carlo sampler, the
//                                  core idea behind path tracing's direct-
//                                  light step.
//   Gun emplacement work light  — 1 point, local contrast near the bunker.
//   Moonlight                   — 1 directional, cool/dim fill and baseline.
//
// Fragment-side lighting itself (ambient + diffuse + specular + emission,
// Blinn-Phong) lives in Shaders/Scene.glsl's fragment stage, uploaded here as a fixed-max
// uniform array (e.g. 32) plus an active count. Keep both the object count
// and the active light count printed at startup/each frame so the
// "lights > objects" requirement is always visibly checkable.
package Lights
