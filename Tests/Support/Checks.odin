package Support

import "core:fmt"

Checks :: struct {
	passed: int,
	failed: int,
}

expect :: proc(checks: ^Checks, condition: bool, loc := #caller_location) {
	if condition {checks.passed += 1; return}
	checks.failed += 1
	fmt.eprintfln("FAILED at %v", loc)
}

expect_value :: proc(checks: ^Checks, actual, expected: $T, loc := #caller_location) {
	if actual == expected {checks.passed += 1; return}
	checks.failed += 1
	fmt.eprintfln("FAILED at %v: got %v, expected %v", loc, actual, expected)
}
