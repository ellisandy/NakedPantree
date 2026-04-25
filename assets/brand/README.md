# Brand Assets

Source-of-truth assets for the Naked Pantree brand. See
[`DESIGN_GUIDELINES.md`](../../DESIGN_GUIDELINES.md) for the full spec.

## Contents

| File | Purpose |
| --- | --- |
| `colors.json` | Machine-readable brand palette. Import into design tools, codegen, or theme files. |

## Pending (designer to add)

These are placeholders — drop the files in when ready, then update this table:

| File | Purpose |
| --- | --- |
| `brand-sheet.png` | Single-page brand reference (icon at all sizes + palette + usage notes). |
| `app-icon-1024.png` | Master 1024×1024 app icon export. |
| `app-icon-512.png` | macOS / web export. |
| `app-icon-180.png` | iPhone @3x. |
| `app-icon-120.png` | iPhone @2x. |
| `app-icon-87.png` | iPhone Settings @3x. |
| `app-icon-60.png` | iPhone Spotlight / Notifications. |
| `wordmark.svg` | Lowercase `naked pantree` lockup. |

## Rules

- All exports come from a single 1024×1024 master. Do **not** pre-round
  corners — iOS applies the rounded mask automatically.
- If you change a color in `colors.json`, update §6 of `DESIGN_GUIDELINES.md`
  in the same commit. They must stay in sync.
