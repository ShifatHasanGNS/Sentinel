package GPU

import gl "vendor:OpenGL"

Min_Filter :: enum i32 {
	Nearest            = gl.NEAREST,
	Linear             = gl.LINEAR,
	Nearest_Mip_Linear = gl.NEAREST_MIPMAP_LINEAR,
	Linear_Mip_Nearest = gl.LINEAR_MIPMAP_NEAREST,
	Trilinear          = gl.LINEAR_MIPMAP_LINEAR,
}

Mag_Filter :: enum i32 {
	Nearest = gl.NEAREST,
	Linear  = gl.LINEAR,
}

Wrap_Mode :: enum i32 {
	Repeat          = gl.REPEAT,
	Mirrored_Repeat = gl.MIRRORED_REPEAT,
	Clamp_To_Edge   = gl.CLAMP_TO_EDGE,
}

Sampler_Desc :: struct {
	min_filter:    Min_Filter,
	mag_filter:    Mag_Filter,
	wrap:          Wrap_Mode,
	anisotropy:    f32,
	compare_depth: bool,
}

Sampler_Trilinear_Repeat :: Sampler_Desc{.Trilinear, .Linear, .Repeat, 16, false}
Sampler_Linear_Clamp :: Sampler_Desc{.Linear, .Linear, .Clamp_To_Edge, 1, false}
Sampler_Linear_Repeat :: Sampler_Desc{.Linear, .Linear, .Repeat, 1, false}
Sampler_Nearest_Clamp :: Sampler_Desc{.Nearest, .Nearest, .Clamp_To_Edge, 1, false}
Sampler_Shadow :: Sampler_Desc{.Linear, .Linear, .Clamp_To_Edge, 1, true}

@(private = "file")
sampler_cache: map[Sampler_Desc]u32

Sampler_Get :: proc(desc: Sampler_Desc) -> u32 {
	assert(desc.anisotropy >= 1, "Sampler_Get: anisotropy must be >= 1")
	if cached, found := sampler_cache[desc]; found do return cached
	sampler: u32
	gl.GenSamplers(1, &sampler)
	apply_sampler_state(sampler, desc)
	GL_Check()
	sampler_cache[desc] = sampler
	return sampler
}

Sampler_Cache_Destroy :: proc() {
	for _, sampler in sampler_cache {
		handle := sampler
		gl.DeleteSamplers(1, &handle)
	}
	delete(sampler_cache)
	sampler_cache = nil
}

@(private = "file")
apply_sampler_state :: proc(sampler: u32, desc: Sampler_Desc) {
	gl.SamplerParameteri(sampler, gl.TEXTURE_MIN_FILTER, i32(desc.min_filter))
	gl.SamplerParameteri(sampler, gl.TEXTURE_MAG_FILTER, i32(desc.mag_filter))
	gl.SamplerParameteri(sampler, gl.TEXTURE_WRAP_S, i32(desc.wrap))
	gl.SamplerParameteri(sampler, gl.TEXTURE_WRAP_T, i32(desc.wrap))
	gl.SamplerParameteri(sampler, gl.TEXTURE_WRAP_R, i32(desc.wrap))
	if anisotropy_max() >= 1 {
		gl.SamplerParameterf(sampler, gl.TEXTURE_MAX_ANISOTROPY, min(desc.anisotropy, anisotropy_max()))
	}
	if desc.compare_depth {
		gl.SamplerParameteri(sampler, gl.TEXTURE_COMPARE_MODE, gl.COMPARE_REF_TO_TEXTURE)
		gl.SamplerParameteri(sampler, gl.TEXTURE_COMPARE_FUNC, gl.LEQUAL)
	}
}
