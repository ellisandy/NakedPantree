#!/usr/bin/env bash
#
# Reliable local lint that matches CI.
#
# The Xcode-bundled `swift-format` (601.x / 602.x) has a bug where
# `lint --recursive .` silently misses per-file violations that the
# same binary catches when given the file directly. CI's `swift:6.0`
# container doesn't have this bug, so a clean local recursive run can
# (and has, multiple times) ship a PR that fails CI on `[LineLength]`
# or similar.
#
# This script enumerates Swift source files explicitly and lints each
# one, sidestepping the broken --recursive code path. It also runs
# swiftlint with the same `--strict` flag CI uses.
#
# Run before pushing. The pre-commit hook calls this; CI runs the same
# substantive command in `.github/workflows/lint.yml`.

set -euo pipefail

cd "$(dirname "$0")/.."

echo "▶ swift-format (per-file, --strict)"
# Exclude generated and build artifacts. The `find ... -print0 | xargs
# -0 ...` pattern handles paths with spaces and runs swift-format once
# per batch of files instead of once per file (faster).
find . \
  -name '*.swift' \
  -not -path './.build/*' \
  -not -path '*/.build/*' \
  -not -path '*/Build/*' \
  -not -path '*/DerivedData/*' \
  -not -path '*/.swiftpm/*' \
  -not -path '*/NakedPantree.xcodeproj/*' \
  -print0 \
  | xargs -0 swift-format lint --strict

echo "▶ swiftlint (--strict)"
swiftlint lint --strict --quiet

echo "✓ lint clean"
