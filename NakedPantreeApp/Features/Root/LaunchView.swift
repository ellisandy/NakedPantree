import SwiftUI

/// In-app launch surface shown while `RootView` waits on
/// `bootstrapComplete`. Phase 8.2's bootstrap-defer pushed the worst-case
/// wait to ~8s on a fresh-install + slow-network cold-start, long enough
/// that a bare `Color.brandWarmCream` reads as a hung app. This view
/// gives the user something to look at: the brand wordmark, a thin
/// native progress indicator, and after a few seconds a calm
/// "Syncing with iCloud…" line for the slow-bootstrap case.
///
/// Voice rules (`DESIGN_GUIDELINES.md` §3 / §9): bootstrap waits aren't
/// the place for personality — sync messaging stays plain. The word
/// "Loading" is intentionally avoided.
///
/// The view is pure (no environment dependencies) so `#Preview` and
/// future snapshot tests can render it without injecting repositories.
struct LaunchView: View {
    /// Seconds until the secondary "Syncing with iCloud…" line appears.
    /// Public so tests / previews can override it; production callers
    /// rely on the default.
    let slowThreshold: Duration

    @State private var showSlowMessage = false

    init(slowThreshold: Duration = .seconds(3)) {
        self.slowThreshold = slowThreshold
    }

    var body: some View {
        ZStack {
            Color.brandWarmCream
                .ignoresSafeArea()

            VStack(spacing: 24) {
                wordmark
                    .accessibilityHidden(true)

                ProgressView()
                    .tint(.brandForestGreen)
                    .controlSize(.regular)

                // Reserve the slow-message slot up front so the
                // wordmark + spinner don't shift vertically when it
                // appears — opacity-only fade keeps the layout stable.
                Text("Syncing with iCloud…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .opacity(showSlowMessage ? 1 : 0)
                    .animation(.easeIn(duration: 0.2), value: showSlowMessage)
                    .accessibilityHidden(!showSlowMessage)
            }
            .padding(.horizontal, 32)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("view.launch")
        .task {
            // A short, cancel-safe wait. If bootstrap finishes first,
            // the parent swaps this view out and the task is cancelled
            // before the flag flips — no flash of the slow message on
            // a fast cold-start.
            try? await Task.sleep(for: slowThreshold)
            showSlowMessage = true
        }
    }

    /// `naked pantree` weighted lockup per `DESIGN_GUIDELINES.md` §5:
    /// `Naked` light, `Pantree` bold. A weighted mark reads as the
    /// brand; a plain lowercase label would read as filler text.
    private var wordmark: some View {
        HStack(spacing: 6) {
            Text("naked")
                .fontWeight(.light)
            Text("pantree")
                .fontWeight(.bold)
        }
        .font(.system(.largeTitle, design: .rounded))
        .foregroundStyle(.brandForestGreen)
        .kerning(-0.5)
    }

    private var accessibilityLabel: String {
        showSlowMessage
            ? "Naked Pantree is starting up. Syncing with iCloud."
            : "Naked Pantree is starting up."
    }
}

#Preview("Launch — fresh") {
    LaunchView()
}

#Preview("Launch — slow state") {
    // Threshold of zero flips the secondary message immediately so
    // reviewers can eyeball the slow-bootstrap state without waiting.
    LaunchView(slowThreshold: .zero)
}
