#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
app_bundle="$repo_root/dist/Optimize Anything.app"
app_executable="$app_bundle/Contents/MacOS/OptimizeAnything"
resource_dir="$app_bundle/Contents/Resources"

test -x "$app_executable"
test -x "$resource_dir/ffmpeg"
test -x "$resource_dir/ffprobe"
test -f "$resource_dir/THIRD_PARTY_NOTICES.md"
test -f "$resource_dir/source-offer/BUILD.txt"
test -f "$resource_dir/source-offer/versions.env"
test -f "$resource_dir/source-offer/ffmpeg-8.0.tar.xz"
test -f "$resource_dir/source-offer/libvpx-1.15.0.tar.gz"
test -f "$resource_dir/source-offer/libaom-3.12.1.tar.gz"
test -f "$resource_dir/source-offer/opus-1.5.2.tar.gz"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$app_bundle/Contents/Info.plist")" = true
codesign --verify --deep --strict "$app_bundle"
build_configuration="$("$resource_dir/ffmpeg" -hide_banner -buildconf 2>&1)"
encoder_list="$("$resource_dir/ffmpeg" -hide_banner -encoders 2>&1)"
grep -q -- '--disable-gpl' <<< "$build_configuration"
grep -q -- '--disable-nonfree' <<< "$build_configuration"
grep -q 'libvpx-vp9' <<< "$encoder_list"
grep -q 'libaom-av1' <<< "$encoder_list"
grep -q 'libopus' <<< "$encoder_list"

file "$app_executable" | grep -q 'arm64'
file "$resource_dir/ffmpeg" | grep -q 'arm64'
file "$resource_dir/ffprobe" | grep -q 'arm64'

for binary in "$app_executable" "$resource_dir/ffmpeg" "$resource_dir/ffprobe"; do
  dependencies="$(otool -L "$binary" | tail -n +2)"
  if grep -E '/(opt/homebrew|usr/local|Volumes|Users)/' <<< "$dependencies" >/dev/null; then
    print -u2 "Non-system dependency found in $binary"
    exit 1
  fi
done

print "Packaging checks passed: $app_bundle"
