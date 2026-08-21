#!/bin/zsh
set -euo pipefail

# Builds dist/Convert Anything.app and installs it into /Applications,
# replacing any previous copy. A running instance is quit first.

script_dir="${0:A:h}"
repo_root="${script_dir:h}"
app_bundle="$repo_root/dist/Convert Anything.app"
install_target="/Applications/Convert Anything.app"

if [[ ! -x "$repo_root/build/vendor/ffmpeg/bin/ffmpeg" ]]; then
  print -u2 "Bundled media tools are missing. Run once first:"
  print -u2 "  zsh scripts/build-ffmpeg.sh"
  exit 1
fi

zsh "$repo_root/scripts/build-app.sh"

if pgrep -x ConvertAnything >/dev/null; then
  osascript -e 'tell application id "com.channprj.convert-anything" to quit' >/dev/null
  deadline=$((SECONDS + 10))
  while pgrep -x ConvertAnything >/dev/null && (( SECONDS < deadline )); do
    sleep 0.2
  done
  if pgrep -x ConvertAnything >/dev/null; then
    print -u2 "Convert Anything did not quit; close it manually and rerun"
    exit 1
  fi
fi

rm -rf -- "$install_target"
ditto "$app_bundle" "$install_target"
codesign --verify --deep --strict "$install_target"
open "$install_target"
print "Installed and launched: $install_target"
