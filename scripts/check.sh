#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
repo_root="${script_dir:h}"
cd "$repo_root"

swift format lint --strict --recursive Package.swift Sources Tests
swift run ConvertAnythingCoreTests
swift run ConvertAnythingMacTests
swift build -c release --product ConvertAnythingApp
zsh scripts/build-app.sh
zsh scripts/integration-test.sh
zsh scripts/runtime-smoke.sh
zsh scripts/test-packaging.sh
git diff --check

print "All checks passed: 76 core, 6 macOS, 10 integration"
print "Artifact: $repo_root/dist/Convert Anything.app"
