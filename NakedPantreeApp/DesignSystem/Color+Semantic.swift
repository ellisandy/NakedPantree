import SwiftUI

/// Semantic / role-named color tokens. Views consume this layer; the
/// primitives in `Color+Brand.swift` are reserved for the semantic layer
/// itself and snapshot/preview tooling. The two-tier shape exists to
/// enforce the `DESIGN_GUIDELINES.md` §6 usage rules through naming —
/// "Cool Blue is reserved for cold storage" becomes hard to violate when
/// the type-checked name views see is `Color.coldStorage`, not
/// `Color.brandCoolBlue`.
///
/// Tokens that map 1:1 to a primitive delegate to it. Tokens with their
/// own light/dark hexes (`surfaceElevated`, `expiringSoon`, …) resolve
/// through Asset Catalog colorsets under `Brand/Semantic/`.
///
/// Light hexes match `docs/BRAND_PASS_PROPOSAL.md` §2; the proposal's
/// computed contrast ratios are in §6. Dark variants for the status
/// text/fill tokens (`expiringSoon`, `expiringSoonFill`, `expired`,
/// `expiredFill`, `coldStorageText`) are deferred to the 10.5d QA pass
/// per proposal §10 item 10 — these colorsets ship light-only so the
/// "needs dark-mode treatment" debt surfaces honestly rather than as a
/// guessed dark hex. Tokens that delegate to a primitive inherit the
/// primitive's dark resolution for free.
///
/// Naming deviation from proposal §2: `primary` and `secondary` are
/// renamed to `brandPrimary` and `brandSecondary` because `Color.primary`
/// and `Color.secondary` are already declared by SwiftUI — using the
/// proposal names verbatim would be a redeclaration error, not silent
/// shadowing. All other token names match §2.
extension Color {

    // MARK: Surfaces

    /// App canvas background. Resolves to `brandWarmCream` so dark mode
    /// inverts cream → near-black through the primitive's colorset.
    /// `DESIGN_GUIDELINES.md` §6: "Warm Cream is the canvas."
    static let surface = Color.brandWarmCream

    /// Elevated surfaces — sheets, modals, cards layered over `surface`.
    /// `DESIGN_GUIDELINES.md` §6: "Pure white is reserved for elevated
    /// surfaces (modals over cream)."
    static let surfaceElevated = Color("SurfaceElevated", bundle: .main)

    // MARK: Brand

    /// Primary brand fill — hero color, key CTAs, filled buttons.
    /// `DESIGN_GUIDELINES.md` §6: "Forest Green is the hero. Don't
    /// substitute another green." Renamed from proposal `primary` to
    /// avoid colliding with SwiftUI's `Color.primary`.
    static let brandPrimary = Color.brandForestGreen

    /// Branded text — wordmark, branded headings on `surface`. Same hex
    /// as `brandPrimary` but role-separated: text uses are limited to
    /// large-type contexts where `brandForestGreen` clears AA on cream.
    /// `DESIGN_GUIDELINES.md` §6 + proposal §6 contrast table.
    static let primaryText = Color.brandForestGreen

    /// Foreground color for content rendered *on* a `brandPrimary` fill.
    /// Resolves to `brandWarmCream` so dark mode lifts together with
    /// the fill. Proposal §6: cream-on-forest-green = 6.65 : 1, AA pass.
    static let onPrimary = Color.brandWarmCream

    /// Secondary accents — section dividers, subdued chrome. Renamed
    /// from proposal `secondary` to avoid colliding with SwiftUI's
    /// `Color.secondary`. `DESIGN_GUIDELINES.md` §6: "Soft Brown — secondary
    /// accents, dividers, pantry/dry-goods category."
    static let brandSecondary = Color.brandSoftBrown

    // MARK: Categories

    /// Pantry / dry-goods category tint. Same hex as `brandSecondary`
    /// but role-separated so a category-icon migration can re-tint
    /// without disturbing dividers. `DESIGN_GUIDELINES.md` §6.
    static let pantryCategory = Color.brandSoftBrown

    /// Cold storage (fridge / freezer) tint — for *fills* and *icons*.
    /// `DESIGN_GUIDELINES.md` §6: "Cool Blue is reserved for cold storage
    /// (fridge, freezer). Don't use it for generic links or buttons."
    /// Body-size text on cream must use `coldStorageText` instead —
    /// proposal §6 marks `brandCoolBlue` as fill / large-text only at
    /// 2.92 : 1 against cream.
    static let coldStorage = Color.brandCoolBlue

    /// Cold storage *text* color for body-size labels on cream. The
    /// raw `brandCoolBlue` fails AA at 2.92 : 1; this deeper variant
    /// (`#1F66B5`) clears 5.14 : 1. Hard rule from proposal §6 —
    /// engineers don't pick.
    static let coldStorageText = Color("ColdStorageText", bundle: .main)

    // MARK: Status — expiring soon

    /// Expiring-soon badge text/icon color on `expiringSoonFill`.
    /// Proposal §6 hard rule: `brandMutedOrange` at body sizes on cream
    /// fails AA (1.83 : 1). `expiringSoon` resolves to a deeper amber
    /// (`#9A6622`) that clears 6.15 : 1 against `expiringSoonFill`.
    /// `DESIGN_GUIDELINES.md` §6: status colors never decorative; pair
    /// with an icon (`clock.badge.exclamationmark`).
    static let expiringSoon = Color("ExpiringSoon", bundle: .main)

    /// Expiring-soon badge fill — cream-orange tint that pairs with the
    /// deeper `expiringSoon` text. Color is never the only state signal
    /// (proposal §6); the badge always carries an icon + label.
    static let expiringSoonFill = Color("ExpiringSoonFill", bundle: .main)

    // MARK: Status — expired

    /// Expired / destructive text/icon color on `expiredFill`.
    /// Proposal §6 hard rule: `brandSoftRed` at body sizes on cream
    /// fails AA (3.89 : 1). `expired` resolves to a deeper red
    /// (`#A93030`) that clears 5.31 : 1 against `expiredFill`.
    /// `DESIGN_GUIDELINES.md` §6: pair with an icon
    /// (`xmark.octagon.fill`); never communicate state with color alone.
    static let expired = Color("Expired", bundle: .main)

    /// Expired badge fill — cream-red tint paired with the deeper
    /// `expired` text. Color is never the only state signal.
    static let expiredFill = Color("ExpiredFill", bundle: .main)

    // MARK: Chrome

    /// Hairline divider — `brandSoftBrown` at 20 % opacity. Proposal
    /// §2 specifies the opacity; resolution stays through the primitive
    /// so dark mode inherits the lifted brown automatically.
    static let divider = Color.brandSoftBrown.opacity(0.2)
}

extension ShapeStyle where Self == Color {
    static var surface: Color { Color.surface }
    static var surfaceElevated: Color { Color.surfaceElevated }
    static var brandPrimary: Color { Color.brandPrimary }
    static var primaryText: Color { Color.primaryText }
    static var onPrimary: Color { Color.onPrimary }
    static var brandSecondary: Color { Color.brandSecondary }
    static var pantryCategory: Color { Color.pantryCategory }
    static var coldStorage: Color { Color.coldStorage }
    static var coldStorageText: Color { Color.coldStorageText }
    static var expiringSoon: Color { Color.expiringSoon }
    static var expiringSoonFill: Color { Color.expiringSoonFill }
    static var expired: Color { Color.expired }
    static var expiredFill: Color { Color.expiredFill }
    static var divider: Color { Color.divider }
}
