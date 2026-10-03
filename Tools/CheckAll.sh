#!/bin/sh
# Runs every unit-test package and the GL check programs; stops with a non-zero exit at the first failure.
# Usage: Tools/CheckAll.sh   (from the repository root)
set -u
status=0
for package in Engine/GPU Engine/Procedural Engine/Render Engine/World Game/Catalogue Game/Base Game/Characters Game/Weapons Game/Gameplay Game/Vehicles Game/Mission Engine/Audio Game/Sandbox; do
	name=$(basename "$package")
	output=$(odin test "$package" -out:/tmp/sentinel_test_$name 2>&1)
	summary=$(printf '%s\n' "$output" | grep -E "Finished [0-9]+ tests" | tail -1)
	case "$summary" in
	*"All tests were successful"*) printf 'ok    %s  %s\n' "$package" "$summary" ;;
	*) printf 'FAIL  %s\n%s\n' "$package" "$output" | tail -15; status=1 ;;
	esac
done
for check in GpuCheck TextureCheck RenderCheck; do
	output=$(odin run Tests/$check -out:/tmp/sentinel_$check 2>&1)
	case "$output" in
	*" 0 failed"*) printf 'ok    Tests/%s  %s\n' "$check" "$(printf '%s\n' "$output" | tail -1)" ;;
	*) printf 'FAIL  Tests/%s\n%s\n' "$check" "$output" | tail -15; status=1 ;;
	esac
done
# End-to-end: the scripted playthrough must complete every objective of both missions (needs a built ./SentinelFast).
if [ -x ./SentinelFast ]; then
	for mission in rescue night; do
		count=$(SENTINEL_SAVE_DIR=/tmp/sentinel_check_save ./SentinelFast --autoplay --mission $mission --capture 900 /tmp/sentinel_check.bmp 2>&1 | grep -c "AUTOPLAY .* completed")
		if [ "$count" = "5" ]; then printf 'ok    autoplay %s  5 objectives completed\n' "$mission"; else printf 'FAIL  autoplay %s  %s of 5 objectives\n' "$mission" "$count"; status=1; fi
	done
fi
exit $status
