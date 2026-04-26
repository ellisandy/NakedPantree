import SwiftUI

/// Brand color tokens. Source of truth is `assets/brand/colors.json` —
/// keep these hex values in sync with that file in the same commit.
/// Usage rules live in `DESIGN_GUIDELINES.md` §6.
extension Color {

    // MARK: Primary

    static let brandForestGreen = Color(brandHex: 0x2F_5D_50)
    static let brandWarmCream   = Color(brandHex: 0xF4_F1_EC)
    static let brandSoftBrown   = Color(brandHex: 0x8B_6F_47)

    // MARK: Accent

    static let brandCoolBlue    = Color(brandHex: 0x4A_90_E2)
    static let brandMutedOrange = Color(brandHex: 0xE9_A8_57)
    static let brandSoftRed     = Color(brandHex: 0xD6_45_45)
}

extension ShapeStyle where Self == Color {
    static var brandForestGreen: Color { Color.brandForestGreen }
    static var brandWarmCream:   Color { Color.brandWarmCream }
    static var brandSoftBrown:   Color { Color.brandSoftBrown }
    static var brandCoolBlue:    Color { Color.brandCoolBlue }
    static var brandMutedOrange: Color { Color.brandMutedOrange }
    static var brandSoftRed:     Color { Color.brandSoftRed }
}

private extension Color {
    init(brandHex hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >>  8) & 0xFF) / 255.0
        let b = Double( hex        & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
