import NakedPantreeDomain
import SwiftUI
import UIKit

/// Issue #16: "Needs Restocking" smart-list content column. Cross-
/// household list of items the user has flagged for restocking
/// (`needsRestocking == true`) or that are out of stock
/// (`quantity == 0`). The repository handles the union and sort —
/// see `ItemRepository.needsRestocking(in:)`.
///
/// Same shape as `AllItemsView` / `RecentlyAddedView`: load on the
/// remote-change tick, render rows + leading swipe to flip the flag
/// off (the swipe label flips to "Got it" when the item is already
/// flagged), trailing swipe stays empty here — destructive deletes
/// belong on the per-location list, not on a smart projection.
///
/// Issue #155: a `Push to Reminders` toolbar button takes the items
/// currently on this list and writes them as `EKReminder`s into the
/// user's chosen Reminders list. The orchestration lives in
/// `PushToRemindersCoordinator`; this view just drives its state
/// machine and renders the picker / toast / inline-error surfaces.
struct NeedsRestockingView: View {
    @Binding var selectedItemID: Item.ID?

    @Environment(\.repositories) private var repositories
    @Environment(\.remoteChangeMonitor) private var remoteChangeMonitor
    @Environment(\.remindersService) private var remindersService
    @Environment(\.remindersListPreference) private var remindersListPreference
    @State private var items: [Item] = []
    @State private var locationsByID: [Location.ID: Location] = [:]
    @State private var didLoad = false
    /// Issue #155: lazily constructed on first appearance. The
    /// coordinator captures the service + preference instance for
    /// the lifetime of the view.
    @State private var pushCoordinator: PushToRemindersCoordinator?

    var body: some View {
        Group {
            if !didLoad {
                ProgressView()
            } else if items.isEmpty {
                emptyState
            } else {
                List(selection: $selectedItemID) {
                    ForEach(items) { item in
                        NeedsRestockingRow(
                            item: item,
                            locationName: locationsByID[item.locationID]?.name
                        )
                        .tag(item.id)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            RestockSwipeButton(item: item) { newValue in
                                Task { await toggle(item.id, to: newValue) }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.surface)
            }
        }
        .navigationTitle("Needs Restocking")
        .toolbar { pushToolbar }
        .task(id: remoteChangeMonitor.changeToken) {
            await load()
        }
        .onAppear {
            // Build the coordinator once. SwiftUI may rebuild the
            // view in compact-iPhone splits but `@State` survives;
            // the `?? makeCoordinator()` keeps construction lazy and
            // idempotent.
            if pushCoordinator == nil {
                pushCoordinator = makeCoordinator()
            }
        }
        .sheet(isPresented: pickerPresentationBinding) {
            pickerSheet
        }
        .alert(
            "Reminders access isn't on yet.",
            isPresented: permissionDeniedBinding
        ) {
            Button("Open Settings") {
                openSystemSettings()
                pushCoordinator?.acknowledge()
            }
            Button("Not now", role: .cancel) {
                pushCoordinator?.acknowledge()
            }
        } message: {
            Text(
                "Turn on Reminders for Naked Pantree in Settings, "
                    + "then try again."
            )
        }
        .alert(
            "Couldn't push to Reminders.",
            isPresented: failureBinding,
            presenting: failureMessage
        ) { _ in
            Button("OK", role: .cancel) {
                pushCoordinator?.acknowledge()
            }
        } message: { message in
            Text(message)
        }
        .overlay(alignment: .bottom) {
            if let summary = completedSummary {
                pushedToast(summary)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: completedSummary)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var pushToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await runPush() }
            } label: {
                Label("Push to Reminders", systemImage: "list.bullet.rectangle")
            }
            .accessibilityIdentifier("needsRestocking.pushToReminders")
            // Voice §10: empty list disables the button — there's
            // nothing to push, and "Pushed 0 items" reads as a bug.
            .disabled(items.isEmpty || isRunning)
        }
    }

    // MARK: Coordinator helpers

    private func makeCoordinator() -> PushToRemindersCoordinator {
        PushToRemindersCoordinator(
            service: remindersService,
            preference: remindersListPreference
        )
    }

    private func runPush() async {
        if pushCoordinator == nil { pushCoordinator = makeCoordinator() }
        await pushCoordinator?.requestPush(
            items: items,
            locationsByID: locationsByID
        )
    }

    private var isRunning: Bool {
        if case .running = pushCoordinator?.state { return true }
        return false
    }

    // MARK: State-driven sheet / alert / toast bindings

    private var pickerPresentationBinding: Binding<Bool> {
        Binding(
            get: {
                if case .needsListPick = pushCoordinator?.state { return true }
                return false
            },
            set: { newValue in
                if !newValue { pushCoordinator?.cancelListPick() }
            }
        )
    }

    @ViewBuilder
    private var pickerSheet: some View {
        if case .needsListPick(let lists) = pushCoordinator?.state {
            RemindersListPickerSheet(
                lists: lists,
                currentListID: remindersListPreference.listID,
                onPick: { picked in
                    Task {
                        await pushCoordinator?.setChosenListID(
                            picked.id,
                            items: items,
                            locationsByID: locationsByID
                        )
                    }
                },
                onCancel: { pushCoordinator?.cancelListPick() }
            )
        }
    }

    private var permissionDeniedBinding: Binding<Bool> {
        Binding(
            get: {
                if case .permissionDenied = pushCoordinator?.state { return true }
                return false
            },
            set: { newValue in
                if !newValue { pushCoordinator?.acknowledge() }
            }
        )
    }

    private var failureBinding: Binding<Bool> {
        Binding(
            get: {
                if case .failed = pushCoordinator?.state { return true }
                return false
            },
            set: { newValue in
                if !newValue { pushCoordinator?.acknowledge() }
            }
        )
    }

    private var failureMessage: String? {
        if case .failed(let message) = pushCoordinator?.state { return message }
        return nil
    }

    private var completedSummary: PushToRemindersCoordinator.PushSummary? {
        if case .completed(let summary) = pushCoordinator?.state { return summary }
        return nil
    }

    @ViewBuilder
    private func pushedToast(_ summary: PushToRemindersCoordinator.PushSummary) -> some View {
        // Voice rule §10: brand wink that's still useful, scannable
        // at glance. The phrasing here is from the issue spec
        // ("Pushed N items to <list>. Don't forget your bag.").
        VStack(spacing: 4) {
            Text(toastTitle(for: summary))
                .font(.subheadline.weight(.semibold))
            Text("Don't forget your bag.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("needsRestocking.pushedToast")
        .task {
            // Auto-acknowledge after a short read window so the toast
            // doesn't linger across re-pushes. 2.5s reads as a normal
            // notification dwell time.
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            pushCoordinator?.acknowledge()
        }
    }

    private func toastTitle(
        for summary: PushToRemindersCoordinator.PushSummary
    ) -> String {
        if summary.totalChanges == 0 {
            return "Reminders is already up to date."
        }
        let count = summary.createdCount + summary.updatedCount
        let item = count == 1 ? "item" : "items"
        return "Pushed \(count) \(item) to \(summary.listTitle)."
    }

    // MARK: System Settings deep link

    /// Opens iOS Settings → Naked Pantree so the user can flip
    /// Reminders permission on. Spec calls this out as the friendly
    /// fallback for the denial path.
    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }

    // MARK: Existing flow

    @ViewBuilder
    private var emptyState: some View {
        // Voice rule §10: short, calming, with a brand wink that's
        // *not* about a sync failure (those are off-limits per §9).
        // "Pantry's stocked." was the canonical line in the issue's
        // empty-state suggestion — keeping it.
        ContentUnavailableView(
            "Pantry's stocked.",
            systemImage: "checkmark.seal",
            description: Text("Items you flag for restocking will show up here.")
        )
    }

    private func load() async {
        do {
            let household = try await repositories.household.currentHousehold()
            let locations = try await repositories.location.locations(in: household.id)
            locationsByID = Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0) })
            items = try await repositories.item.needsRestocking(in: household.id)
        } catch {
            items = []
        }
        didLoad = true
    }

    private func toggle(_ id: Item.ID, to newValue: Bool) async {
        do {
            try await repositories.item.setNeedsRestocking(
                id: id,
                needsRestocking: newValue
            )
            await load()
        } catch {
            // Soft-fail — reload picks up canonical state on the
            // next remote-change tick. Swallowing matches the same
            // shape as `ItemsView.delete`'s catch arm.
        }
    }
}

private struct NeedsRestockingRow: View {
    let item: Item
    let locationName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(item.name).font(.body)
                // Issue #156: shared expired badge across every list.
                // An expired item that's also flagged for restock is
                // exactly the case the user wants surfaced in red.
                ItemExpiryBadge(expiresAt: item.expiresAt)
            }
            HStack(spacing: 8) {
                if let locationName {
                    Text(locationName)
                    Text("·")
                }
                // The two reasons an item lands here render as a hint
                // the user can scan without opening the detail. Both
                // reasons show when both apply.
                if item.quantity == 0 {
                    Text("Out of stock")
                }
                if item.needsRestocking && item.quantity == 0 {
                    Text("·")
                }
                if item.needsRestocking {
                    Text("Flagged")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    @Previewable @State var selectedItemID: Item.ID?
    NavigationStack {
        NeedsRestockingView(selectedItemID: $selectedItemID)
    }
    .environment(\.repositories, .makePreview())
}
