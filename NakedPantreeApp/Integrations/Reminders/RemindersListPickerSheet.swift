import NakedPantreeDomain
import SwiftUI
import os

/// Issue #155 — picker UI for the Reminders list a push lands in.
/// Presented in two contexts:
///
/// - First-time push from `NeedsRestockingView` — coordinator emits
///   `.needsListPick(lists)`, the view presents this sheet over the
///   smart list, the user picks, the coordinator re-runs the push.
/// - Settings re-pick — the same sheet, presented from the Reminders
///   list row when the user wants to change their choice.
///
/// Voice rules (DESIGN_GUIDELINES §10): plain, short, one cream-line
/// brand wink in the empty state. No personality on the action
/// buttons themselves — they're verbs the user reads on autopilot.
struct RemindersListPickerSheet: View {
    let lists: [RemindersListSummary]
    /// `nil` when the user has never picked one. Used to highlight the
    /// current selection so the Settings re-pick path reads as
    /// "change from X to Y" instead of "you have no choice yet."
    let currentListID: String?
    let onPick: (RemindersListSummary) -> Void
    let onCancel: () -> Void

    /// Issue #162 probe: confirm whether the picker actually mounts
    /// (and how many rows it sees) before SwiftUI tears it back down.
    /// Same subsystem/category as `EventKitRemindersService`.
    private static let logger = Logger(
        subsystem: "cc.mnmlst.nakedpantree",
        category: "reminders"
    )

    var body: some View {
        NavigationStack {
            Group {
                if lists.isEmpty {
                    emptyState
                } else {
                    listContent
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.surface)
            .navigationTitle("Pick a list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
            }
            .onAppear {
                let count = lists.count
                Self.logger.notice(
                    "RemindersListPickerSheet.onAppear: rendering count=\(count, privacy: .public)"
                )
            }
            .onDisappear {
                Self.logger.notice(
                    "RemindersListPickerSheet.onDisappear"
                )
            }
        }
    }

    @ViewBuilder
    private var listContent: some View {
        List {
            Section {
                ForEach(lists) { list in
                    Button {
                        onPick(list)
                    } label: {
                        HStack {
                            Text(list.title)
                                .foregroundStyle(Color.primary)
                            Spacer()
                            if list.id == currentListID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .accessibilityIdentifier("reminders.listPicker.row.\(list.id)")
                }
            } footer: {
                Text(
                    "We'll write your restock items into the list you pick. "
                        + "You can change this later from Settings."
                )
            }
        }
        .accessibilityIdentifier("reminders.listPicker")
    }

    @ViewBuilder
    private var emptyState: some View {
        // Voice §10 — one short brand-tinted line, scannable, no
        // sync-failure phrasing per §9.
        ContentUnavailableView(
            "No Reminders lists.",
            systemImage: "list.bullet.rectangle",
            description: Text(
                "Open Reminders, make a list, then come back."
            )
        )
    }
}

#Preview("With lists") {
    RemindersListPickerSheet(
        lists: [
            RemindersListSummary(id: "1", title: "Groceries"),
            RemindersListSummary(id: "2", title: "Costco run"),
            RemindersListSummary(id: "3", title: "Farmers market"),
        ],
        currentListID: "2",
        onPick: { _ in },
        onCancel: {}
    )
}

#Preview("Empty") {
    RemindersListPickerSheet(
        lists: [],
        currentListID: nil,
        onPick: { _ in },
        onCancel: {}
    )
}
