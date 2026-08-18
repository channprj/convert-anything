#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
repo_root="${script_dir:h}"
tool_dir="${CONVERT_ANYTHING_TOOL_DIR:-$repo_root/build/vendor/ffmpeg/bin}"
ffmpeg="$tool_dir/ffmpeg"
fixture_dir="${1:-}"

if [[ -z "$fixture_dir" || "$fixture_dir" != /* || "$fixture_dir" == "/" || "$fixture_dir" == "$repo_root" ]]; then
  print -u2 "Usage: $0 <absolute-fixture-directory>"
  exit 1
fi
test -x "$ffmpeg"

mkdir -p "$fixture_dir"
find "$fixture_dir" -mindepth 1 -delete

common=(-nostdin -hide_banner -loglevel error -y)
"$ffmpeg" "${common[@]}" -f lavfi -i 'sine=frequency=440:duration=1' \
  -c:a pcm_s16le "$fixture_dir/voice.wav"
"$ffmpeg" "${common[@]}" -f lavfi -i 'testsrc2=size=320x180:rate=24:duration=1' \
  -f lavfi -i 'sine=frequency=880:duration=1' -c:v prores_ks -c:a pcm_s16le \
  -shortest "$fixture_dir/movie.mov"
"$ffmpeg" "${common[@]}" -f lavfi -i 'color=c=0x3366cc:s=96x64:d=1' \
  -frames:v 1 "$fixture_dir/opaque.png"
"$ffmpeg" "${common[@]}" -f lavfi -i 'color=c=red@0.4:s=96x64:d=1,format=rgba' \
  -frames:v 1 "$fixture_dir/alpha.png"
"$ffmpeg" "${common[@]}" -f lavfi -i 'testsrc2=size=640x360:rate=60:duration=20' \
  -c:v mpeg4 -q:v 5 -an "$fixture_dir/long.mov"

(
  cd "$fixture_dir"
  shasum -a 256 voice.wav movie.mov opaque.png alpha.png long.mov > sources.sha256
)
print "Generated deterministic fixtures: $fixture_dir"
