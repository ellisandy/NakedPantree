import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Unobtrusive banner that surfaces iCloud-account problems. Stays
/// hidden when `status == .available`. Copy follows the
/// `DESIGN_GUIDELINES.md` §9 rule that sync failures are off-limits for
/// personality — plain, calm, useful.
struct AccountStatusBanner: View {
    let status: AccountStatus

    var body: some View {
        if let message = status.message {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: "exclamationmark.icloud")
                    .imageScale(.medium)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 12)
                if status == .noAccount {
                    Button("Settings") {
                        openSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.brandWarmCream)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(.separator)
                    .frame(height: 0.5)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("banner.accountStatus")
            .accessibilityLabel(message)
        }
    }

    private func openSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }
}

extension AccountStatus {
    /// Body copy for the banner. `nil` when `.available` — caller
    /// decides not to render. Keep these short; voice rules apply.
    var message: String? {
        switch self {
        case .available:
            nil
        case .noAccount:
            "Sign in to iCloud to keep your pantry in sync across devices."
        case .restricted:
            "iCloud is restricted on this device. Changes won't sync."
        case .couldNotDetermine:
            "iCloud is unreachable. Changes will sync when it's back."
        case .temporarilyUnavailable:
            "iCloud is briefly unavailable. Trying again."
        }
    }
}

#Preview("No account") {
    AccountStatusBanner(status: .noAccount)
}

#Preview("Restricted") {
    AccountStatusBanner(status: .restricted)
}

#Preview("Couldn't determine") {
    AccountStatusBanner(status: .couldNotDetermine)
}

#Preview("Available (hidden)") {
    AccountStatusBanner(status: .available)
}
