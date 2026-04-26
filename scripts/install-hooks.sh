#!/usr/bin/env bash
#
# Install the pre-commit hook by symlinking it into .git/hooks.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
HOOK_TARGET="$REPO_ROOT/scripts/pre-commit"
HOOK_LINK="$REPO_ROOT/.git/hooks/pre-commit"

if [ ! -f "$HOOK_TARGET" ]; then
    echo "install-hooks: $HOOK_TARGET not found." >&2
    exit 1
fi

mkdir -p "$REPO_ROOT/.git/hooks"
ln -sf "../../scripts/pre-commit" "$HOOK_LINK"
chmod +x "$HOOK_TARGET"

echo "install-hooks: pre-commit hook linked → $HOOK_LINK"
echo "install-hooks: requires \`swift-format\` and \`swiftlint\` on PATH (Homebrew)."
