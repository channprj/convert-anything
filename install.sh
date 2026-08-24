#!/usr/bin/env bash
set -euo pipefail

repository="channprj/convert-anything"
repository_ref="${CONVERT_ANYTHING_REF:-main}"
source_url="${CONVERT_ANYTHING_SOURCE_URL:-https://api.github.com/repos/$repository/tarball/$repository_ref}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf '%s\n' "Convert Anything requires macOS 14 or later." >&2
  exit 1
fi

if [[ "$(uname -m)" != "arm64" ]]; then
  printf '%s\n' "Convert Anything currently supports Apple Silicon Macs only." >&2
  exit 1
fi

macos_version="$(sw_vers -productVersion)"
macos_major="${macos_version%%.*}"
if (( macos_major < 14 )); then
  printf '%s\n' "Convert Anything requires macOS 14 or later (found $macos_version)." >&2
  exit 1
fi

required_commands=(curl tar swift cmake ninja pkg-config make clang codesign ditto pgrep osascript open)
missing_commands=()
for required_command in "${required_commands[@]}"; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    missing_commands+=("$required_command")
  fi
done

if (( ${#missing_commands} > 0 )); then
  missing_list=""
  for missing_command in "${missing_commands[@]}"; do
    if [[ -n "$missing_list" ]]; then
      missing_list="$missing_list, "
    fi
    missing_list="$missing_list$missing_command"
  done
  printf '%s\n' "Missing required build tools: $missing_list" >&2
  printf '%s\n' "Install Xcode Command Line Tools and the media build dependencies:" >&2
  printf '%s\n' "  xcode-select --install" >&2
  printf '%s\n' "  brew install cmake ninja pkg-config" >&2
  exit 1
fi

temporary_base="${TMPDIR:-/tmp}"
work_dir="$(mktemp -d "$temporary_base/convert-anything-install.XXXXXX")"
archive="$work_dir/source.tar.gz"
source_root="$work_dir/source"

cleanup() {
  rm -rf -- "$work_dir"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$source_root"

curl_arguments=(
  --fail
  --location
  --retry 3
  --show-error
  --silent
  --output "$archive"
)

printf '%s\n' "Downloading Convert Anything ($repository_ref)..."
if ! curl "${curl_arguments[@]}" "$source_url"; then
  printf '%s\n' "Could not download the Convert Anything source." >&2
  exit 1
fi

tar -xzf "$archive" -C "$source_root" --strip-components=1
if [[ ! -x "$source_root/scripts/build-ffmpeg.sh" || ! -x "$source_root/scripts/install.sh" ]]; then
  printf '%s\n' "The downloaded source does not contain the expected installer scripts." >&2
  exit 1
fi

cd "$source_root"
printf '%s\n' "Building the bundled media tools. This can take several minutes..."
zsh scripts/build-ffmpeg.sh
zsh scripts/install.sh

printf '%s\n' "Convert Anything is installed in /Applications."
