import SwiftUI

/// Brand color tokens. Source of truth is `assets/brand/colors.json` —
/// keep these hex values in sync with that file in the same commit.
/// Usage rules live in `DESIGN_GUIDELINES.md` §6.
///
/// Each primitive resolves through an Asset Catalog colorset under
/// `Assets.xcassets/Brand/`, so iOS's appearance machinery picks the
/// right light / dark / Increase-Contrast variant at runtime — views
/// never branch on `colorScheme`. The light + dark + (where applicable)
/// high-contrast hexes are pinned in `docs/BRAND_PASS_PROPOSAL.md` §4.
extension Color {

    // MARK: Primary

    static let brandForestGreen = Color("BrandForestGreen", bundle: .main)
    static let brandWarmCream = Color("BrandWarmCream", bundle: .main)
    static let brandSoftBrown = Color("BrandSoftBrown", bundle: .main)

    // MARK: Accent

    static let brandCoolBlue = Color("BrandCoolBlue", bundle: .main)
    static let brandMutedOrange = Color("BrandMutedOrange", bundle: .main)
    static let brandSoftRed = Color("BrandSoftRed", bundle: .main)
}

extension ShapeStyle where Self == Color {
    static var brandForestGreen: Color { Color.brandForestGreen }
    static var brandWarmCream: Color { Color.brandWarmCream }
    static var brandSoftBrown: Color { Color.brandSoftBrown }
    static var brandCoolBlue: Color { Color.brandCoolBlue }
    static var brandMutedOrange: Color { Color.brandMutedOrange }
    static var brandSoftRed: Color { Color.brandSoftRed }
}
