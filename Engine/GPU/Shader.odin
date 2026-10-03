package GPU

import "core:fmt"
import "core:mem"
import "core:strings"
import gl "vendor:OpenGL"

Shader :: struct {
	program:                  u32,
	uniform_locations:        map[string]i32,
	last_values:              map[i32]Uniform_Value, // What each uniform was last set to; an identical set is skipped (program state persists).
	tolerate_missing_uniforms: bool, // For generic setters where a given shader may legitimately not use every uniform.
}

Shader_Create :: proc(path: string, defines: []string = nil, tolerate_missing_uniforms := false) -> (shader: Shader, ok: bool) {
	stages, loaded := Shader_Source_Load(path, defines)
	if !loaded do return {}, false
	defer Shader_Stages_Destroy(&stages)
	return Shader_Create_From_Source(stages.vertex, stages.fragment, path, tolerate_missing_uniforms)
}

Shader_Create_From_Source :: proc(vertex_source, fragment_source: string, label: string, tolerate_missing_uniforms := false) -> (shader: Shader, ok: bool) {
	vertex_id, vertex_ok := compile_stage(gl.VERTEX_SHADER, vertex_source, label)
	if !vertex_ok do return {}, false
	defer gl.DeleteShader(vertex_id)
	fragment_id, fragment_ok := compile_stage(gl.FRAGMENT_SHADER, fragment_source, label)
	if !fragment_ok do return {}, false
	defer gl.DeleteShader(fragment_id)

	shader.program = gl.CreateProgram()
	shader.tolerate_missing_uniforms = tolerate_missing_uniforms
	gl.AttachShader(shader.program, vertex_id)
	gl.AttachShader(shader.program, fragment_id)
	gl.LinkProgram(shader.program)
	if !program_linked(shader.program, label) {
		gl.DeleteProgram(shader.program)
		return {}, false
	}
	GL_Check()
	return shader, true
}

Uniform_Value :: struct {
	bytes: [64]u8, // Up to a mat4.
	size:  int,
}

Shader_Destroy :: proc(shader: ^Shader) {
	for name in shader.uniform_locations do delete(name)
	delete(shader.uniform_locations)
	delete(shader.last_values)
	gl.DeleteProgram(shader.program)
	shader^ = {}
}

Shader_Use :: proc(shader: ^Shader) {
	gl.UseProgram(shader.program)
}

// Overloads are resolved by exact type: write i32(1) and f32(1), not bare literals.
Shader_Set :: proc {
	Shader_Set_i32,
	Shader_Set_f32,
	Shader_Set_vec2,
	Shader_Set_vec3,
	Shader_Set_vec4,
	Shader_Set_mat3,
	Shader_Set_mat4,
}

// Skips a set when the uniform already holds exactly these bytes. A draw call per scene item sets about nine uniforms, most of them
// the same as the previous item's, and each skipped call is a driver round trip saved.
@(private = "file")
unchanged :: proc(shader: ^Shader, location: i32, value: ^$T) -> bool {
	size := size_of(T)
	cached, present := shader.last_values[location]
	if present && cached.size == size && mem.compare(cached.bytes[:size], mem.byte_slice(value, size)) == 0 do return true
	entry: Uniform_Value
	entry.size = size
	copy(entry.bytes[:size], mem.byte_slice(value, size))
	shader.last_values[location] = entry
	return false
}

Shader_Set_i32 :: proc(shader: ^Shader, name: string, value: i32) {
	value := value
	location := uniform_location(shader, name)
	if unchanged(shader, location, &value) do return
	gl.ProgramUniform1i(shader.program, location, value)
}

Shader_Set_f32 :: proc(shader: ^Shader, name: string, value: f32) {
	value := value
	location := uniform_location(shader, name)
	if unchanged(shader, location, &value) do return
	gl.ProgramUniform1f(shader.program, location, value)
}

Shader_Set_vec2 :: proc(shader: ^Shader, name: string, value: [2]f32) {
	value := value
	location := uniform_location(shader, name)
	if unchanged(shader, location, &value) do return
	gl.ProgramUniform2fv(shader.program, location, 1, &value[0])
}

Shader_Set_vec3 :: proc(shader: ^Shader, name: string, value: [3]f32) {
	value := value
	location := uniform_location(shader, name)
	if unchanged(shader, location, &value) do return
	gl.ProgramUniform3fv(shader.program, location, 1, &value[0])
}

Shader_Set_vec4 :: proc(shader: ^Shader, name: string, value: [4]f32) {
	value := value
	location := uniform_location(shader, name)
	if unchanged(shader, location, &value) do return
	gl.ProgramUniform4fv(shader.program, location, 1, &value[0])
}

Shader_Set_mat3 :: proc(shader: ^Shader, name: string, value: matrix[3, 3]f32) {
	value := value
	location := uniform_location(shader, name)
	if unchanged(shader, location, &value) do return
	gl.ProgramUniformMatrix3fv(shader.program, location, 1, false, &value[0, 0])
}

Shader_Set_mat4 :: proc(shader: ^Shader, name: string, value: matrix[4, 4]f32) {
	value := value
	location := uniform_location(shader, name)
	if unchanged(shader, location, &value) do return
	gl.ProgramUniformMatrix4fv(shader.program, location, 1, false, &value[0, 0])
}

Shader_Bind_Uniform_Block :: proc(shader: ^Shader, block_name: cstring, binding: u32) {
	index := gl.GetUniformBlockIndex(shader.program, block_name)
	assert(index != gl.INVALID_INDEX, "Shader_Bind_Uniform_Block: block not found in shader")
	gl.UniformBlockBinding(shader.program, index, binding)
	GL_Check()
}

@(private = "file")
uniform_location :: proc(shader: ^Shader, name: string) -> i32 {
	if location, cached := shader.uniform_locations[name]; cached do return location
	name_c := strings.clone_to_cstring(name, context.temp_allocator)
	location := gl.GetUniformLocation(shader.program, name_c)
	assert(location != -1 || shader.tolerate_missing_uniforms, fmt.tprintf("uniform '%s' not found (unused uniforms are optimised out)", name))
	shader.uniform_locations[strings.clone(name)] = location
	return location
}

@(private = "file")
compile_stage :: proc(stage: u32, source: string, label: string) -> (id: u32, ok: bool) {
	id = gl.CreateShader(stage)
	source_c := strings.clone_to_cstring(source, context.temp_allocator)
	gl.ShaderSource(id, 1, &source_c, nil)
	gl.CompileShader(id)
	status: i32
	gl.GetShaderiv(id, gl.COMPILE_STATUS, &status)
	if status != 0 do return id, true
	log_length: i32
	gl.GetShaderiv(id, gl.INFO_LOG_LENGTH, &log_length)
	message := make([]u8, log_length, context.temp_allocator)
	gl.GetShaderInfoLog(id, log_length, nil, raw_data(message))
	fmt.eprintfln("shader compile failed (%s):\n%s", label, string(message))
	gl.DeleteShader(id)
	return 0, false
}

@(private = "file")
program_linked :: proc(program: u32, label: string) -> bool {
	status: i32
	gl.GetProgramiv(program, gl.LINK_STATUS, &status)
	if status != 0 do return true
	log_length: i32
	gl.GetProgramiv(program, gl.INFO_LOG_LENGTH, &log_length)
	message := make([]u8, log_length, context.temp_allocator)
	gl.GetProgramInfoLog(program, log_length, nil, raw_data(message))
	fmt.eprintfln("shader link failed (%s):\n%s", label, string(message))
	return false
}
