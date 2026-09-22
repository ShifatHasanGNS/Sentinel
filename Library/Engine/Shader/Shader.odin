package Shader

import dbg "../Debugger"
import "core:fmt"
import "core:log"
import la "core:math/linalg"
import "core:os"
import "core:path/filepath"
import "core:strings"
import gl "vendor:OpenGL"

Shader :: struct {
	FilePath:             string,
	RendererID:           u32,
	UniformLocationCache: map[string]i32,
}

New :: proc(shader_source_file_path: string) -> Shader {
	abs_path, error := filepath.abs(shader_source_file_path)
	if error != nil {log.warn("Invalid Shader File Path"); return {}}

	vert_src, frag_src := load_shaders_from(abs_path)

	vert_shader_id := compile_shader(.VERTEX_SHADER, vert_src)
	defer gl.DeleteShader(vert_shader_id); dbg.GL_Check()
	frag_shader_id := compile_shader(.FRAGMENT_SHADER, frag_src)
	defer gl.DeleteShader(frag_shader_id); dbg.GL_Check()

	shader_program_id := gl.CreateProgram()

	gl.AttachShader(shader_program_id, vert_shader_id); dbg.GL_Check()
	gl.AttachShader(shader_program_id, frag_shader_id); dbg.GL_Check()

	gl.LinkProgram(shader_program_id); dbg.GL_Check()
	gl.ValidateProgram(shader_program_id); dbg.GL_Check()

	return Shader{abs_path, shader_program_id, {}}
}

Delete :: proc(shader: ^Shader) {
	delete(shader.FilePath)
	gl.DeleteProgram(shader.RendererID); dbg.GL_Check()
}

Bind :: proc(shader: ^Shader) {
	gl.UseProgram(shader.RendererID); dbg.GL_Check()
}

Unbind :: proc() {
	gl.UseProgram(0); dbg.GL_Check()
}

GetUniformLocation :: proc(
	shader: ^Shader,
	uniform_name: string,
	location := #caller_location,
) -> (
	uniform_location: i32,
) {
	if loc, ok := shader.UniformLocationCache[uniform_name]; ok {
		return loc
	}

	uniform_location = gl.GetUniformLocation(
		shader.RendererID,
		strings.clone_to_cstring(uniform_name),
	); dbg.GL_Check()

	if uniform_location == -1 do log.warnf("\nUniform '%s' not Found or Used in Shader File '%s'", uniform_name, shader.FilePath, location = location)

	shader.UniformLocationCache[uniform_name] = uniform_location
	return uniform_location
}

SetUniform :: proc {
	SetUniform1i32,
	SetUniform2i32,
	SetUniform3i32,
	SetUniform4i32,
	SetUniform1f32,
	SetUniform2f32,
	SetUniform3f32,
	SetUniform4f32,
	SetUniformMatrix2f32,
	SetUniformMatrix3f32,
	SetUniformMatrix4f32,
}

SetUniform1i32 :: proc(
	shader: ^Shader,
	uniform_name: string,
	v0: i32,
	location := #caller_location,
) {
	Bind(shader)
	gl.Uniform1i(GetUniformLocation(shader, uniform_name, location), v0); dbg.GL_Check()
}

SetUniform2i32 :: proc(
	shader: ^Shader,
	uniform_name: string,
	v0, v1: i32,
	location := #caller_location,
) {
	Bind(shader)
	gl.Uniform2i(GetUniformLocation(shader, uniform_name, location), v0, v1); dbg.GL_Check()
}

SetUniform3i32 :: proc(
	shader: ^Shader,
	uniform_name: string,
	v0, v1, v2: i32,
	location := #caller_location,
) {
	Bind(shader)
	gl.Uniform3i(GetUniformLocation(shader, uniform_name, location), v0, v1, v2); dbg.GL_Check()
}

SetUniform4i32 :: proc(
	shader: ^Shader,
	uniform_name: string,
	v0, v1, v2, v3: i32,
	location := #caller_location,
) {
	Bind(shader)
	gl.Uniform4i(
		GetUniformLocation(shader, uniform_name, location),
		v0,
		v1,
		v2,
		v3,
	); dbg.GL_Check()
}

SetUniform1f32 :: proc(
	shader: ^Shader,
	uniform_name: string,
	v0: f32,
	location := #caller_location,
) {
	Bind(shader)
	gl.Uniform1f(GetUniformLocation(shader, uniform_name, location), v0); dbg.GL_Check()
}

SetUniform2f32 :: proc(
	shader: ^Shader,
	uniform_name: string,
	v0, v1: f32,
	location := #caller_location,
) {
	Bind(shader)
	gl.Uniform2f(GetUniformLocation(shader, uniform_name, location), v0, v1); dbg.GL_Check()
}


SetUniform3f32 :: proc(
	shader: ^Shader,
	uniform_name: string,
	v0, v1, v2: f32,
	location := #caller_location,
) {
	Bind(shader)
	gl.Uniform3f(GetUniformLocation(shader, uniform_name, location), v0, v1, v2); dbg.GL_Check()
}

SetUniform4f32 :: proc(
	shader: ^Shader,
	uniform_name: string,
	v0, v1, v2, v3: f32,
	location := #caller_location,
) {
	Bind(shader)
	gl.Uniform4f(
		GetUniformLocation(shader, uniform_name, location),
		v0,
		v1,
		v2,
		v3,
	); dbg.GL_Check()
}

SetUniformMatrix2f32 :: proc(
	shader: ^Shader,
	uniform_name: string,
	mat: ^la.Matrix2f32,
	location := #caller_location,
) {
	Bind(shader)
	gl.UniformMatrix2fv(
		GetUniformLocation(shader, uniform_name, location),
		1,
		false,
		la.to_ptr(mat),
	); dbg.GL_Check()
}

SetUniformMatrix3f32 :: proc(
	shader: ^Shader,
	uniform_name: string,
	mat: ^la.Matrix3f32,
	location := #caller_location,
) {
	Bind(shader)
	gl.UniformMatrix3fv(
		GetUniformLocation(shader, uniform_name, location),
		1,
		false,
		la.to_ptr(mat),
	); dbg.GL_Check()
}

SetUniformMatrix4f32 :: proc(
	shader: ^Shader,
	uniform_name: string,
	mat: ^la.Matrix4f32,
	location := #caller_location,
) {
	Bind(shader)
	gl.UniformMatrix4fv(
		GetUniformLocation(shader, uniform_name, location),
		1,
		false,
		la.to_ptr(mat),
	); dbg.GL_Check()
}

@(private = "file")
load_shaders_from :: proc(shader_file_src: string) -> (vert_src: string, frag_src: string) {
	ShaderType :: enum {
		NONE,
		VERTEX,
		FRAGMENT,
	}

	data, error := os.read_entire_file(shader_file_src, context.allocator)
	defer delete(data)
	if error != nil {log.warnf("Failed to read file: %s", shader_file_src); return "", ""}

	content := string(data)
	lines := strings.split(content, "\n")
	defer delete(lines)

	vert_builder: strings.Builder
	frag_builder: strings.Builder
	defer strings.builder_destroy(&vert_builder)
	defer strings.builder_destroy(&frag_builder)

	current_shader := ShaderType.NONE
	version_line := ""
	version_added := false

	for line in lines {
		trimmed := strings.trim_space(line)

		if len(trimmed) == 0 || strings.has_prefix(trimmed, "//") {
			continue
		}

		if strings.has_prefix(trimmed, "#version") && !version_added {
			version_line = strings.concatenate({trimmed, "\n"})
			version_added = true
			continue
		}

		if strings.has_prefix(trimmed, "#shader vertex") {
			current_shader = ShaderType.VERTEX
			continue
		} else if strings.has_prefix(trimmed, "#shader fragment") {
			current_shader = ShaderType.FRAGMENT
			continue
		}

		switch current_shader {
		case .VERTEX:
			strings.write_string(&vert_builder, trimmed)
			strings.write_string(&vert_builder, "\n")
		case .FRAGMENT:
			strings.write_string(&frag_builder, trimmed)
			strings.write_string(&frag_builder, "\n")
		case .NONE:
		}
	}

	vert_content := strings.to_string(vert_builder)
	frag_content := strings.to_string(frag_builder)

	if len(vert_content) > 0 {
		vert_src = strings.concatenate({version_line, vert_content})
	}
	if len(frag_content) > 0 {
		frag_src = strings.concatenate({version_line, frag_content})
	}

	if version_added do delete(version_line)

	return vert_src, frag_src
}

@(private = "file")
compile_shader :: proc(shader_type: gl.Shader_Type, shader_src: string) -> (shader_id: u32) {
	shader_id = 0

	if shader_type != .VERTEX_SHADER && shader_type != .FRAGMENT_SHADER do log.panic("Invalid Shader Type")

	shader_id = gl.CreateShader(u32(shader_type)); dbg.GL_Check()
	shader_data := strings.clone_to_cstring(shader_src)

	gl.ShaderSource(shader_id, 1, &shader_data, nil); dbg.GL_Check()
	gl.CompileShader(shader_id); dbg.GL_Check()

	result: i32
	gl.GetShaderiv(shader_id, gl.COMPILE_STATUS, &result); dbg.GL_Check()

	if result == 0 {
		length: i32
		gl.GetShaderiv(shader_id, gl.INFO_LOG_LENGTH, &length); dbg.GL_Check()
		message := make([]u8, length)
		gl.GetShaderInfoLog(shader_id, length, &length, raw_data(message)); dbg.GL_Check()
		shader_name: string = "Vertex" if shader_type == .VERTEX_SHADER else "Fragment"
		log.panicf("Failed to Compile '%s Shader'\n%s", shader_name, message)
	}

	return shader_id
}
