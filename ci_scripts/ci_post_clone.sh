#!/usr/bin/env bash
#
# Xcode Cloud post-clone hook. Runs once per build after the repo is
# cloned, before any xcodebuild step.
#
# This repo doesn't commit `*.xcodeproj/` (see .gitignore + project.yml
# — XcodeGen regenerates it) so without this script Xcode Cloud's
# `xcodebuild` step can't find a project to build.
#
# Apple looks for this script at the literal path `ci_scripts/ci_post_clone.sh`
# next to `project.yml`. Folder and filename are fixed — do not rename.

set -euo pipefail

echo "▶ Installing XcodeGen via Homebrew"
brew install xcodegen

# Xcode Cloud sets `$CI_PRIMARY_REPOSITORY_PATH` to the repo root.
# Fall back to the script's parent directory when unset (so the same
# script runs locally for sanity-checking).
ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT"

echo "▶ Generating Xcode project from project.yml"
xcodegen generate

echo "✓ Xcode Cloud post-clone complete"
