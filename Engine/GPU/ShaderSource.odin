package GPU

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

SHADER_INCLUDE_DIRECTORY :: "Shaders/Include"
SHADER_INCLUDE_DEPTH_MAX :: 16

Shader_Stages :: struct {
	vertex:   string,
	fragment: string,
}

// Source layout: `#version` once, optional shared code, then `#stage vertex` and `#stage fragment` sections.
// `#include "File.glsl"` is expanded once per file (include-once), searched beside the including file, then in the include directory.
Shader_Source_Load :: proc(path: string, defines: []string = nil) -> (stages: Shader_Stages, ok: bool) {
	expanded: strings.Builder
	defer strings.builder_destroy(&expanded)
	included := make(map[string]struct{})
	defer delete(included)
	defer for key in included do delete(key)
	if !expand_includes(path, &expanded, &included, 0) do return {}, false
	return split_stages(strings.to_string(expanded), defines)
}

Shader_Stages_Destroy :: proc(stages: ^Shader_Stages) {
	delete(stages.vertex)
	delete(stages.fragment)
	stages^ = {}
}

@(private = "file")
expand_includes :: proc(path: string, output: ^strings.Builder, included: ^map[string]struct{}, depth: int) -> bool {
	if depth > SHADER_INCLUDE_DEPTH_MAX {
		fmt.eprintfln("shader include depth exceeds %d at %s", SHADER_INCLUDE_DEPTH_MAX, path)
		return false
	}
	absolute_path, path_error := filepath.abs(path, context.temp_allocator)
	if path_error != nil {
		fmt.eprintfln("shader path cannot be resolved: %s", path)
		return false
	}
	if absolute_path in included do return true
	included[strings.clone(absolute_path)] = {}
	data, read_error := os.read_entire_file(path, context.temp_allocator)
	if read_error != nil {
		fmt.eprintfln("shader file cannot be read: %s", path)
		return false
	}
	text := string(data)
	for line in strings.split_lines_iterator(&text) {
		include_name, is_include := parse_include(line)
		if !is_include {
			strings.write_string(output, line)
			strings.write_byte(output, '\n')
			continue
		}
		include_path := resolve_include(path, include_name)
		if !expand_includes(include_path, output, included, depth + 1) do return false
	}
	return true
}

@(private = "file")
parse_include :: proc(line: string) -> (name: string, ok: bool) {
	trimmed := strings.trim_space(line)
	if !strings.has_prefix(trimmed, "#include") do return "", false
	first_quote := strings.index_byte(trimmed, '"')
	last_quote := strings.last_index_byte(trimmed, '"')
	if first_quote < 0 || last_quote <= first_quote do return "", false
	return trimmed[first_quote + 1:last_quote], true
}

@(private = "file")
resolve_include :: proc(including_path, name: string) -> string {
	beside, _ := filepath.join({filepath.dir(including_path), name}, context.temp_allocator)
	if os.exists(beside) do return beside
	shared, _ := filepath.join({SHADER_INCLUDE_DIRECTORY, name}, context.temp_allocator)
	return shared
}

@(private = "package")
split_stages :: proc(source: string, defines: []string) -> (stages: Shader_Stages, ok: bool) {
	Section :: enum {Shared, Vertex, Fragment}
	builders: [Section]strings.Builder
	defer for &builder in builders do strings.builder_destroy(&builder)
	version_line := ""
	section := Section.Shared
	text := source
	for line in strings.split_lines_iterator(&text) {
		trimmed := strings.trim_space(line)
		switch {
		case strings.has_prefix(trimmed, "#version"):
			version_line = trimmed
		case trimmed == "#stage vertex":
			section = .Vertex
		case trimmed == "#stage fragment":
			section = .Fragment
		case:
			strings.write_string(&builders[section], line)
			strings.write_byte(&builders[section], '\n')
		}
	}
	if version_line == "" || builders[.Vertex].buf == nil || builders[.Fragment].buf == nil {
		fmt.eprintln("shader source needs #version, #stage vertex and #stage fragment")
		return {}, false
	}
	header := build_header(version_line, defines)
	defer delete(header)
	stages.vertex = strings.concatenate({header, strings.to_string(builders[.Shared]), strings.to_string(builders[.Vertex])})
	stages.fragment = strings.concatenate({header, strings.to_string(builders[.Shared]), strings.to_string(builders[.Fragment])})
	return stages, true
}

@(private = "file")
build_header :: proc(version_line: string, defines: []string) -> string {
	header: strings.Builder
	strings.write_string(&header, version_line)
	strings.write_byte(&header, '\n')
	for define in defines do fmt.sbprintfln(&header, "#define %s", define)
	return strings.to_string(header)
}
