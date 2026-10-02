#!/bin/sh
# Converts a BMP screenshot to PNG (macOS sips) so image viewers can open it.
# Usage: Tools/ToPng.sh <capture.bmp> [output.png]
set -eu
[ "$#" -ge 1 ] || { echo "usage: $0 <capture.bmp> [output.png]" >&2; exit 1; }
output="${2:-${1%.bmp}.png}"
sips -s format png "$1" --out "$output" >/dev/null
echo "$output"
