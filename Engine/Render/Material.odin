package Render

import "../GPU"
import "../Procedural"

// Binds a baked texture set to three consecutive units and points the shader's array samplers at them.
Texture_Set_Bind :: proc(shader: ^GPU.Shader, set: ^Procedural.Texture_Set) {
	GPU.Texture_Units_Reset()
	GPU.Shader_Set(shader, "u_AlbedoArray", GPU.Texture_Bind_Next(&set.albedo, GPU.Sampler_Trilinear_Repeat))
	GPU.Shader_Set(shader, "u_NormalArray", GPU.Texture_Bind_Next(&set.normal, GPU.Sampler_Trilinear_Repeat))
	GPU.Shader_Set(shader, "u_OrmArray", GPU.Texture_Bind_Next(&set.orm, GPU.Sampler_Trilinear_Repeat))
}
