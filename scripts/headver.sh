#!/bin/zsh
set -euo pipefail

# HeadVer (https://github.com/line/headver): head.yearweek.build
# head is manual. yearweek is the ISO-8601 week (YYWW). build increases by one.

script_dir="${0:A:h}"
repo_root="${script_dir:h}"
headver_pattern='^[0-9]+\.[0-9]{4}\.[0-9]+$'

yearweek_for() {
  local when="${1:-}"
  local iso_year iso_week
  if [[ -n "$when" ]]; then
    iso_year="$(date -j -f '%Y-%m-%d' "$when" '+%G')"
    iso_week="$(date -j -f '%Y-%m-%d' "$when" '+%V')"
  else
    iso_year="$(date '+%G')"
    iso_week="$(date '+%V')"
  fi
  if [[ ${#iso_year} -ne 4 || ${#iso_week} -ne 2 ]]; then
    print -u2 "Could not format an ISO year-week from '${when:-today}'"
    return 1
  fi
  print "${iso_year:2:2}${iso_week}"
}

next_version() {
  local current="$1"
  local when="${2:-}"
  if [[ ! "$current" =~ $headver_pattern ]]; then
    print -u2 "VERSION must be head.yearweek.build (got '${current}')"
    return 1
  fi
  local head rest build yearweek next_build
  head="${current%%.*}"
  rest="${current#*.}"
  build="${rest#*.}"
  yearweek="$(yearweek_for "$when")"
  next_build=$((10#$build + 1))
  print "${head}.${yearweek}.${next_build}"
}

read_version_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    print -u2 "VERSION file is missing: $file"
    return 1
  fi
  tr -d '[:space:]' < "$file"
}

write_version_file() {
  local file="$1"
  local version="$2"
  local tmp
  tmp="$(mktemp "${file}.XXXXXX")"
  print -r -- "$version" > "$tmp"
  mv -f "$tmp" "$file"
}

stamp_plist() {
  local plist="$1"
  local version="$2"
  local tmp
  tmp="$(mktemp "${plist}.XXXXXX")"
  cp "$plist" "$tmp"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${version}" "$tmp" >/dev/null
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${version}" "$tmp" >/dev/null
  mv -f "$tmp" "$plist"
}

ensure_hooks_path() {
  local current
  current="$(git -C "$repo_root" config --local --get core.hooksPath || true)"
  if [[ -z "$current" ]]; then
    git -C "$repo_root" config --local core.hooksPath scripts/git-hooks
  elif [[ "$current" != "scripts/git-hooks" ]]; then
    print -u2 "core.hooksPath is '${current}', so headver tags are not pushed automatically"
  fi
}

apply_bump() {
  local root="$1"
  local when="${2:-}"
  local version_file="$root/VERSION"
  local plist="$root/App/Info.plist"
  local current next
  if [[ ! -f "$plist" ]]; then
    print -u2 "Info.plist is missing: $plist"
    return 1
  fi
  current="$(read_version_file "$version_file")"
  next="$(next_version "$current" "$when")"
  stamp_plist "$plist" "$next"
  write_version_file "$version_file" "$next"
  if [[ "$root" == "$repo_root" ]]; then
    ensure_hooks_path
  fi
  print "$next"
}

usage() {
  print -u2 "Usage:"
  print -u2 "  scripts/headver.sh yearweek [YYYY-MM-DD]"
  print -u2 "  scripts/headver.sh bump <VERSION-file> [YYYY-MM-DD]"
  print -u2 "  scripts/headver.sh apply [--root DIR] [--date YYYY-MM-DD]"
}

command="${1:-}"
if [[ $# -gt 0 ]]; then
  shift
fi

case "$command" in
  yearweek)
    yearweek_for "${1:-}"
    ;;
  bump)
    if [[ $# -lt 1 || $# -gt 2 ]]; then
      usage
      exit 1
    fi
    current="$(read_version_file "$1")"
    next="$(next_version "$current" "${2:-}")"
    write_version_file "$1" "$next"
    print "$next"
    ;;
  apply)
    root="$repo_root"
    when=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --root)
          root="${2:?}"
          shift 2
          ;;
        --date)
          when="${2:?}"
          shift 2
          ;;
        *)
          usage
          exit 1
          ;;
      esac
    done
    apply_bump "$root" "$when"
    ;;
  *)
    usage
    exit 1
    ;;
esac
