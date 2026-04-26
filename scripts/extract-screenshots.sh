#!/usr/bin/env bash
#
# Pull screenshot attachments out of an xcresult bundle into a
# Fastlane-shaped tree:
#
#     screenshots/<locale>/<device>/<attachment-name>.png
#
# Usage:
#     scripts/extract-screenshots.sh <xcresult-path> <device-label> [locale]
#
# Example:
#     scripts/extract-screenshots.sh Snapshots.xcresult "iPhone 6.9" en-US
#
# `device-label` is whatever path-segment label you want (e.g.
# "iPhone 6.9" or "iPhone 17 Pro Max"). Locale defaults to en-US.
#
# Requires Xcode 16+ — uses `xcresulttool export attachments`. The
# command writes one file per attachment plus a `manifest.json` that
# maps attachment names to filenames; we rename the exported files to
# match the names set on `XCTAttachment` so the output is human-
# readable.

set -euo pipefail

if [ "$#" -lt 2 ]; then
    echo "usage: $0 <xcresult-path> <device-label> [locale]" >&2
    exit 64
fi

XCRESULT_PATH="$1"
DEVICE_LABEL="$2"
LOCALE="${3:-en-US}"
OUTPUT_DIR="screenshots/${LOCALE}/${DEVICE_LABEL}"

if [ ! -d "$XCRESULT_PATH" ]; then
    echo "error: $XCRESULT_PATH not found" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

xcrun xcresulttool export attachments \
    --path "$XCRESULT_PATH" \
    --output-path "$TMP_DIR" >/dev/null

# `manifest.json` maps each test's attachments to the
# auto-generated `exportedFileName` and the human `suggestedHumanReadableName`
# we set on the XCTAttachment. Walk it with python and copy the files
# into the final tree using the human names.
python3 - "$TMP_DIR" "$OUTPUT_DIR" <<'PY'
import json
import os
import re
import shutil
import sys

source = sys.argv[1]
dest = sys.argv[2]

manifest_path = os.path.join(source, "manifest.json")
with open(manifest_path) as fp:
    manifest = json.load(fp)

# xcresulttool decorates the human name with `_<index>_<UUID>.png` —
# strip that suffix back to the bare name we set on the XCTAttachment.
suffix_pattern = re.compile(r"_\d+_[0-9A-F-]{30,}\.png$", re.IGNORECASE)

count = 0
for entry in manifest:
    for attachment in entry.get("attachments", []):
        exported = attachment.get("exportedFileName")
        human = attachment.get("suggestedHumanReadableName") or exported
        if not exported or not exported.lower().endswith(".png"):
            continue
        src = os.path.join(source, exported)
        if not os.path.exists(src):
            continue
        clean = suffix_pattern.sub(".png", human)
        if not clean.lower().endswith(".png"):
            clean += ".png"
        target = os.path.join(dest, clean)
        shutil.copyfile(src, target)
        count += 1

print(f"Wrote {count} PNG(s) to {dest}")
PY
