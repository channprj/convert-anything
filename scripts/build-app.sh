#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
repo_root="${script_dir:h}"
app_bundle="$repo_root/dist/Convert Anything.app"
tool_dir="$repo_root/build/vendor/ffmpeg/bin"
release_executable="$repo_root/.build/release/ConvertAnythingApp"

if [[ "$app_bundle" != "$repo_root/dist/Convert Anything.app" || "$repo_root" == "/" ]]; then
  print -u2 "Refusing unsafe app bundle target: $app_bundle"
  exit 1
fi

test -x "$tool_dir/ffmpeg"
test -x "$tool_dir/ffprobe"

cd "$repo_root"
swift build -c release --product ConvertAnythingApp

rm -rf -- "$app_bundle"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
cp "$release_executable" "$app_bundle/Contents/MacOS/ConvertAnything"
cp "$repo_root/App/Info.plist" "$app_bundle/Contents/Info.plist"
cp "$tool_dir/ffmpeg" "$tool_dir/ffprobe" "$app_bundle/Contents/Resources/"
cp "$repo_root/THIRD_PARTY_NOTICES.md" "$app_bundle/Contents/Resources/"
cp -R "$tool_dir/../source-offer" "$app_bundle/Contents/Resources/source-offer"
chmod +x \
  "$app_bundle/Contents/MacOS/ConvertAnything" \
  "$app_bundle/Contents/Resources/ffmpeg" \
  "$app_bundle/Contents/Resources/ffprobe"

strip -x "$app_bundle/Contents/MacOS/ConvertAnything"
strip -x "$app_bundle/Contents/Resources/ffmpeg"
strip -x "$app_bundle/Contents/Resources/ffprobe"

codesign --force --sign - --timestamp=none "$app_bundle/Contents/Resources/ffmpeg"
codesign --force --sign - --timestamp=none "$app_bundle/Contents/Resources/ffprobe"
codesign --force --deep --sign - --timestamp=none "$app_bundle"

zsh "$repo_root/scripts/test-packaging.sh"
print "Built app bundle: $app_bundle"
