import NakedPantreeDomain
import SwiftUI
import os

/// User-level Settings screen. Phase 9.3 introduced the reminder-time
/// picker; Phase 10.1 (issue #60) folds household management in next to
/// it, retiring the sidebar's "Share Household" toolbar item. The form
/// stays intentionally short — future preferences (per-item lead time,
/// rename household, member list, leave/transfer) hang off the same
/// screen later.
///
/// Reads the live `NotificationSettings` instance from the environment.
/// `@Bindable` lets the picker mutate hour/minute directly; the
/// `didSet` hooks on `NotificationSettings` handle the UserDefaults
/// write-through. Reschedule of pending notifications happens at the
/// scheduler-call sites (the parent's integration commit) — this view
/// is a pure preference editor.
///
/// **Voice:** `DESIGN_GUIDELINES.md` §9 classifies notification
/// permission requests as off-limits for personality, but the
/// preference for *when* a granted notification fires is a low-stakes
/// configuration moment, not a permission flow. Copy stays plain and
/// useful so users in a hurry can scan it without rolling their eyes
/// (§10 checklist), with a single light brand-consistent line.
struct SettingsView: View {
    @Environment(\.notificationSettings) private var settings
    @Environment(\.repositories) private var repositories
    @Environment(\.householdSharing) private var householdSharing
    @Environment(\.dismiss) private var dismiss

    /// Loaded asynchronously in `.task` from the household repository.
    /// `nil` while the load is in flight or if it failed; the row shows
    /// a neutral placeholder in that case rather than blocking the
    /// whole screen — the share action doesn't depend on the name.
    @State private var household: Household?
    @State private var isPresentingShareSheet = false

    /// Trace for #90 (blank Share Household sheet on TestFlight).
    /// Same subsystem/category as `CloudSharingControllerView` and
    /// `CloudHouseholdSharingService` so a single Console.app filter
    /// — `subsystem:cc.mnmlst.nakedpantree` — captures the full
    /// share path. `notice` level so messages show without the
    /// "Include Info Messages" toggle. Lifetime: keep until #90
    /// is closed, then trim to whatever turns out to be load-bearing.
    private static let logger = Logger(
        subsystem: "cc.mnmlst.nakedpantree",
        category: "sharing"
    )

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                householdSection
                expiryRemindersSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.surface)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isPresentingShareSheet) {
                if let household, let sharing = householdSharing {
                    CloudSharingControllerView(
                        householdID: household.id,
                        sharing: sharing,
                        onCompletion: { isPresentingShareSheet = false }
                    )
                    .ignoresSafeArea()
                } else {
                    // Diagnostic fallback for #90. If the sheet
                    // presents but the if-let above fails, the user
                    // sees a blank sheet — exactly the reported
                    // symptom. The .onAppear log captures which input
                    // was nil so the bug surfaces in Console without
                    // needing to attach a debugger.
                    Color.clear
                        .onAppear {
                            let householdState = household != nil ? "set" : "nil"
                            let sharingState = householdSharing != nil ? "set" : "nil"
                            Self.logger.error(
                                // swiftlint:disable:next line_length
                                "share sheet presented but if-let failed — household=\(householdState, privacy: .public) sharing=\(sharingState, privacy: .public)"
                            )
                        }
                }
            }
            .task { await loadHousehold() }
        }
    }

    /// Household section — name (read-only) plus Share Household row.
    /// Structured as a single `Section` so future rows (rename, member
    /// list, leave/transfer; out of scope for #60) slot in cleanly.
    @ViewBuilder
    private var householdSection: some View {
        Section {
            LabeledContent("Name") {
                Text(household?.name ?? "—")
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("settings.household.name")

            // Hidden in previews / tests / snapshot mode where the
            // sharing service is nil — see CloudHouseholdSharingService.
            // The name row above always renders so the section isn't
            // empty in those contexts.
            if householdSharing != nil {
                Button {
                    // First log line of the share path — earliest
                    // possible signal that the user actually tapped.
                    // `notice` level so the message is visible in
                    // Console.app without enabling Info messages.
                    let householdState = household != nil ? "set" : "nil"
                    let sharingState = householdSharing != nil ? "set" : "nil"
                    Self.logger.notice(
                        // swiftlint:disable:next line_length
                        "share button tapped — household=\(householdState, privacy: .public) sharing=\(sharingState, privacy: .public)"
                    )
                    isPresentingShareSheet = true
                } label: {
                    Label("Share Household", systemImage: "person.crop.circle.badge.plus")
                }
                .accessibilityIdentifier("settings.shareHousehold")
                .disabled(household == nil)
            }
        } header: {
            Text("Household")
        }
    }

    @ViewBuilder
    private var expiryRemindersSection: some View {
        @Bindable var settings = settings
        Section {
            DatePicker(
                "Reminder time",
                selection: timeOfDayBinding(for: settings),
                displayedComponents: .hourAndMinute
            )
            .accessibilityIdentifier("settings.notificationTime.picker")
        } header: {
            Text("Expiry reminders")
        } footer: {
            Text("We'll remind you 3 days before something expires.")
        }
    }

    /// `DatePicker(.hourAndMinute)` binds to a `Date`, but the
    /// preference is two `Int`s. Bridge them through an arbitrary
    /// reference date — only the hour and minute components survive
    /// the round-trip, the calendar day is irrelevant.
    private func timeOfDayBinding(for settings: NotificationSettings) -> Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = settings.hourOfDay
                components.minute = settings.minute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newValue in
                let components = Calendar.current.dateComponents(
                    [.hour, .minute],
                    from: newValue
                )
                settings.hourOfDay = components.hour ?? NotificationSettings.defaultHourOfDay
                settings.minute = components.minute ?? NotificationSettings.defaultMinute
            }
        )
    }

    /// Mirrors Sidebar's load pattern: swallow errors silently for now
    /// — the screen's other section (reminder time) keeps working, and
    /// the household row simply stays at its placeholder. A real error
    /// banner is a Phase 10 polish item once household mutations
    /// (rename, leave) need to surface failures.
    private func loadHousehold() async {
        do {
            household = try await repositories.household.currentHousehold()
        } catch {
            household = nil
        }
    }
}

#Preview("Default 9:00 AM") {
    SettingsView()
        .environment(\.notificationSettings, NotificationSettings())
        .environment(\.repositories, .makePreview())
}
