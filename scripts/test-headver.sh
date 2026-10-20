#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
repo_root="${script_dir:h}"
headver="$repo_root/scripts/headver.sh"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/headver.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

expect_eq() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  if [[ "$actual" != "$expected" ]]; then
    print -u2 "${label}: expected ${expected}, got ${actual}"
    exit 1
  fi
}

while read -r day expected; do
  [[ -n "$day" ]] || continue
  actual="$("$headver" yearweek "$day")"
  expect_eq "$actual" "$expected" "$day"
done <<'EOF'
2012-01-01 1152
2018-01-01 1801
2018-01-02 1801
2018-01-07 1801
2018-01-06 1801
2019-01-01 1901
2015-01-01 1501
2010-01-01 0953
2018-12-31 1901
2019-12-31 2001
2009-12-31 0953
2011-12-31 1152
2017-12-31 1752
2015-01-01 1501
2015-12-31 1553
2016-01-01 1553
2016-12-31 1652
EOF

version_file="$scratch/VERSION"
print -r -- '0.2642.7' > "$version_file"
expect_eq "$("$headver" bump "$version_file" 2026-10-20)" "0.2643.8" "week rollover keeps head and increments build"
expect_eq "$(tr -d '[:space:]' < "$version_file")" "0.2643.8" "bump writes VERSION"
expect_eq "$("$headver" bump "$version_file" 2026-10-20)" "0.2643.9" "same week increments build"

print -r -- '2.1552.4' > "$version_file"
expect_eq "$("$headver" bump "$version_file" 2016-01-01)" "2.1553.5" "manual head is preserved"

print -r -- '0.1.0' > "$version_file"
if "$headver" bump "$version_file" 2026-10-20 >/dev/null 2>"$scratch/invalid.err"; then
  print -u2 "invalid VERSION was accepted"
  exit 1
fi

root="$scratch/app"
mkdir -p "$root/App"
print -r -- '0.2643.0' > "$root/VERSION"
cp "$repo_root/App/Info.plist" "$root/App/Info.plist"
expect_eq "$("$headver" apply --root "$root" --date 2026-10-20)" "0.2643.1" "apply bumps the checkout"
expect_eq "$(tr -d '[:space:]' < "$root/VERSION")" "0.2643.1" "apply writes VERSION"
plist="$root/App/Info.plist"
expect_eq "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" "0.2643.1" "short version"
expect_eq "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")" "0.2643.1" "bundle version"
expect_eq "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" "com.channprj.convert-anything" "plist identity preserved"

print "HeadVer checks passed"
