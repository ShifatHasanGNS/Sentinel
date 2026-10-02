package GPU

import gl "vendor:OpenGL"

Texture_Kind :: enum {
	Texture_2D,
	Texture_2D_Array,
	Texture_3D,
	Texture_Cube,
}

Texture_Format :: enum {
	None,
	R8,
	RG8,
	RGBA8,
	SRGB8_A8,
	R16F,
	RGBA16F,
	R11G11B10F,
	RGBA32F,
	Depth24,
	Depth32F,
}

// depth is the layer count for arrays and the third extent for 3D; unused for 2D and cube.
// mip_levels 0 requests the full chain.
Texture_Desc :: struct {
	kind:       Texture_Kind,
	format:     Texture_Format,
	width:      i32,
	height:     i32,
	depth:      i32,
	mip_levels: i32,
}

Texture :: struct {
	id:         u32,
	desc:       Texture_Desc,
	mip_levels: i32,
}

Texture_Create :: proc(desc: Texture_Desc) -> Texture {
	assert(desc.format != .None, "Texture_Create: format required")
	assert(desc.width > 0 && desc.height > 0, "Texture_Create: extent must be positive")
	assert(desc.kind != .Texture_Cube || desc.width == desc.height, "Texture_Create: cube faces must be square")
	texture := Texture{desc = desc, mip_levels = desc.mip_levels}
	if texture.mip_levels == 0 do texture.mip_levels = mip_chain_length(desc)
	gl.GenTextures(1, &texture.id)
	target := texture_target(desc.kind)
	gl.BindTexture(target, texture.id)
	for level in 0 ..< texture.mip_levels do allocate_level(desc, level)
	gl.TexParameteri(target, gl.TEXTURE_BASE_LEVEL, 0)
	gl.TexParameteri(target, gl.TEXTURE_MAX_LEVEL, texture.mip_levels - 1)
	GL_Check()
	return texture
}

// For 2D, array (layer = array index) and cube (layer = face 0..5) the data covers one image; for 3D, the whole volume.
Texture_Upload :: proc(texture: ^Texture, data: []$T, level: i32 = 0, layer: i32 = 0) {
	assert(level < texture.mip_levels, "Texture_Upload: level out of range")
	width, height, depth := level_extent(texture.desc, level)
	image_depth := depth if texture.desc.kind == .Texture_3D else 1
	expected_bytes := int(width) * int(height) * int(image_depth) * int(source_bytes_per_pixel(texture.desc.format))
	assert(len(data) * size_of(T) == expected_bytes, "Texture_Upload: data size does not match level size")
	info := format_info(texture.desc.format)
	target := texture_target(texture.desc.kind)
	gl.BindTexture(target, texture.id)
	gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
	switch texture.desc.kind {
	case .Texture_2D:
		gl.TexSubImage2D(target, level, 0, 0, width, height, info.pixel_format, info.pixel_type, raw_data(data))
	case .Texture_Cube:
		face_target := u32(gl.TEXTURE_CUBE_MAP_POSITIVE_X) + u32(layer)
		gl.TexSubImage2D(face_target, level, 0, 0, width, height, info.pixel_format, info.pixel_type, raw_data(data))
	case .Texture_2D_Array:
		gl.TexSubImage3D(target, level, 0, 0, layer, width, height, 1, info.pixel_format, info.pixel_type, raw_data(data))
	case .Texture_3D:
		gl.TexSubImage3D(target, level, 0, 0, 0, width, height, depth, info.pixel_format, info.pixel_type, raw_data(data))
	}
	GL_Check()
}

Texture_Generate_Mips :: proc(texture: ^Texture) {
	target := texture_target(texture.desc.kind)
	gl.BindTexture(target, texture.id)
	texture.mip_levels = mip_chain_length(texture.desc)
	gl.TexParameteri(target, gl.TEXTURE_MAX_LEVEL, texture.mip_levels - 1) // Generation stops at MAX_LEVEL, so raise it first.
	gl.GenerateMipmap(target)
	GL_Check()
}

Texture_Read_2D :: proc(texture: ^Texture, out: []$T, level: i32 = 0) {
	assert(texture.desc.kind == .Texture_2D, "Texture_Read_2D: not a 2D texture")
	width, height, _ := level_extent(texture.desc, level)
	expected_bytes := int(width) * int(height) * int(source_bytes_per_pixel(texture.desc.format))
	assert(len(out) * size_of(T) == expected_bytes, "Texture_Read_2D: output size does not match level size")
	info := format_info(texture.desc.format)
	gl.BindTexture(gl.TEXTURE_2D, texture.id)
	gl.PixelStorei(gl.PACK_ALIGNMENT, 1)
	gl.GetTexImage(gl.TEXTURE_2D, level, info.pixel_format, info.pixel_type, raw_data(out))
	GL_Check()
}

// Reads one layer of a 2D array texture through a temporary framebuffer; leaves the read framebuffer binding at the default.
Texture_Read_Layer :: proc(texture: ^Texture, layer: i32, out: []$T, level: i32 = 0) {
	assert(texture.desc.kind == .Texture_2D_Array, "Texture_Read_Layer: not an array texture")
	assert(layer >= 0 && layer < texture.desc.depth, "Texture_Read_Layer: layer out of range")
	width, height, _ := level_extent(texture.desc, level)
	assert(len(out) * size_of(T) == int(width) * int(height) * int(source_bytes_per_pixel(texture.desc.format)), "Texture_Read_Layer: output size does not match level size")
	info := format_info(texture.desc.format)
	reader: u32
	gl.GenFramebuffers(1, &reader)
	gl.BindFramebuffer(gl.READ_FRAMEBUFFER, reader)
	gl.FramebufferTextureLayer(gl.READ_FRAMEBUFFER, gl.COLOR_ATTACHMENT0, texture.id, level, layer)
	gl.ReadBuffer(gl.COLOR_ATTACHMENT0)
	gl.PixelStorei(gl.PACK_ALIGNMENT, 1)
	gl.ReadPixels(0, 0, width, height, info.pixel_format, info.pixel_type, raw_data(out))
	gl.BindFramebuffer(gl.READ_FRAMEBUFFER, 0)
	gl.DeleteFramebuffers(1, &reader)
	GL_Check()
}

Texture_Destroy :: proc(texture: ^Texture) {
	gl.DeleteTextures(1, &texture.id)
	texture^ = {}
}

// Texture units are handed out sequentially each frame so no caller tracks unit numbers by hand.
@(private = "file")
texture_unit_next: i32

Texture_Units_Reset :: proc() {
	texture_unit_next = 0
}

Texture_Bind_Next :: proc(texture: ^Texture, sampler_desc: Sampler_Desc) -> (unit: i32) {
	units_available: i32
	gl.GetIntegerv(gl.MAX_COMBINED_TEXTURE_IMAGE_UNITS, &units_available)
	assert(texture_unit_next < units_available, "Texture_Bind_Next: out of texture units")
	unit = texture_unit_next
	texture_unit_next += 1
	gl.ActiveTexture(gl.TEXTURE0 + u32(unit))
	gl.BindTexture(texture_target(texture.desc.kind), texture.id)
	gl.BindSampler(u32(unit), Sampler_Get(sampler_desc))
	GL_Check()
	return unit
}

@(private = "file")
Format_Info :: struct {
	internal_format: i32,
	pixel_format:    u32,
	pixel_type:      u32,
}

@(private = "file")
format_info :: proc(format: Texture_Format) -> Format_Info {
	switch format {
	case .None: unreachable()
	case .R8: return {gl.R8, gl.RED, gl.UNSIGNED_BYTE}
	case .RG8: return {gl.RG8, gl.RG, gl.UNSIGNED_BYTE}
	case .RGBA8: return {gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE}
	case .SRGB8_A8: return {gl.SRGB8_ALPHA8, gl.RGBA, gl.UNSIGNED_BYTE}
	case .R16F: return {gl.R16F, gl.RED, gl.FLOAT}
	case .RGBA16F: return {gl.RGBA16F, gl.RGBA, gl.FLOAT}
	case .R11G11B10F: return {gl.R11F_G11F_B10F, gl.RGB, gl.FLOAT}
	case .RGBA32F: return {gl.RGBA32F, gl.RGBA, gl.FLOAT}
	case .Depth24: return {gl.DEPTH_COMPONENT24, gl.DEPTH_COMPONENT, gl.FLOAT}
	case .Depth32F: return {gl.DEPTH_COMPONENT32F, gl.DEPTH_COMPONENT, gl.FLOAT}
	}
	unreachable()
}

// Float formats are uploaded and read as 32-bit floats; the driver converts to the stored precision.
Texture_Format_Is_Depth :: proc(format: Texture_Format) -> bool {
	return format == .Depth24 || format == .Depth32F
}

@(private = "file")
source_bytes_per_pixel :: proc(format: Texture_Format) -> i32 {
	switch format {
	case .None: unreachable()
	case .R8: return 1
	case .RG8: return 2
	case .RGBA8, .SRGB8_A8: return 4
	case .R16F, .Depth24, .Depth32F: return 4
	case .R11G11B10F: return 12
	case .RGBA16F, .RGBA32F: return 16
	}
	unreachable()
}

@(private = "file")
texture_target :: proc(kind: Texture_Kind) -> u32 {
	switch kind {
	case .Texture_2D: return gl.TEXTURE_2D
	case .Texture_2D_Array: return gl.TEXTURE_2D_ARRAY
	case .Texture_3D: return gl.TEXTURE_3D
	case .Texture_Cube: return gl.TEXTURE_CUBE_MAP
	}
	unreachable()
}

@(private = "file")
mip_chain_length :: proc(desc: Texture_Desc) -> i32 {
	largest := max(desc.width, desc.height)
	if desc.kind == .Texture_3D do largest = max(largest, desc.depth)
	levels: i32 = 1
	for largest > 1 {
		largest /= 2
		levels += 1
	}
	return levels
}

level_extent :: proc(desc: Texture_Desc, level: i32) -> (width, height, depth: i32) {
	width = max(1, desc.width >> u32(level))
	height = max(1, desc.height >> u32(level))
	depth = desc.depth
	if desc.kind == .Texture_3D do depth = max(1, desc.depth >> u32(level))
	return
}

@(private = "file")
allocate_level :: proc(desc: Texture_Desc, level: i32) {
	width, height, depth := level_extent(desc, level)
	info := format_info(desc.format)
	switch desc.kind {
	case .Texture_2D:
		gl.TexImage2D(gl.TEXTURE_2D, level, info.internal_format, width, height, 0, info.pixel_format, info.pixel_type, nil)
	case .Texture_Cube:
		for face in 0 ..< u32(6) {
			gl.TexImage2D(gl.TEXTURE_CUBE_MAP_POSITIVE_X + face, level, info.internal_format, width, height, 0, info.pixel_format, info.pixel_type, nil)
		}
	case .Texture_2D_Array:
		assert(depth > 0, "Texture_Create: array needs a layer count in desc.depth")
		gl.TexImage3D(gl.TEXTURE_2D_ARRAY, level, info.internal_format, width, height, depth, 0, info.pixel_format, info.pixel_type, nil)
	case .Texture_3D:
		assert(depth > 0, "Texture_Create: 3D texture needs desc.depth")
		gl.TexImage3D(gl.TEXTURE_3D, level, info.internal_format, width, height, depth, 0, info.pixel_format, info.pixel_type, nil)
	}
}
