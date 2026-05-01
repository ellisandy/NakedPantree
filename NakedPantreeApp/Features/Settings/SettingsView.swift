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
///
/// **Multi-sheet conflict (issue #162).** SwiftUI's `.sheet` modifier
/// resolves at most one presentation per view. Earlier this file had
/// three (`locationFormMode`, `isPresentingRemindersListPicker`,
/// `preparedShare`) stacked on the NavigationStack. Probe build #165
/// proved that stacking caused the Reminders picker to mount and
/// auto-dismiss within ~553 ms — SwiftUI couldn't decide which sheet
/// the view was asking for and tore everything down. The fix is to
/// fold all three presentations through a single `.sheet(item:)`
/// driven by `SettingsSheet`. Per-sheet payloads (form mode, picker
/// lists, prepared share) stay on separate state vars so the enum
/// itself can be a thin tag without dragging non-Equatable
/// CloudKit types through Equatable synthesis.
struct SettingsView: View {
    @Environment(\.notificationSettings) private var settings
    @Environment(\.repositories) private var repositories
    @Environment(\.householdSharing) private var householdSharing
    @Environment(\.remindersService) private var remindersService
    @Environment(\.remindersListPreference) private var remindersListPreference
    @Environment(\.dismiss) private var dismiss

    /// Loaded asynchronously in `.task` from the household repository.
    /// `nil` while the load is in flight or if it failed; the row shows
    /// a neutral placeholder in that case rather than blocking the
    /// whole screen — the share action doesn't depend on the name.
    @State private var household: Household?

    /// Issue #162: single source of truth for which sheet is on
    /// screen. Set at the call sites (Add Location button, Pick a
    /// list button, Share Household button); reset to nil whenever
    /// the user dismisses the sheet (gesture, save, cancel). The
    /// `.onChange` watcher on this clears the matching payload vars
    /// below.
    @State private var presentedSheet: SettingsSheet?

    /// Form mode payload for `SettingsSheet.locationForm`. Held
    /// separately so the enum can be a thin tag and so the
    /// `LocationsSection` can write here via the `presentForm`
    /// callback below.
    @State private var locationFormMode: LocationFormView.Mode?

    /// Issue #90: prepared share payload for `SettingsSheet.shareHousehold`.
    /// `isPreparingShare` drives the spinner; `shareError` drives the
    /// alert. Kept separate from the enum because `CKShare` /
    /// `CKContainer` aren't `Equatable` and folding them inline would
    /// block automatic Equatable synthesis on `SettingsSheet`.
    @State private var preparedShare: ShareSheetPreparation.PreparedShare?
    @State private var isPreparingShare = false
    @State private var shareError: ShareErrorAlert?

    /// Issue #155: re-pick state for the Reminders list. Settings
    /// owns the picker presentation here (not the row) so the same
    /// SwiftUI presentation-context fix from build #52 applies — a
    /// `.sheet(isPresented:)` inside a Form's Section can collapse
    /// the whole sheet stack on present.
    @State private var remindersListPickerLists: [RemindersListSummary] = []
    @State private var remindersListPickerError: String?

    /// Issue #162 — signal channel for `LocationsSection` to refresh
    /// after the form sheet dismisses. The lifted `.sheet(item:)`
    /// pattern means the section can no longer observe its own
    /// `formMode` going nil; instead the parent bumps this token in
    /// `.onChange(of: presentedSheet)`. `&+=` is overflow-safe so a
    /// long-running view session never traps.
    @State private var locationsReloadToken = 0

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

    /// Issue #162 trace. Same subsystem so a single Console filter
    /// covers the whole picker flow; category `reminders` lets the
    /// share-flow logger above stay independent.
    private static let remindersLogger = Logger(
        subsystem: "cc.mnmlst.nakedpantree",
        category: "reminders"
    )

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                householdSection
                LocationsSection(
                    householdID: household?.id,
                    presentForm: { mode in
                        locationFormMode = mode
                        presentedSheet = .locationForm
                    },
                    reloadToken: locationsReloadToken
                )
                expiryRemindersSection
                remindersListSection
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
            // Issue #162: single presentation point. Stacking three
            // `.sheet` modifiers on this NavigationStack let SwiftUI
            // race them; the loser tore the winner back down. One
            // modifier, one source of truth — the sheet stays put.
            .sheet(item: $presentedSheet) { sheet in
                presentedSheetContent(for: sheet)
            }
            .onChange(of: presentedSheet) { oldValue, newValue in
                guard newValue == nil else { return }
                // Sheet just dismissed (gesture / save / cancel). Clear
                // the per-sheet payload, and bump the locations reload
                // token if the form was the one that closed.
                switch oldValue {
                case .locationForm:
                    locationFormMode = nil
                    locationsReloadToken &+= 1
                case .shareHousehold:
                    preparedShare = nil
                case .remindersListPicker, .none:
                    break
                }
            }
            .alert(
                "Couldn't load Reminders lists.",
                isPresented: remindersErrorBinding,
                presenting: remindersListPickerError
            ) { _ in
                Button("OK", role: .cancel) {
                    remindersListPickerError = nil
                }
            } message: { message in
                Text(message)
            }
            .alert(item: $shareError) { wrapper in
                Alert(
                    title: Text("Couldn't share"),
                    message: Text(wrapper.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .task { await loadHousehold() }
        }
    }

    /// Sheet content router. Pulled out of the modifier so the body
    /// stays scannable and the switch can grow another case without
    /// a giant inline closure.
    @ViewBuilder
    private func presentedSheetContent(for sheet: SettingsSheet) -> some View {
        switch sheet {
        case .locationForm:
            if let mode = locationFormMode {
                LocationFormView(mode: mode) {
                    // No-op — `.onChange(of: presentedSheet)` above
                    // bumps `locationsReloadToken` when this sheet
                    // closes, which triggers `LocationsSection` to
                    // refresh. Keeping the save callback empty here
                    // means save / cancel / drag-down all share the
                    // same dismissal path.
                }
            }
        case .remindersListPicker:
            RemindersListPickerSheet(
                lists: remindersListPickerLists,
                currentListID: remindersListPreference.listID,
                onPick: { picked in
                    remindersListPreference.listID = picked.id
                    presentedSheet = nil
                },
                onCancel: { presentedSheet = nil }
            )
        case .shareHousehold:
            if let prepared = preparedShare {
                // Issue #90: by the time this closure fires, the share
                // is already a real `CKShare` resolved by
                // `ShareSheetPreparation`. The controller uses
                // `init(share:container:)` and renders participant UI
                // immediately — no more lazy preparation handler.
                CloudSharingControllerView(
                    share: prepared.share,
                    container: prepared.container,
                    onCompletion: { presentedSheet = nil }
                )
                .ignoresSafeArea()
            }
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
                    Task { await prepareShareForPresentation() }
                } label: {
                    HStack {
                        Label("Share Household", systemImage: "person.crop.circle.badge.plus")
                        if isPreparingShare {
                            Spacer()
                            ProgressView()
                                .accessibilityIdentifier("settings.shareHousehold.spinner")
                        }
                    }
                }
                .accessibilityIdentifier("settings.shareHousehold")
                .disabled(household == nil || isPreparingShare)
            }
        } header: {
            Text("Household")
        }
    }

    /// Issue #155: Reminders integration row. The first push from
    /// `NeedsRestockingView` writes the chosen list id to
    /// `remindersListPreference.listID`; this row surfaces that
    /// choice and lets the user re-pick or clear it.
    ///
    /// Voice §10: copy reads as a configuration moment, not a sync
    /// failure path. The footer is a single light brand-tinted line
    /// — same calibration as `expiryRemindersSection`.
    @ViewBuilder
    private var remindersListSection: some View {
        Section {
            LabeledContent("Reminders list") {
                Text(currentListLabel)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("settings.remindersList.current")
            Button {
                Task { await loadRemindersListsAndPresent() }
            } label: {
                Label(
                    remindersListPreference.listID == nil
                        ? "Pick a list"
                        : "Change list",
                    systemImage: "list.bullet.rectangle"
                )
            }
            .accessibilityIdentifier("settings.remindersList.change")
            .disabled(isLoadingRemindersLists)
            if remindersListPreference.listID != nil {
                Button(role: .destructive) {
                    remindersListPreference.listID = nil
                } label: {
                    Label("Clear chosen list", systemImage: "xmark.circle")
                }
                .accessibilityIdentifier("settings.remindersList.clear")
            }
            if isLoadingRemindersLists {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Loading your Reminders lists…")
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("settings.remindersList.loading")
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text(
                "We'll write your restock items into this list when "
                    + "you tap Push to Reminders."
            )
        }
    }

    /// Display string for the "Reminders list" row. Renders the list
    /// title when we can resolve it (post-launch the picker results
    /// are cached), otherwise the raw id, otherwise an em-dash.
    private var currentListLabel: String {
        guard let id = remindersListPreference.listID else { return "—" }
        if let cached = remindersListPickerLists.first(where: { $0.id == id }) {
            return cached.title
        }
        // Fallback when the picker hasn't been opened yet — the user
        // sees an opaque short id, but tapping "Change list" loads
        // the names and the next render replaces it.
        return "(picked)"
    }

    private var remindersErrorBinding: Binding<Bool> {
        Binding(
            get: { remindersListPickerError != nil },
            set: { newValue in
                if !newValue { remindersListPickerError = nil }
            }
        )
    }

    /// Issue #162: spinner gate for the Reminders-list load. Right
    /// after a fresh permission grant `EKEventStore`'s iCloud sources
    /// can take ~10s to populate; `EventKitRemindersService` blocks
    /// inside `availableLists` until they do (or the timeout fires).
    /// During that window the row should read as in-flight rather
    /// than silently spin — users were tapping again and re-entering
    /// the same wait, then assumed the feature was broken.
    @State private var isLoadingRemindersLists = false

    /// Fetch available Reminders lists, then present the picker.
    /// Failure modes:
    /// - permission denied → friendly alert with the Settings deep
    ///   link (matches `NeedsRestockingView` shape)
    /// - other EventKit errors → present the error message in an
    ///   alert and let the user retry
    private func loadRemindersListsAndPresent() async {
        Self.remindersLogger.notice("settings.loadRemindersListsAndPresent: entry")
        isLoadingRemindersLists = true
        defer { isLoadingRemindersLists = false }
        do {
            let access = try await remindersService.requestAccess()
            Self.remindersLogger.notice(
                // swiftlint:disable:next line_length
                "settings.loadRemindersListsAndPresent: requestAccess returned \(String(describing: access), privacy: .public)"
            )
            guard access == .granted else {
                Self.remindersLogger.notice(
                    "settings.loadRemindersListsAndPresent: not granted, bailing"
                )
                remindersListPickerError =
                    "Turn on Reminders for Naked Pantree in Settings, then try again."
                return
            }
            let lists = try await remindersService.availableLists()
            Self.remindersLogger.notice(
                // swiftlint:disable:next line_length
                "settings.loadRemindersListsAndPresent: got \(lists.count, privacy: .public) lists, presenting"
            )
            remindersListPickerLists = lists
            presentedSheet = .remindersListPicker
        } catch {
            Self.remindersLogger.error(
                // swiftlint:disable:next line_length
                "settings.loadRemindersListsAndPresent: caught \(error.localizedDescription, privacy: .public)"
            )
            remindersListPickerError = error.localizedDescription
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

    /// Issue #90: kicks off `ShareSheetPreparation.prepareShare`,
    /// driving the spinner / sheet / alert state. Idempotent against
    /// the existing share — `CloudHouseholdSharingService` returns the
    /// same `CKShare` on subsequent calls so a tap → dismiss → tap
    /// sequence reuses the prepared share rather than minting a new
    /// one. The orphan-share trade-off (a single tap before any
    /// invite leaves a `CKShare` on iCloud) is accepted; a follow-up
    /// issue covers cleaning up empty shares on dismiss if it ever
    /// matters.
    @MainActor
    private func prepareShareForPresentation() async {
        guard let household, let sharing = householdSharing else {
            Self.logger.error(
                // swiftlint:disable:next line_length
                "prepareShareForPresentation: missing household or sharing service — household=\(household != nil ? "set" : "nil", privacy: .public) sharing=\(householdSharing != nil ? "set" : "nil", privacy: .public)"
            )
            return
        }
        isPreparingShare = true
        defer { isPreparingShare = false }

        let result = await ShareSheetPreparation.prepareShare(
            for: household.id,
            using: sharing
        )
        switch result {
        case .success(let payload):
            preparedShare = payload
            presentedSheet = .shareHousehold
        case .failure(let error):
            shareError = ShareErrorAlert(message: error.localizedDescription)
        }
    }
}

/// Issue #162 — single tag for whichever sheet `SettingsView` has
/// presented. Per-sheet payloads (form mode, picker lists, prepared
/// share) live on separate `@State` vars so this enum can stay thin
/// and `Hashable` without dragging non-`Equatable` CloudKit types
/// (`CKShare`, `CKContainer`) into automatic synthesis.
private enum SettingsSheet: String, Identifiable, Hashable {
    case locationForm
    case remindersListPicker
    case shareHousehold

    var id: String { rawValue }
}

/// `Identifiable` wrapper so `.alert(item:)` can drive on a single
/// state binding rather than a paired `isPresented` + `errorMessage`.
struct ShareErrorAlert: Identifiable {
    let id = UUID()
    let message: String
}

#Preview("Default 9:00 AM") {
    SettingsView()
        .environment(\.notificationSettings, NotificationSettings())
        .environment(\.repositories, .makePreview())
}
