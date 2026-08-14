#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
repo_root="${script_dir:h}"
app_bundle="$repo_root/dist/Optimize Anything.app"
app_executable="$app_bundle/Contents/MacOS/OptimizeAnything"
resource_dir="$app_bundle/Contents/Resources"
scratch_root="$(mktemp -d "${TMPDIR:-/tmp}/optimize-anything-runtime.XXXXXX")"
app_pid=""

cleanup() {
  if [[ -n "$app_pid" ]] && kill -0 "$app_pid" 2>/dev/null; then
    kill -TERM "$app_pid" 2>/dev/null || true
    wait "$app_pid" 2>/dev/null || true
  fi
  find "$scratch_root" -depth -delete
}
trap cleanup EXIT

test -x "$app_executable"
test -x "$resource_dir/ffmpeg"
test -x "$resource_dir/ffprobe"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$app_bundle/Contents/Info.plist")" = true

existing_pids="$(pgrep -x OptimizeAnything || true)"
if [[ -n "$existing_pids" ]]; then
  print -u2 "OptimizeAnything is already running: $existing_pids"
  exit 1
fi

fixture_dir="$scratch_root/fixtures"
home_dir="$scratch_root/home"
mkdir -p "$home_dir"
OPTIMIZE_ANYTHING_TOOL_DIR="$resource_dir" \
  zsh "$repo_root/scripts/generate-fixtures.sh" "$fixture_dir"

log_file="$scratch_root/app.log"
CFFIXED_USER_HOME="$home_dir" "$app_executable" --ingest \
  "$fixture_dir/voice.wav" \
  "$fixture_dir/movie.mov" \
  "$fixture_dir/opaque.png" \
  "$fixture_dir/alpha.png" \
  >"$log_file" 2>&1 &
app_pid=$!

expected_outputs=(
  "$fixture_dir/voice.m4a"
  "$fixture_dir/movie.webm"
  "$fixture_dir/opaque.avif"
  "$fixture_dir/alpha.avif"
)
deadline=$((SECONDS + 90))
while (( SECONDS < deadline )); do
  if ! kill -0 "$app_pid" 2>/dev/null; then
    print -u2 "Packaged app exited before conversion completed"
    tail -n 200 "$log_file" >&2
    exit 1
  fi
  all_complete=true
  for output in "${expected_outputs[@]}"; do
    if [[ ! -s "$output" ]]; then
      all_complete=false
      break
    fi
  done
  $all_complete && break
  sleep 0.1
done

for output in "${expected_outputs[@]}"; do
  if [[ ! -s "$output" ]]; then
    print -u2 "Timed out waiting for $output"
    tail -n 200 "$log_file" >&2
    exit 1
  fi
done

process_count="$(pgrep -x OptimizeAnything | wc -l | tr -d ' ')"
test "$process_count" = 1
test "$(pgrep -x OptimizeAnything)" = "$app_pid"
(
  cd "$fixture_dir"
  shasum -a 256 -c sources.sha256
)
if find "$fixture_dir" -maxdepth 1 -type f -name '.*.optimize-anything-*' | grep -q .; then
  print -u2 "Runtime smoke left a temporary conversion file"
  exit 1
fi

ffprobe="$resource_dir/ffprobe"
test "$("$ffprobe" -v error -select_streams a:0 -show_entries stream=codec_name -of default=nw=1:nk=1 "$fixture_dir/voice.m4a")" = aac
test "$("$ffprobe" -v error -select_streams v:0 -show_entries stream=codec_name -of default=nw=1:nk=1 "$fixture_dir/movie.webm")" = vp9
test "$("$ffprobe" -v error -select_streams a:0 -show_entries stream=codec_name -of default=nw=1:nk=1 "$fixture_dir/movie.webm")" = opus
test "$("$ffprobe" -v error -select_streams v:0 -show_entries stream=codec_name -of default=nw=1:nk=1 "$fixture_dir/opaque.avif")" = av1
test "$("$ffprobe" -v error -select_streams v:0 -show_entries stream=codec_name -of default=nw=1:nk=1 "$fixture_dir/alpha.avif")" = av1
alpha_stream_count="$("$ffprobe" -v error -select_streams v -show_entries stream=index -of csv=p=0 "$fixture_dir/alpha.avif" | wc -l | tr -d ' ')"
test "$alpha_stream_count" = 2

osascript -e 'tell application id "com.channprj.optimize-anything" to quit' >/dev/null
quit_deadline=$((SECONDS + 10))
while kill -0 "$app_pid" 2>/dev/null && (( SECONDS < quit_deadline )); do
  sleep 0.1
done
if kill -0 "$app_pid" 2>/dev/null; then
  print -u2 "Packaged app did not terminate normally"
  exit 1
fi
wait "$app_pid"
app_pid=""
print "Runtime smoke passed: four packaged conversions, one process, sources preserved"
