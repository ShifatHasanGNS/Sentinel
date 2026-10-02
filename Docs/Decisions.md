# Decisions

- GL 4.1 core: the macOS maximum. Metal/Vulkan/wgpu rejected: backend rewrite, no needed feature.
- Deferred shading: many lights and many illumination models (model id in G-buffer). No MSAA, so FXAA.
- Fully procedural content: no model or texture files. Textures baked at startup into GPU memory by fragment passes; nothing stored on disk.
- Clean-slate rewrite of v1 (`legacy-v1`): v1 was a 2263-line Main.odin, duplicated VS/FS lighting code, no texture concept.
- Course syllabus no longer applies.
- No `glTexStorage*` (GL 4.2): each mip level is allocated with `glTexImage*`. `glGenerateMipmap` stops at `TEXTURE_MAX_LEVEL`, so `Texture_Generate_Mips` raises it first.
- GL checks run as `Tests/GpuCheck` (main thread), not `odin test`: macOS windowing traps off the main thread.
- CPU noise (`Engine/Procedural`) is continuous, not periodic: geometry and terrain need continuity only. Texture tileability is tested with the GLSL recipes in M3.
- Deformers are position maps; normals and tangents follow the numerical Jacobian (n' = J^-T n, t' = J t). One mechanism for every deformer, and hard edges are never smoothed across seams.
- Tangents are analytic per primitive (not computed from UV derivatives): poles make UV-derived tangents degenerate.
- Box, cylinder and capsule take segment counts so deformers have vertices to move.
- Texture bake renders every recipe into one layer of three array textures (albedo sRGB, normal+height, roughness/metal/AO) through `glFramebufferTextureLayer`; no copies. Albedo is written linear into an sRGB target (`GL_FRAMEBUFFER_SRGB` during the bake) so sampling decodes it.
- Tiling is tested exactly, not statistically: `BakeMain.glsl` has a `BAKE_PERIODICITY_PROBE` mode that outputs |recipe(uv) - recipe(uv + whole tiles)|. A seam-vs-neighbour statistic gave false failures for sharp patterns whose cell size divides the tile (canvas), because the seam is always a pattern boundary there.
- `cells_per_tile` must be a whole number (and thread counts even) so the periodic noise and weave tile.
- Lit.glsl applies gamma by hand as a placeholder; the HDR/tonemap post pass in M4 owns that.
