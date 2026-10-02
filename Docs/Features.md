# Features: where is it implemented?

| Feature | File : proc |
|---|---|
| Window + GL 4.1 context | `Engine/Platform/Window.odin` : `Window_Create` |
| Frame clock (capped delta) | `Engine/Platform/Clock.odin` : `Clock_Tick` |
| Keyboard / mouse polling | `Engine/Platform/Input.odin` : `Input_Update`, `Input_Key_Down` |
| GL error checking | `Engine/GPU/Debug.odin` : `GL_Check` |
| Shader source with `#include`, `#stage`, defines | `Engine/GPU/ShaderSource.odin` : `Shader_Source_Load` |
| Shader compile/link, uniforms | `Engine/GPU/Shader.odin` : `Shader_Create`, `Shader_Set` |
| Vertex/index/uniform buffers | `Engine/GPU/Buffer.odin` : `Buffer_Create` |
| Vertex arrays, instancing streams | `Engine/GPU/VertexArray.odin` : `Vertex_Array_Create` |
| Textures: 2D, array, 3D, cube, formats, mips | `Engine/GPU/Texture.odin` : `Texture_Create`, `Texture_Upload`, `Texture_Generate_Mips` |
| Texture unit allocation | `Engine/GPU/Texture.odin` : `Texture_Bind_Next` |
| Samplers, anisotropy, shadow compare (cached) | `Engine/GPU/Sampler.odin` : `Sampler_Get` |
| Extension / anisotropy capability query | `Engine/GPU/Capabilities.odin` |
| Framebuffers, MRT, resize | `Engine/GPU/Framebuffer.odin` : `Framebuffer_Create`, `Framebuffer_Resize` |
| Uniform blocks (std140) | `Engine/GPU/UniformBlock.odin` |
| Fullscreen triangle pass (bakes, post) | `Engine/GPU/FullscreenPass.odin` |
| Screenshot (BMP) | `Engine/GPU/Screenshot.odin` : `Screenshot_Save` |
| Integer hash (PCG) | `Engine/Procedural/Hash.odin` : `Hash_U32`, `Hash_Lattice_3` |
| Gradient noise, fbm | `Engine/Procedural/Noise.odin` : `Noise_Gradient_3`, `Noise_Fbm_3` |
| CPU mesh type, bounds | `Engine/Procedural/Mesh.odin` : `Mesh`, `Mesh_Bounds` |
| Primitives: box, sphere, cylinder, cone, capsule, torus, wedge (UV + tangents) | `Engine/Procedural/Primitives.odin` : `Box_Create`, `Sphere_Create`, ... |
| Merge parts under a transform (normal matrix, mirror-safe) | `Engine/Procedural/MeshBuilder.odin` : `Mesh_Append` |
| Deformers: noise displace, taper, twist, bend, bulge | `Engine/Procedural/Deform.odin` : `Mesh_Deform` |
| Upload a CPU mesh to the GPU | `Engine/Render/Mesh.odin` : `Mesh_Upload`, `Mesh_Draw` |
| Render into array-texture layers | `Engine/GPU/Framebuffer.odin` : `Framebuffer_Set_Layers` |
| Read an array layer back | `Engine/GPU/Texture.odin` : `Texture_Read_Layer` |
| Periodic gradient noise, fbm, Worley (GLSL) | `Shaders/Include/Noise.glsl` |
| Surface recipe contract + bake pass (albedo, normal+height, roughness/metal/AO) | `Shaders/Include/Surface.glsl`, `Shaders/Include/BakeMain.glsl` |
| Procedural texture bake into material arrays | `Engine/Procedural/TextureRecipe.odin` : `Texture_Set_Bake` |
| Bind a baked set to a shader | `Engine/Render/Material.odin` : `Texture_Set_Bind` |
| Triplanar sampling + normal blend (GLSL) | `Shaders/Include/Triplanar.glsl` |
| Material list + recipe table (concrete, camo, rust, sand, canvas, grass, dirt, rock) | `Game/Materials/Materials.odin` : `Materials_Bake` |
| One recipe per material | `Shaders/Recipes/*.glsl` |
| Octahedral normal encoding (G-buffer) | `Shaders/Include/Gbuffer.glsl` : `oct_encode`, `oct_decode` |
| Read the G-buffer, rebuild position from depth | `Shaders/Include/GbufferRead.glsl` : `gbuffer_read` |
| Illumination models: Lambert, Phong, Blinn-Phong, Oren-Nayar, Cook-Torrance GGX, subsurface | `Shaders/Include/Brdf.glsl` : `brdf_evaluate`, `light_cosine`; `Engine/Render/Illumination.odin` |
| Light sources: directional, point, spot, area (sampled rectangle) | `Shaders/Include/Lighting.glsl` : `shade_light`; `Engine/Render/Light.odin` |
| Sky gradient + sun disc, sky ambient | `Shaders/Include/Sky.glsl` |
| Image-based ambient (split-sum environment BRDF) | `Shaders/Include/Ambient.glsl` : `ambient_light` |
| ACES tonemap, vignette, sRGB | `Shaders/Include/Tonemap.glsl`, `Shaders/PostTonemap.glsl` |
| FXAA | `Shaders/PostFxaa.glsl` |
| Camera, frustum slices | `Engine/Render/Camera.odin`, `Engine/Render/Shadows.odin` : `Frustum_Slice_Corners` |
| Cascade splits + fit (sphere bound, texel snapping) | `Engine/Render/Shadows.odin` : `Cascade_Splits`, `Shadow_Cascades_Fit` |
| Shadow map pass + uniforms | `Engine/Render/ShadowMap.odin` : `Shadow_Map_Render`, `Shadow_Map_Bind` |
| Shadow lookup (cascade pick, normal offset, PCF) | `Shaders/Include/Shadow.glsl` : `shadow_factor` |
| Deferred frame: shadow, geometry, lighting, post | `Engine/Render/Renderer.odin` : `Renderer_Render` |
| Geometry pass (writes the G-buffer) | `Shaders/Geometry.glsl` |
| Sun + ambient + sky fullscreen pass | `Shaders/DeferredBase.glsl` |
| Local lights as additive proxy volumes | `Shaders/DeferredLight.glsl` |
| Depth-only render into an array layer | `Engine/GPU/Framebuffer.odin` : `Framebuffer_Set_Depth_Layer` |
| Showroom (materials on primitives, deformed shapes, material spheres) | `Game/Showroom/Showroom.odin`, `Game/Showroom/Gallery.odin` |
| Gallery of primitives, plain and deformed | `Game/Showroom/Gallery.odin` : `Gallery_Create` |
