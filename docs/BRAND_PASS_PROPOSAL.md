# Brand Pass Proposal — Phase 10.2 research

> Companion to `DESIGN_GUIDELINES.md` §6 (Color). This is a **proposal** —
> the deliverable for issue #52. Implementation lands in Phase 10.5
> follow-ups; the prioritized list at the bottom of this doc seeds those
> issues.

---

## 1. What we have today

- **Source of truth:** `assets/brand/colors.json` defines the six brand
  hexes with role + usage notes. `DESIGN_GUIDELINES.md` §6 mirrors it.
- **Swift API:** `NakedPantreeApp/DesignSystem/Color+Brand.swift` exposes
  `Color.brandForestGreen`, `Color.brandWarmCream`, `Color.brandSoftBrown`,
  `Color.brandCoolBlue`, `Color.brandMutedOrange`, `Color.brandSoftRed`
  as flat sRGB hex constants, plus `ShapeStyle` mirrors so they work
  with `.foregroundStyle(...)` / `.tint(...)`.
- **Asset Catalog:** `AccentColor.colorset` is wired to Forest Green
  (`#2F5D50`). No other branded colorsets exist.
- **Current usage:** only `LaunchView` and `AccountStatusBanner` consume
  brand tokens. Everywhere else (`RootView`, `SidebarView`, `ItemsView`,
  `ItemDetailView`, `ItemFormView`, `SettingsView`, smart-list views)
  uses default SwiftUI styling.

So: the **primitive** layer exists, dark mode does not, no surface other
than launch reflects the brand, and there is no semantic / role-named
layer above the primitives.

---

## 2. Final color tokens + naming (recommended)

### Two-tier scheme

The primitive layer is what `Color+Brand.swift` already exposes. Keep it.
Add a **semantic role layer** on top — that is what views will consume.
The two-tier shape exists to enforce the §6 usage rules through naming:
"Cool Blue is reserved for cold storage" becomes hard to violate when the
type-checked name views see is `Color.coldStorage`, not `Color.brandCoolBlue`.

| Tier | Purpose | Examples |
| --- | --- | --- |
| **Primitive** | Raw brand hexes. Mirrors `colors.json`. Used only by the semantic layer and snapshot/preview tooling. | `brandForestGreen`, `brandWarmCream`, `brandSoftBrown`, `brandCoolBlue`, `brandMutedOrange`, `brandSoftRed` |
| **Semantic / role** | What views call. Resolves to a primitive (or an Asset-Catalog colorset that interpolates between light/dark). | see table below |

### Proposed semantic tokens

| Semantic name | Light resolves to | Role |
| --- | --- | --- |
| `surface` | `brandWarmCream` `#F4F1EC` | App canvas background |
| `surfaceElevated` | `#FFFFFF` | Sheets, modals over `surface` |
| `primary` | `brandForestGreen` `#2F5D50` | Primary brand, hero, key CTAs |
| `primaryText` | `brandForestGreen` `#2F5D50` | Branded headings, wordmark |
| `onPrimary` | `brandWarmCream` `#F4F1EC` | Text/iconography on `primary` fills |
| `secondary` | `brandSoftBrown` `#8B6F47` | Secondary accents, dividers |
| `pantryCategory` | `brandSoftBrown` `#8B6F47` | Pantry / dry-goods icon tint |
| `coldStorage` | `brandCoolBlue` `#4A90E2` | Fridge / freezer icon tint |
| `expiringSoon` | `#9A6622` (deep amber, see §6) | Expiring-soon badge text/icon on cream |
| `expiringSoonFill` | `#FCEAD0` (cream-orange tint) | Expiring-soon badge background |
| `expired` | `#A93030` (deep red, see §6) | Expired/destructive text/icon on cream |
| `expiredFill` | `#F8E0E0` (cream-red tint) | Expired badge background |
| `divider` | `brandSoftBrown` at 20 % opacity | Hairlines |

The `expiringSoon` / `expired` text tokens are **not** the raw brand
hexes — `brandMutedOrange` and `brandSoftRed` fail WCAG AA against
`brandWarmCream` at body sizes (1.83 : 1 and 3.89 : 1). The raw hexes
remain correct as **status fills / chip backgrounds**, paired with a
deeper text color. See §6 for the full contrast table.

### File shape (no Swift edits in this PR — for Phase 10.5)

```
NakedPantreeApp/DesignSystem/
    Color+Brand.swift          # existing — primitives stay
    Color+Semantic.swift       # NEW — role tokens, light resolution
    Theme.swift                # NEW — see §3 environment hook (optional)
NakedPantreeApp/Resources/Assets.xcassets/Brand/
    BrandForestGreen.colorset  # NEW — light + dark + AnyAppearance HC
    BrandWarmCream.colorset
    BrandSoftBrown.colorset
    BrandCoolBlue.colorset
    BrandMutedOrange.colorset
    BrandSoftRed.colorset
```

Primitives migrate from inline `Color(brandHex:)` to
`Color("BrandForestGreen", bundle: .main)` so the system resolves
light / dark / high-contrast at runtime. The `Color.brandForestGreen`
**call sites stay identical** — only the body of the static var changes.

---

## 3. SwiftUI integration approach

**Recommended: Asset Catalog colorsets + the existing `Color` extension,
no environment value.**

The `Color+Brand.swift` API (`Color.brandForestGreen`, etc.) already
exists and is already partially adopted. We swap the *implementation* of
those vars from `Color(brandHex:)` to `Color("BrandForestGreen", bundle:
…)` so iOS's own appearance machinery resolves the right variant for
light / dark / high-contrast / Increase Contrast. We add a thin
**`Color+Semantic.swift`** on top whose vars (`Color.surface`,
`Color.expiringSoon`, …) just return primitives. Two layers, no runtime
plumbing, no preview wiring change, and the existing call sites in
`LaunchView` / `AccountStatusBanner` keep working as-is.

### Rejected alternatives (one line each)

- **Pure `Color` extension with hex literals (status quo).** Rejected —
  no path to dark mode without per-call-site mode checks; brittle.
- **`@Environment(\.theme) var theme: Theme` value.** Rejected — adds a
  preview/test injection burden across every view for ~zero benefit;
  iOS already has the appearance environment, we just need to feed it
  through Asset Catalog colorsets.
- **Third-party design-token library (Tokens, Spectrum, etc.).**
  Rejected — six colors and a handful of semantic roles do not justify
  a dependency. Asset Catalog plus a Swift file is enough.
- **Code-gen tokens from `colors.json` at build time.** Rejected for
  Phase 10.5 — the file has six entries and changes once a quarter;
  manual sync (already enforced by §6's "change both in the same
  commit" rule) is cheaper than a build script. Revisit if the palette
  grows past ~20 tokens.

---

## 4. Light / dark mode + Dynamic Type strategy

### One token, two appearances

Each primitive is **one** semantic name backed by an Asset Catalog
colorset with a Light + Dark + (optional) High-Contrast variant. Views
never branch on `colorScheme`. The proposed dark-mode hexes:

| Token | Light | Dark | Notes |
| --- | --- | --- | --- |
| `brandForestGreen` | `#2F5D50` | `#4A8B7A` | Lifted ~25 L for legibility on dark canvas. |
| `brandWarmCream` | `#F4F1EC` | `#1C1B17` | Near-black canvas, warm-shifted to keep brand temperature. |
| `brandSoftBrown` | `#8B6F47` | `#B8966A` | Lifted; passes 6.24 : 1 on the dark canvas. |
| `brandCoolBlue` | `#4A90E2` | `#7AB3F0` | Lifted; passes 7.82 : 1 on the dark canvas. |
| `brandMutedOrange` | `#E9A857` | `#F0BC72` | Slightly lighter; passes 9.96 : 1. |
| `brandSoftRed` | `#D64545` | `#E97070` | Lifted to pass 5.76 : 1 on dark canvas. |
| `surfaceElevated` | `#FFFFFF` | `#2A2823` | Slightly raised vs `brandWarmCream` dark. |

In dark mode the **surface inverts** (cream → near-black) and the brand
green **lifts** so the wordmark and primary CTAs read on the new canvas.
The hero is still recognizably forest-green; we are not switching brands
between modes.

### Dynamic Type

- Type styles (`.body`, `.headline`, …) are inherited everywhere — no
  fixed point sizes in branded components. Status badges use `.caption`
  + `.medium` weight + tabular numerals, which scales correctly.
- Branded chips / badges must use the **icon + text** pattern that §6
  already mandates, so Dynamic Type users at AX5 still get state
  information when the chip background tint becomes the smallest visual
  signal.
- The wordmark in `LaunchView` is a `.system(.largeTitle, design:
  .rounded)` — already Dynamic-Type-correct. Don't introduce hard-sized
  brand text anywhere else.

### Increase Contrast / high-contrast appearance

Asset Catalog colorsets accept a "High Contrast" variant per appearance.
We will ship a high-contrast variant for the three colors that sit
closest to AA threshold:

- `brandSoftBrown` light HC: `#6E5234` (6.4 : 1 on cream — fixes the
  current 4.18 : 1 fail at body sizes).
- `brandMutedOrange` light HC: deepen toward `#9A6622` for *text* uses
  only; chip-fill HC stays bright.
- `brandSoftRed` light HC: `#A93030` for text uses; chip-fill HC stays
  bright.

For the dark mode HC variants, lift each by another ~10 L.

---

## 5. Highest-leverage surfaces (where to apply branding first)

Ordered by **visibility × stability** — surfaces a user sees daily, that
won't rev again soon. This list maps directly to the follow-up issues
in §10.

1. **App canvas (`brandWarmCream` background).** The single highest-
   leverage change. `RootView`, all `List` backgrounds, smart-list
   views, sidebar.
2. **Expiry badges** (`ExpiringSoonView`, `ItemsView` row, `ItemDetail`
   expiry section). State color is the most utility-aligned brand
   moment — it carries information *and* personality at once.
3. **Primary CTA buttons** (`ItemFormView` Save/Add, `LocationFormView`
   Save). One filled `brandPrimary` button style replaces the default
   blue.
4. **Empty states** (`ItemsView` empty location, `SidebarView` empty
   Locations, smart-list empties). High-personality moments per §9 —
   warm cream illustration tone fits the playful-but-not-childish bar.
5. **Sidebar navigation chrome.** No tab bar in this app — sidebar is
   the equivalent. Branded tint, `coldStorage` blue on fridge/freezer
   icons, `pantryCategory` brown on pantry/dry-goods.
6. **`ItemDetailView` header.** Photo-less items currently look like a
   plain Form. A branded section header strip (with location-kind
   accent) makes the screen feel intentional.
7. **`AccountStatusBanner`.** Already on `brandWarmCream` — finish the
   pass with branded text + iconography per status.

---

## 6. Accessibility — pairings with computed contrast ratios

WCAG thresholds: AA-body ≥ 4.5 : 1, AA-large (≥ 18 pt or 14 pt bold) ≥
3.0 : 1, AAA-body ≥ 7.0 : 1.

### Light mode

| Foreground | Background | Ratio | AA body | AA large | AAA |
| --- | --- | --- | --- | --- | --- |
| `brandForestGreen` `#2F5D50` | `brandWarmCream` `#F4F1EC` | **6.65** | PASS | PASS | fail |
| `brandWarmCream` | `brandForestGreen` (filled CTA) | **6.65** | PASS | PASS | fail |
| white | `brandForestGreen` | **7.49** | PASS | PASS | PASS |
| white | `brandSoftBrown` | **4.71** | PASS | PASS | fail |
| `brandSoftBrown` | `brandWarmCream` | 4.18 | **fail** | PASS | fail |
| `brandSoftBrown` HC `#6E5234` | `brandWarmCream` | **6.38** | PASS | PASS | fail |
| `brandCoolBlue` | `brandWarmCream` | 2.92 | **fail** | fail | fail |
| `brandCoolBlue` text `#1F66B5` | `brandWarmCream` | **5.14** | PASS | PASS | fail |
| `brandMutedOrange` | `brandWarmCream` | 1.83 | **fail** | fail | fail |
| `expiringSoon` `#9A6622` | `expiringSoonFill` `#FCEAD0` | **6.15** | PASS | PASS | fail |
| black | `brandMutedOrange` (chip fill) | **10.20** | PASS | PASS | PASS |
| `brandSoftRed` | `brandWarmCream` | 3.89 | **fail** | PASS | fail |
| `expired` `#A93030` | `expiredFill` `#F8E0E0` | **5.31** | PASS | PASS | fail |
| white | `brandSoftRed` (filled destructive) | 4.38 | **fail** | PASS | fail |
| white | `brandSoftRed` HC `#A93030` | **6.66** | PASS | PASS | fail |

### Dark mode

| Foreground | Background | Ratio | AA body | AA large | AAA |
| --- | --- | --- | --- | --- | --- |
| `brandWarmCream` light `#F4F1EC` | `brandWarmCream` dark `#1C1B17` | **15.30** | PASS | PASS | PASS |
| `brandForestGreen` dark `#4A8B7A` | dark canvas | 4.32 | **fail** | PASS | fail |
| `brandSoftBrown` dark `#B8966A` | dark canvas | **6.24** | PASS | PASS | fail |
| `brandCoolBlue` dark `#7AB3F0` | dark canvas | **7.82** | PASS | PASS | PASS |
| `brandMutedOrange` dark `#F0BC72` | dark canvas | **9.96** | PASS | PASS | PASS |
| `brandSoftRed` dark `#E97070` | dark canvas | **5.76** | PASS | PASS | fail |

### Hard rules baked into the tokens

- **`brandMutedOrange` and `brandSoftRed` are fill-only at body sizes in
  light mode.** Text must use the deeper `expiringSoon` / `expired`
  variants. The semantic-token names enforce this — `Color.expiringSoon`
  resolves to the deep amber, `Color.expiringSoonFill` to the bright
  brand orange. Engineers don't pick.
- **`brandCoolBlue` light is a fill / large-text color only.** A semantic
  `Color.coldStorageText` (`#1F66B5`) is required for body-size labels.
- **`brandForestGreen` dark fails AA at body size on the dark canvas.**
  Use as a fill (CTA background) or large-text accent only in dark mode;
  body text on dark uses `brandWarmCream` light or `surfaceElevated` dark.
  This is acceptable because forest-green is primarily a *surface* color
  in dark mode (filled buttons, navigation tint), not body text.
- **Color is never the only state signal.** Already in §6 — restate
  here because the badge tokens make this easy to forget.

### Color-blind safety

The three status colors (orange, red, brown) cluster in the long-wave
range. Deuteranopia / protanopia simulations collapse orange and red
toward similar warm-yellow. Mitigations:

1. Status icons (`clock.badge.exclamationmark`, `xmark.octagon.fill`)
   are **load-bearing** — never strip them in compact layouts.
2. Expired vs expiring-soon must differ in **shape / glyph**, not just
   tint. The §6 rule "icon + label" is the contract.
3. Pantry-brown vs expired-red: pantry use is icon-only and confined to
   the sidebar / category context. Status reds appear on a *cream*
   chip background, never on a pantry-brown chip. The semantic tokens
   keep them apart.

---

## 7. Emoji / illustration consistency

§3 / §9 already pin the voice as "playful, not childish." The visual
analogue:

- **Emoji are for copy, not chrome.** `DESIGN_GUIDELINES.md` §1 uses
  emoji as bullet pegs in a copy block — that's fine. Emoji as iconography
  in the running UI is **off**: SF Symbols carry weight/scale/Dynamic-Type
  behavior, emoji do not.
- **One illustrated mark, used sparingly.** The cabinet from
  `assets/brand/icon.png` is the only first-party illustration. We
  should commission a small illustrated empty-state set (Phase 10.6+,
  not in this proposal) using the same fill-style + brand palette: an
  open shelf for "empty pantry," a tag-and-string for "no items
  matching." Until that ships, empty states use SF Symbols rendered in
  `Color.secondary` + a single playful copy line per §9.
- **Personality lives in copy + state colors.** Illustrations and
  large emoji clusters are not the brand voice for this app — short,
  dry, slightly witty strings are.
- **Where emoji *do* appear** (currently §1's bullet list, future
  marketing copy), they ride alongside text — never as the only state
  signal.

---

## 8. Shape, motion, and other surfaces (briefly out of scope)

Animation/motion language is explicitly out of scope per the issue.
Corner radius, elevation, and density are *not* called out as research
deliverables, but the brand-pass implementation will inherit defaults:

- Corner radius: SF default (`RoundedRectangle` 12 pt for chips,
  default `Form` insets elsewhere).
- Elevation: rely on iOS chrome — sheets, materials, blurred bars.
  No custom shadows.
- Density: `.regular` everywhere; no compact mode.

If any of these become a brand lever, file a separate research issue.

---

## 9. Constraints and non-goals (recap)

In scope for this proposal: tokens, naming, light/dark, accessibility,
rollout order.

Out of scope: icon redesign, marketing assets, animation/motion,
typography overhaul (Typography is settled in §5), wholesale
restyling. Each Phase 10.5 sub-issue must touch *one* surface.

---

## 10. Prioritized follow-up implementation issues

Each item is one Phase 10.5 sub-issue. Title is imperative, paragraph
is the scope. The list is ordered by **dependency × leverage** — the
earlier items unblock later ones.

1. **Add Asset Catalog colorsets for the six brand primitives with
   light, dark, and high-contrast variants.** Create
   `NakedPantreeApp/Resources/Assets.xcassets/Brand/<Name>.colorset`
   for Forest Green, Warm Cream, Soft Brown, Cool Blue, Muted Orange,
   Soft Red. Each colorset gets light + dark + AnyAppearance High
   Contrast variants matching §4. Update `Color+Brand.swift` so each
   static var resolves via `Color("BrandForestGreen", bundle: …)`
   instead of `Color(brandHex:)`. Call sites stay byte-identical;
   appearance handling becomes free. Also reconcile the existing
   `AccentColor.colorset` (currently a flat `#2F5D50`): either give it
   the same light/dark/high-contrast variants as `BrandForestGreen`,
   or delete it and point the project-level accent reference at
   `BrandForestGreen` directly. Without this, the system `.tint` stays
   on the light-mode green in dark mode while brand surfaces lift —
   subtle but visible drift. Foundation for everything else.

2. **Introduce semantic role tokens (`Color+Semantic.swift`).** Add
   `Color.surface`, `Color.surfaceElevated`, `Color.primary`,
   `Color.onPrimary`, `Color.coldStorage`, `Color.coldStorageText`,
   `Color.pantryCategory`, `Color.expiringSoon`, `Color.expiringSoonFill`,
   `Color.expired`, `Color.expiredFill`, `Color.divider`, plus the
   `ShapeStyle` mirrors. Each var resolves to a primitive (or a
   primitive at a tuned opacity). No view changes — this is the seam
   the next four items consume. Add a doc comment on each token
   referencing the §6 usage rule it enforces.

3. **Apply `Color.surface` as the app canvas.** `RootView`, every
   `List` background (`SidebarView`, `ItemsView`, `AllItemsView`,
   `ExpiringSoonView`, `RecentlyAddedView`, `SearchResultsView`),
   `ItemDetailView`'s `Form`. Use
   `.scrollContentBackground(.hidden).background(Color.surface)` on
   `Form` / `List`. Verify dark mode works without per-view branches.

4. **Add expiry / quantity badge components and wire them into `ItemRow`,
   `ExpiringSoonView`, and `ItemDetailView` expiry section.** Build
   `ExpiryBadge(expiresAt:)` that picks `expiringSoon`/`expired`/no-
   badge based on the same threshold logic the smart list already uses,
   pairs the chip with `clock.badge.exclamationmark` /
   `xmark.octagon.fill`, and uses `expiringSoonFill` / `expiredFill` for
   the chip background with the deep-text variants for the label.
   Also build `QuantityBadge(quantity:unit:)` using
   `Color.surfaceElevated` + `Color.primary` text.

5. **Add `Color.primary` filled button style and apply to primary
   CTAs.** Implement `ButtonStyle.brandPrimary` (filled rounded
   rectangle, `Color.primary` background, `Color.onPrimary` text,
   tactile press response). Apply to the Save/Add buttons in
   `ItemFormView` and `LocationFormView`. Don't touch toolbar buttons
   — those remain native chrome.

6. **Brand the empty states.** Wrap `ContentUnavailableView` usage in
   a `BrandedEmptyState(systemImage:title:message:)` helper that
   tints the symbol with `Color.secondary` (currently default), uses
   `surface` background, and renders the message with the
   `playful-but-utility-first` copy already in §9 (Empty pantry: "Your
   pantry is empty. This feels like a bigger problem.", etc.). Apply
   to `ItemsView` empty location, `ExpiringSoonView`, `RecentlyAddedView`,
   `SearchResultsView`, the empty Locations row in `SidebarView`, the
   `ItemDetailView` "Pick an item" placeholder.

7. **Tint sidebar location icons by kind using `coldStorage` /
   `pantryCategory` / `secondary`.** `LocationKind.systemImage`
   already maps kinds to SF Symbols — extend with a tint mapping
   (`fridge` / `freezer` → `coldStorage`, `pantry` / `dryGoods` →
   `pantryCategory`, `other` / `unknown` → `secondary`). Wordmark
   the navigation title area in `SidebarView` using the same weighted
   `naked pantree` lockup as `LaunchView`.

8. **Brand the `ItemDetailView` header strip.** When an item has no
   primary photo, render a thin colored band above the form keyed to
   the item's location kind (cold storage → `coldStorage`, pantry →
   `pantryCategory`). When a primary photo exists, layer the band as a
   subtle shadow under the photo. Pure decoration — must remain
   ignorable for a11y (`accessibilityHidden`).

9. **Polish the `AccountStatusBanner`.** It already sits on
   `brandWarmCream` — finish the pass with `Color.expiringSoon` for
   degraded-iCloud states (paired with an icon), `Color.expired` for
   sign-out, and `Color.primary` for the "available" success state
   (only shown briefly on transition). Ensure the banner is never the
   sole signal for any state — it is paired with the in-feature
   alerting.

10. **Dark-mode + Increase-Contrast QA pass.** Run the snapshot suite
    in both modes plus the iOS Increase Contrast accessibility
    setting. Capture screenshots for each surface in each mode.
    File one ticket per regression discovered. Includes the
    `LaunchView` (already branded) — which is allowed to skip dark
    mode if the cream background reads better as a fixed launch
    surface; that decision lives in this issue's PR.

---

## 11. References

- `DESIGN_GUIDELINES.md` §3 (voice), §6 (color), §9 (personality), §10
  (writing checklist), §11 (restraint).
- `assets/brand/colors.json` — primitive source of truth.
- `assets/brand/brand-guide.png` — single-page visual reference.
- `NakedPantreeApp/DesignSystem/Color+Brand.swift` — current Swift API.
- WCAG 2.1 SC 1.4.3 (contrast minimum) and 1.4.6 (enhanced).
