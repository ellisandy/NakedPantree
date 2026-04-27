import SwiftUI

/// User-level Settings screen. Phase 9.3 ships exactly one knob — the
/// time of day expiry reminders fire — so the form is intentionally
/// short. Future preferences (per-item lead time, multiple reminders
/// per day, per-household time) hang off the same screen later.
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
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
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
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
}

#Preview("Default 9:00 AM") {
    SettingsView()
        .environment(\.notificationSettings, NotificationSettings())
}
