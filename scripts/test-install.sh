#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
temporary_base="${TMPDIR:-/tmp}"
test_root="$(mktemp -d "$temporary_base/convert-anything-install-test.XXXXXX")"

cleanup() {
  rm -rf -- "$test_root"
}
trap cleanup EXIT HUP INT TERM

fixture_root="$test_root/fixture/convert-anything-test"
archive="$test_root/source.tar.gz"
shim_dir="$test_root/bin"
mkdir -p "$fixture_root/scripts" "$shim_dir"

cat > "$fixture_root/scripts/build-ffmpeg.sh" <<'SCRIPT'
#!/bin/zsh
set -euo pipefail
print "build:$PWD" >> "$INSTALL_TEST_ACTION_LOG"
SCRIPT

cat > "$fixture_root/scripts/install.sh" <<'SCRIPT'
#!/bin/zsh
set -euo pipefail
grep -q '^build:' "$INSTALL_TEST_ACTION_LOG"
print "install:$PWD" >> "$INSTALL_TEST_ACTION_LOG"
SCRIPT

chmod +x "$fixture_root/scripts/build-ffmpeg.sh" "$fixture_root/scripts/install.sh"
tar -czf "$archive" -C "$test_root/fixture" convert-anything-test

cat > "$shim_dir/curl" <<'SCRIPT'
#!/bin/zsh
set -euo pipefail
rewritten_arguments=()
for argument in "$@"; do
  print -r -- "$argument"
  if [[ "$argument" == https://api.github.com/* ]]; then
    rewritten_arguments+=("file://$INSTALL_TEST_ARCHIVE")
  else
    rewritten_arguments+=("$argument")
  fi
done >> "$INSTALL_TEST_CURL_ARGUMENTS_LOG"
exec /usr/bin/curl "${rewritten_arguments[@]}"
SCRIPT

cat > "$shim_dir/gh" <<'SCRIPT'
#!/bin/zsh
set -euo pipefail
print "invoked" >> "$INSTALL_TEST_GH_LOG"
print "INSTALLER_TEST_CLI_CREDENTIAL_SENTINEL"
SCRIPT

chmod +x "$shim_dir/curl" "$shim_dir/gh"

run_installer_case() {
  local case_name="$1"
  shift

  local action_log="$test_root/actions-$case_name.log"
  local curl_arguments_log="$test_root/curl-arguments-$case_name.log"
  local gh_log="$test_root/gh-$case_name.log"
  local installer_output
  installer_output="$(
    /usr/bin/curl -fsSL "file://$repo_root/install.sh" |
      /usr/bin/env -u GH_TOKEN -u GITHUB_TOKEN \
        PATH="$shim_dir:$PATH" \
        INSTALL_TEST_ACTION_LOG="$action_log" \
        INSTALL_TEST_CURL_ARGUMENTS_LOG="$curl_arguments_log" \
        INSTALL_TEST_GH_LOG="$gh_log" \
        INSTALL_TEST_ARCHIVE="$archive" \
        "$@" \
        /bin/bash
  )"

  test "$(wc -l < "$action_log" | tr -d ' ')" = 2
  local build_root="$(sed -n 's/^build://p' "$action_log")"
  local install_root="$(sed -n 's/^install://p' "$action_log")"
  test "$build_root" = "$install_root"
  test ! -e "$build_root"
  grep -q 'Downloading Convert Anything (main)' <<< "$installer_output"
  grep -q 'Convert Anything is installed in /Applications' <<< "$installer_output"

  if grep -q 'INSTALLER_TEST_.*_CREDENTIAL_SENTINEL\|Authorization:' "$curl_arguments_log"; then
    print -u2 "Installer exposed a credential through curl arguments ($case_name)"
    exit 1
  fi
  if [[ -e "$gh_log" ]]; then
    print -u2 "Installer invoked GitHub CLI for authentication ($case_name)"
    exit 1
  fi
}

run_installer_case environment \
  GH_TOKEN=INSTALLER_TEST_ENV_CREDENTIAL_SENTINEL \
  GITHUB_TOKEN=INSTALLER_TEST_FALLBACK_CREDENTIAL_SENTINEL
run_installer_case cli

print "Curl installer test passed"
