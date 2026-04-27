import NakedPantreeDomain
import SwiftUI

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

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                householdSection
                expiryRemindersSection
            }
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
