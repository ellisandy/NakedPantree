import Foundation
import SwiftUI

/// Issue #156: shared "Expired" badge for item rows. Originally lived
/// privately inside `ExpiringSoonRow`, where it was the only list to
/// surface the past-date signal. Every other list (per-location,
/// All Items, Recently Added, Search Results) showed the date in
/// muted secondary text — indistinguishable from a future expiry, so
/// users could miss two-week-stale items unless they happened to
/// open the Expiring Soon view.
///
/// Centralising the badge here means the visual treatment, the
/// `< Date()` comparison, and the accessibility-rule wording (icon
/// + text per `DESIGN_GUIDELINES.md` §6 — never color alone) live in
/// exactly one place. Future tweaks (e.g. "stale for >7 days" red vs
/// yellow gradient) ship to every list automatically.
///
/// Renders nothing when `expiresAt` is `nil` or in the future, so
/// callers can drop it into any HStack unconditionally without
/// needing their own `if isExpired` guard.
struct ItemExpiryBadge: View {
    let expiresAt: Date?

    var body: some View {
        if isExpired {
            Label("Expired", systemImage: "exclamationmark.triangle.fill")
                .labelStyle(.titleAndIcon)
                .font(.caption.bold())
                .foregroundStyle(.red)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.12), in: Capsule())
                .accessibilityIdentifier("item.expiredBadge")
        }
    }

    private var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt < Date()
    }
}
