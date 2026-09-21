// Objects.odin — builds the 9 SENTINEL scene objects (see package doc in
// Transform.odin for the tentative-package-split note).
//
// Roadmap step 3 parts 3–4 / Prompts.md Sessions 5–6. All positions,
// dimensions, and counts come from parameters/formulas fed into
// `Library/Geometry`'s cube/tetrahedron/plane generators via `Scene.Node`
// hierarchies — never literal position or vertex tables (CLAUDE.md §2.5),
// and nothing assembled at compile time. Every "cylinder," "wedge," or
// "cone" named below is a runtime composition of those three primitives via
// matrix transforms (CLAUDE.md §2 item 6), not a distinct generator.
//
// The 9 required objects (Requirements.md §3 "minimum 6"; this project
// targets 9 — CLAUDE.md §5.1, §12, §14; Plan.md §2):
//   1. Watchtower            — legs, platform, railing, roof; separate
//                               rotating "floodlight head" child node
//                               carrying 2 spot lights.
//   2. Perimeter fence + gate — runtime loop of posts + panels around the
//                               base perimeter, with a gate gap; exposes
//                               post positions for fence-lamp placement.
//   3. Armored jeep          — body, cabin, wheels, hood, 2 headlight child
//                               nodes, distinct windshield quad node
//                               (candidate ray-traced surface, CLAUDE.md §6.2).
//   4. Sandbag bunker        — stacked short low-segment cylinders in a
//                               wall arc.
//   5. Radar dish / antenna  — mast + rotating dish child node + beacon.
//   6. Barracks hut          — box body, pitched roof, 2–3 window child
//                               nodes exposing quad geometry for area lights
//                               (CLAUDE.md §6.3).
//   7. Cargo crate stack     — several crates, formula-varied sizes/rotation.
//   8. Battle tank           — hull (box + wedge front) -> turret (child) ->
//                               barrel (child of turret); hull headlights,
//                               turret searchlight, turret periscope/gun-
//                               sight quad (other ray-tracing candidate).
//   9. Static gun emplacement — sandbag ring, tripod, gun; deliberately
//                               static (no animation), contrasts with the tank.
//
// Every root/child node that will later carry a light or be independently
// animated/selected must have a clear, stable name — Inspection Mode's
// object-cycling (roadmap step 10) and Lights.odin's parent attachment both
// depend on it.
//
// Verification: print the total object count at startup (must be >= 6,
// this plan targets 9) and confirm via capture that the base reads well
// with no intersecting/floating geometry from at least two camera angles.
package Scene
