import Foundation

/// In-memory `RemindersService` stub for previews, snapshot tests, the
/// `EMPTY_STORE` UI-test branch, and unit tests of the orchestrator.
/// Production code never sees this — `LiveDependencies.makeProduction*`
/// wires the EventKit adapter on the production branch.
///
/// **Why an actor:** `RemindersService` is `Sendable`, and the stored
/// state has to outlive a single call. Actor isolation gives us
/// thread-safe mutation without `@unchecked Sendable` ceremony, which
/// matches the pattern in `InMemoryItemRepository` /
/// `InMemoryLocationRepository`.
///
/// **Configurable surfaces** for tests:
/// - `accessStatus`: starts as `.granted`. Tests flip it to `.denied`
///   to drive the permission-denial UI.
/// - `applied`: every plan that's been pushed through `apply` is
///   appended here, so tests can assert the orchestrator built the
///   right plan without dissecting the post-apply snapshot state.
public actor InMemoryRemindersService: RemindersService {
    /// Mutable for tests; default `.granted` so previews / snapshot
    /// runs proceed without a prompt path. Production never uses this
    /// type so the choice has no UX impact in shipped builds.
    public var accessStatus: RemindersAccessStatus

    /// Every list the picker UI will offer. Identifiers are caller-
    /// supplied (typically `UUID().uuidString` or a short fixture
    /// string); titles are user-facing.
    public var lists: [RemindersListSummary]

    /// Reminders bucketed by list id. Tests seed this directly to
    /// stand up "an existing reminder is in the list" scenarios.
    public var rowsByListID: [String: [Row]]

    /// Audit trail of every plan that's been applied. Empty until the
    /// orchestrator pushes its first plan. Useful for tests:
    ///
    ///     #expect(service.applied.last?.creates.count == 3)
    public var applied: [ReminderPlan] = []

    /// Storage form for an in-memory reminder. Mirrors the fields the
    /// adapter's snapshot pass projects from `EKReminder`. Tests
    /// construct rows directly to seed pre-existing state.
    public struct Row: Sendable, Hashable {
        public var calendarItemIdentifier: String
        public var nakedPantreeID: UUID?
        public var title: String
        public var notes: String?
        public var url: URL?
        public var isCompleted: Bool

        public init(
            calendarItemIdentifier: String = UUID().uuidString,
            nakedPantreeID: UUID? = nil,
            title: String,
            notes: String? = nil,
            url: URL? = nil,
            isCompleted: Bool = false
        ) {
            self.calendarItemIdentifier = calendarItemIdentifier
            self.nakedPantreeID = nakedPantreeID
            self.title = title
            self.notes = notes
            self.url = url
            self.isCompleted = isCompleted
        }
    }

    public init(
        accessStatus: RemindersAccessStatus = .granted,
        lists: [RemindersListSummary] = [],
        rowsByListID: [String: [Row]] = [:]
    ) {
        self.accessStatus = accessStatus
        self.lists = lists
        self.rowsByListID = rowsByListID
    }

    public func setAccessStatus(_ status: RemindersAccessStatus) {
        self.accessStatus = status
    }

    public func seedList(_ list: RemindersListSummary, rows: [Row] = []) {
        if !lists.contains(where: { $0.id == list.id }) {
            lists.append(list)
        }
        rowsByListID[list.id, default: []].append(contentsOf: rows)
    }

    /// Returns a list's current rows. Tests use this to assert the
    /// post-apply state matches what the reconciler intended.
    public func rows(in listID: String) -> [Row] {
        rowsByListID[listID] ?? []
    }

    // MARK: RemindersService

    public func requestAccess() async throws -> RemindersAccessStatus {
        accessStatus
    }

    public func availableLists() async throws -> [RemindersListSummary] {
        guard accessStatus == .granted else {
            throw RemindersServiceError.accessNotGranted
        }
        return lists
    }

    public func snapshots(in listID: String) async throws -> [ReminderSnapshot] {
        guard accessStatus == .granted else {
            throw RemindersServiceError.accessNotGranted
        }
        guard let rows = rowsByListID[listID] else {
            throw RemindersServiceError.listNotFound(id: listID)
        }
        return rows.map { row in
            ReminderSnapshot(
                calendarItemIdentifier: row.calendarItemIdentifier,
                nakedPantreeID: ReminderTag.resolveItemID(
                    url: row.url,
                    notes: row.notes
                ),
                title: row.title,
                isCompleted: row.isCompleted
            )
        }
    }

    public func apply(_ plan: ReminderPlan, in listID: String) async throws {
        guard accessStatus == .granted else {
            throw RemindersServiceError.accessNotGranted
        }
        guard rowsByListID[listID] != nil else {
            throw RemindersServiceError.listNotFound(id: listID)
        }

        for create in plan.creates {
            rowsByListID[listID]?.append(
                Row(
                    nakedPantreeID: create.payload.nakedPantreeID,
                    title: create.payload.title,
                    notes: create.payload.notes,
                    url: create.payload.url,
                    isCompleted: false
                )
            )
        }
        for update in plan.titleUpdates {
            updateTitle(update, in: listID)
        }
        for completion in plan.completions {
            markCompleted(completion, in: listID)
        }
        applied.append(plan)
    }

    private func updateTitle(_ op: ReminderPlan.UpdateTitle, in listID: String) {
        guard var rows = rowsByListID[listID] else { return }
        if let index = rows.firstIndex(where: {
            $0.calendarItemIdentifier == op.calendarItemIdentifier
        }) {
            rows[index].title = op.newTitle
            rowsByListID[listID] = rows
        }
    }

    private func markCompleted(_ op: ReminderPlan.MarkCompleted, in listID: String) {
        guard var rows = rowsByListID[listID] else { return }
        if let index = rows.firstIndex(where: {
            $0.calendarItemIdentifier == op.calendarItemIdentifier
        }) {
            rows[index].isCompleted = true
            rowsByListID[listID] = rows
        }
    }
}
