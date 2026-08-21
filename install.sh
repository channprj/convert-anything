#!/bin/zsh
set -euo pipefail

repository="channprj/convert-anything"
repository_ref="${CONVERT_ANYTHING_REF:-main}"
source_url="${CONVERT_ANYTHING_SOURCE_URL:-https://api.github.com/repos/$repository/tarball/$repository_ref}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  print -u2 "Convert Anything requires macOS 14 or later."
  exit 1
fi

if [[ "$(uname -m)" != "arm64" ]]; then
  print -u2 "Convert Anything currently supports Apple Silicon Macs only."
  exit 1
fi

macos_version="$(sw_vers -productVersion)"
macos_major="${macos_version%%.*}"
if (( macos_major < 14 )); then
  print -u2 "Convert Anything requires macOS 14 or later (found $macos_version)."
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
  print -u2 "Missing required build tools: ${(j:, :)missing_commands}"
  print -u2 "Install Xcode Command Line Tools and the media build dependencies:"
  print -u2 "  xcode-select --install"
  print -u2 "  brew install cmake ninja pkg-config"
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

print "Downloading Convert Anything ($repository_ref)..."
if ! curl "${curl_arguments[@]}" "$source_url"; then
  print -u2 "Could not download the Convert Anything source."
  exit 1
fi

tar -xzf "$archive" -C "$source_root" --strip-components=1
if [[ ! -x "$source_root/scripts/build-ffmpeg.sh" || ! -x "$source_root/scripts/install.sh" ]]; then
  print -u2 "The downloaded source does not contain the expected installer scripts."
  exit 1
fi

cd "$source_root"
print "Building the bundled media tools. This can take several minutes..."
zsh scripts/build-ffmpeg.sh
zsh scripts/install.sh

print "Convert Anything is installed in /Applications."
