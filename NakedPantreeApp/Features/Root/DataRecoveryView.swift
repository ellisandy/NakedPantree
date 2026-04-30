import SwiftUI

/// User-facing surface shown when `AppLauncher` fails to load the
/// Core Data stack on launch (issue #106). Two-tier remediation:
///
/// 1. **Try Again** — re-runs the build path. Fixes transient
///    failures (disk pressure, brief filesystem hiccup) without
///    destroying anything.
/// 2. **Reset Local Data** — destructive; deletes the SQLite stores
///    so CloudKit re-syncs from cloud. Gated on `accountStatusMonitor.status`
///    being `.available` so a signed-out user can't permanently lose
///    their pantry. Two-tap (button → confirmation alert) per
///    DESIGN_GUIDELINES voice rules and Jack's call in the #106 PR
///    discussion.
///
/// The view is intentionally pure-presentational: callbacks are
/// handed in by `AppLauncher`, no environment dependencies beyond
/// the `AccountStatusMonitor` (read for the gating).
struct DataRecoveryView: View {
    let errorDescription: String
    let accountStatusMonitor: AccountStatusMonitor
    let onTryAgain: () -> Void
    let onResetAndRetry: () -> Void

    @State private var isPresentingResetConfirmation = false
    @State private var isShowingDetails = false

    var body: some View {
        ZStack {
            Color.brandWarmCream
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)

                Text("Couldn't load your pantry")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text(bodyCopy)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                detailsSection

                Spacer()

                actionButtons

                if !canResetSafely {
                    Text("Sign in to iCloud in Settings to make Reset safe to use.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .accessibilityIdentifier("recovery.icloudWarning")
                }
            }
            .padding(.vertical, 32)
        }
        .accessibilityIdentifier("view.recovery")
        .alert(
            "Reset Local Data?",
            isPresented: $isPresentingResetConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                onResetAndRetry()
            }
            .accessibilityIdentifier("recovery.confirmReset")
        } message: {
            // Copy approved by Jack on #106. Avoids "loading" / "issue"
            // jargon — describes consequences in user-domain terms.
            Text(
                "This deletes your pantry on this device. If iCloud is "
                    + "available, it will re-sync. Otherwise, this can't be undone."
            )
        }
    }

    /// `.available` is the only `CKAccountStatus` value where we can
    /// reasonably expect a re-sync to recover the user's data. Every
    /// other state — signed-out, restricted, account temporarily
    /// unavailable — risks permanent loss, so we hide the destructive
    /// button entirely and explain via the inline note.
    private var canResetSafely: Bool {
        accountStatusMonitor.status == .available
    }

    /// Body copy adapts to whether we'll show the destructive button.
    /// When iCloud isn't available, "Reset" isn't on the table — so
    /// the body offers the user just the retry framing.
    private var bodyCopy: String {
        if canResetSafely {
            return
                "We couldn't open the local database. This is usually "
                + "temporary — try again, or reset your local data and "
                + "let iCloud sync it back."
        } else {
            return
                "We couldn't open the local database. This is usually "
                + "temporary — try again to retry the load."
        }
    }

    @ViewBuilder
    private var detailsSection: some View {
        DisclosureGroup(
            isExpanded: $isShowingDetails,
            content: {
                Text(errorDescription)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                    .accessibilityIdentifier("recovery.errorDescription")
            },
            label: {
                Text("Show technical details")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        )
        .padding(.horizontal, 32)
    }

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: onTryAgain) {
                Text("Try Again")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.brandForestGreen)
            .accessibilityIdentifier("recovery.tryAgain")

            if canResetSafely {
                Button(role: .destructive) {
                    isPresentingResetConfirmation = true
                } label: {
                    Text("Reset Local Data…")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("recovery.resetLocalData")
            }
        }
        .padding(.horizontal, 32)
    }
}

#Preview("iCloud available") {
    DataRecoveryView(
        errorDescription:
            "The persistent store could not be opened. (NSCocoaErrorDomain Code=134060)",
        accountStatusMonitor: AccountStatusMonitor(),
        onTryAgain: {},
        onResetAndRetry: {}
    )
}
