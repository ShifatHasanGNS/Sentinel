package GPU

import "core:strings"
import "core:testing"

@(test)
test_include_expands_once_and_splits_stages :: proc(t: ^testing.T) {
	stages, ok := Shader_Source_Load("Engine/GPU/Fixtures/IncludeMain.glsl", {"EXTRA_FLAG"})
	defer Shader_Stages_Destroy(&stages)
	testing.expect(t, ok)
	testing.expect(t, strings.has_prefix(stages.vertex, "#version 410 core\n#define EXTRA_FLAG\n"))
	testing.expect_value(t, strings.count(stages.vertex, "#define SHARED_VALUE"), 1)
	testing.expect_value(t, strings.count(stages.fragment, "#define SHARED_VALUE"), 1)
	testing.expect(t, strings.contains(stages.vertex, "gl_Position"))
	testing.expect(t, !strings.contains(stages.vertex, "out vec4 color"))
	testing.expect(t, strings.contains(stages.fragment, "out vec4 color"))
	testing.expect(t, !strings.contains(stages.fragment, "gl_Position"))
}

@(test)
test_missing_file_fails_without_crashing :: proc(t: ^testing.T) {
	_, ok := Shader_Source_Load("Engine/GPU/Fixtures/DoesNotExist.glsl")
	testing.expect(t, !ok)
}

@(test)
test_split_rejects_source_without_stages :: proc(t: ^testing.T) {
	_, ok := split_stages("#version 410 core\nvoid main() {}\n", nil)
	testing.expect(t, !ok)
}
