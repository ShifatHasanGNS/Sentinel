#!/bin/sh
# Debug/ToPng.sh — convert a --capture screenshot (BMP) to PNG so it can be
# viewed with an image viewer/Claude Code's file reader.
#
# core:image/bmp is Odin's only core-library image encoder in this build
# (core:image/png only decodes), so Save_Screenshot (Debug/Capture.odin)
# writes BMP. This script is NOT part of the SENTINEL program and is never
# invoked by it; it exists purely so a human or a Claude Code session can
# look at a capture during development. See PROGRESS.md.
#
# Usage: Debug/ToPng.sh <capture.bmp> [output.png]
# Uses macOS's built-in `sips` — no extra install required.

set -eu

if [ "$#" -lt 1 ]; then
	echo "usage: $0 <capture.bmp> [output.png]" >&2
	exit 1
fi

input="$1"
output="${2:-${input%.bmp}.png}"

sips -s format png "$input" --out "$output" >/dev/null
echo "$output"
