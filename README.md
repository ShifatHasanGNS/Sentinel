# SENTINEL

A real-time 3D renderer of a night-time military base, built from
scratch in **Odin** on top of **OpenGL** and **GLFW** — no game engine,
no imported models or textures. Every object in the scene is generated
procedurally at runtime from three base shapes (cube, tetrahedron,
plane), and every object is placed in a hand-built parent/child
transform hierarchy.

This build is a **progress milestone**: it demonstrates procedural
geometry, the transform hierarchy, the camera system, and both
operating modes. Lighting, shading, and the remaining syllabus topics
are a later milestone — see `Docs/report/report.pdf` for the full
progress report.

## Build & run

```sh
odin build Source -out:Sentinel
./Sentinel
```

## Modes

- **Patrol Mode** (default) — fully automatic camera tour of the base,
  no input needed.
- **Inspection Mode** (`Tab` to switch) — free-fly camera with object
  selection and editing.

## Controls (Inspection Mode)

| Key | Action |
| --- | --- |
| `W`/`A`/`S`/`D`, mouse | Move / look |
| `Q` / `E` | Move down / up |
| `Shift` | Sprint |
| `P` | Toggle perspective / orthographic |
| `[` / `]` | Select previous / next object |
| Left click | Pick the object at the screen centre |
| `I`/`K`, `J`/`L`, `U`/`O` | Translate selected object (local Z, X, Y) |
| `4`–`9` | Rotate selected object (yaw, pitch, roll) |
| `0` / `Shift`+`0` | Reset selected / reset all objects |
| `H` | Print the full control list |
| `Esc` | Quit |

## Notes

- All 9 scene objects and every shape beyond them are generated at
  runtime — nothing is a stored/imported model.
- `Space` pauses the shared animation clock; `,`/`.` slow down / speed
  it up.
