#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
repo_root="${script_dir:h}"
tool_dir="${OPTIMIZE_ANYTHING_TOOL_DIR:-$repo_root/build/vendor/ffmpeg/bin}"
test -x "$tool_dir/ffmpeg"
test -x "$tool_dir/ffprobe"

scratch_root="$(mktemp -d "${TMPDIR:-/tmp}/optimize-anything-integration.XXXXXX")"
cleanup() {
  find "$scratch_root" -depth -delete
}
trap cleanup EXIT

fixture_dir="$scratch_root/fixtures"
OPTIMIZE_ANYTHING_TOOL_DIR="$tool_dir" zsh "$repo_root/scripts/generate-fixtures.sh" "$fixture_dir"
cd "$repo_root"
OPTIMIZE_ANYTHING_TOOL_DIR="$tool_dir" \
  OPTIMIZE_ANYTHING_FIXTURE_DIR="$fixture_dir" \
  swift run OptimizeAnythingIntegrationTests
