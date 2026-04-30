import CoreData
import NakedPantreePersistence
import SwiftUI
import os

/// Bumps `changeToken` whenever the persistence layer reports a
/// non-self-emitted remote change — local writes by another household
/// member that CloudKit's mirror has imported, in Phase 2's
/// same-account-sync world. Views read the token via `.task(id:)` and
/// re-fetch when it ticks.
///
/// **Architectural note:** this lives in the app layer rather than behind
/// a `NakedPantreeDomain` protocol. The monitor only consumes
/// `NSPersistentStoreRemoteChange` posts off `NotificationCenter` plus
/// `NSPersistentHistoryChangeRequest` against the container — it never
/// calls into `NSPersistentCloudKitContainer` itself, so the
/// "no app code talks to CloudKit container directly" rule in
/// `AGENTS.md` §2 still holds. If a non-iOS surface (the future macOS
/// CLI, an AppIntent extension) needs the same signal, lift the
/// observer behind a Domain protocol then. Premature now.
///
/// **Self-emission filter (issue #28):** Phase 2.1 enables
/// `NSPersistentStoreRemoteChangeNotificationPostOptionKey` on both
/// stores, so a local `context.save()` also fires the notification.
/// Phase 10.4 closes that double-fire: `performBackgroundTaskWithDefaults`
/// stamps every background context with `transactionAuthor = "local"`,
/// and after each remote-change post we fetch the persistent-history
/// transactions since our last seen token. If every transaction has
/// `author == "local"` we ignore the post; the form callback's
/// optimistic reload already covered it. Anything else (CloudKit
/// mirror imports leave `author` nil) bumps `changeToken`.
///
/// **Token persistence:** the last-seen `NSPersistentHistoryToken` is
/// archived to `UserDefaults` so a process restart picks up where we
/// left off. Without this, the first refresh after launch would refetch
/// the entire history and treat every prior local save as a remote
/// change.
///
/// **Debounce:** notifications fan out — CloudKit fires per-store on
/// save (private + shared) and per-transaction on initial sync. A
/// single user action can produce 5+ notifications across one frame,
/// each previously bumping `changeToken` and triggering SwiftUI's
/// "onChange tried to update multiple times per frame" warning plus
/// a thundering herd of `.task(id:)` cancellations on app launch.
/// We coalesce into one history-fetch per ~120ms quiet window.
@Observable
@MainActor
final class RemoteChangeMonitor {
    private(set) var changeToken = UUID()

    /// `true` for the production initializer (real container);
    /// `false` for the no-op preview/test initializer. Phase 8.2's
    /// deferred bootstrap consults this to skip the
    /// wait-for-first-tick race when there's no source of remote
    /// changes — otherwise the in-memory test target would always
    /// hit the bootstrap timeout, since the no-op monitor's
    /// `changeToken` never bumps.
    nonisolated let isObserving: Bool

    // Held inside a `Sendable` `MutableTaskHolder` so `deinit`
    // (nonisolated) can read it without hopping back to the main
    // actor. Same pattern as `AccountStatusMonitor` — see the type's
    // doc comment for the rationale.
    @ObservationIgnored
    nonisolated private let taskHolder = MutableTaskHolder()

    /// Pending debounce timer. Each incoming notification cancels the
    /// previous timer and starts a new one — only the last
    /// notification followed by ~120ms of quiet actually triggers a
    /// history fetch. Stays on the main actor; no deinit cleanup
    /// needed since the task self-terminates after the sleep.
    private var debounceTask: Task<Void, Never>?

    /// Background context used to run `NSPersistentHistoryChangeRequest`.
    /// History fetches must happen on a managed-object-context queue;
    /// the view context would block the main thread and any background
    /// context returned by `performBackgroundTask` is a fresh per-call
    /// thing not worth re-creating each refresh. `nil` for the no-op
    /// initializer. `nonisolated` so the no-op `init()` (which is
    /// itself nonisolated) can write to it.
    nonisolated private let historyContext: NSManagedObjectContext?

    /// `UserDefaults` slot for the last-seen `NSPersistentHistoryToken`.
    /// `nil` for the no-op initializer; injected for tests so they don't
    /// pollute `.standard`. Mirrors the `NotificationSettings.defaults`
    /// pattern, including its `nonisolated(unsafe)` trade-off (Swift 6
    /// flags `UserDefaults?` as non-`Sendable`, but Apple ships
    /// `UserDefaults` as documented thread-safe).
    nonisolated(unsafe) private let defaults: UserDefaults?

    /// Key under which the archived `NSPersistentHistoryToken` lives in
    /// `UserDefaults`. Single token, app-wide — both stores feed the
    /// same observer, history is per-coordinator. Test fixtures should
    /// pass a unique suite name to keep parallel test runs from
    /// stomping on each other.
    ///
    /// `nonisolated` so the test target can read this constant from a
    /// non-MainActor context (Swift 6 otherwise treats statics on a
    /// `@MainActor` type as MainActor-isolated).
    nonisolated static let historyTokenDefaultsKey = "persistence.lastHistoryToken"

    /// Last-seen history token in memory. Persisted to `defaults`
    /// after each successful refresh. Read on init from defaults so
    /// the first post-launch fetch only sees transactions newer than
    /// the previous run's last refresh.
    private var lastHistoryToken: NSPersistentHistoryToken?

    /// No-op monitor for previews and tests. Never bumps `changeToken`.
    /// `nonisolated` so the `@Entry` environment default value (which
    /// must run in a non-isolated context) can construct one.
    nonisolated init() {
        self.isObserving = false
        self.historyContext = nil
        self.defaults = nil
    }

    /// Production initializer. Subscribes to `NSPersistentStoreRemoteChange`
    /// for the container's coordinator and runs a persistent-history
    /// filter on every notification. `defaults` is injected so tests
    /// can supply a fresh suite per run; production passes
    /// `.standard`.
    convenience init(container: NSPersistentContainer) {
        self.init(container: container, defaults: .standard)
    }

    init(container: NSPersistentContainer, defaults: UserDefaults) {
        self.isObserving = true
        self.defaults = defaults

        let context = container.newBackgroundContext()
        context.transactionAuthor = CoreDataStack.localTransactionAuthor
        self.historyContext = context

        // Restore the last-seen token from the previous launch so
        // the first refresh doesn't replay every prior local save.
        if let data = defaults.data(forKey: Self.historyTokenDefaultsKey),
            let token = try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: NSPersistentHistoryToken.self,
                from: data
            )
        {
            self.lastHistoryToken = token
        }

        let stream = NotificationCenter.default.notifications(
            named: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator
        )
        taskHolder.task = Task { @MainActor [weak self] in
            for await _ in stream {
                self?.scheduleRefresh()
            }
        }
    }

    deinit {
        taskHolder.task?.cancel()
    }

    private func scheduleRefresh() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(120))
                await self?.refresh()
            } catch {
                // Cancelled by a newer notification — that newer
                // notification owns the next refresh.
            }
        }
    }

    /// Fetch persistent-history transactions newer than `lastHistoryToken`,
    /// filter out our own (`author == "local"`), and only bump
    /// `changeToken` if anything else remains. Persists the new history
    /// token regardless so we don't reprocess local-only windows on the
    /// next pass.
    private func refresh() async {
        guard let context = historyContext else { return }
        // Wrap the prior token in a `Sendable` box before crossing the
        // MainActor → nonisolated boundary. `NSPersistentHistoryToken`
        // is documented-immutable but isn't annotated `Sendable` in
        // the SDK, so we vouch for it via `@unchecked` — same trade-off
        // `HistoryFetchOutcome` makes for the return trip.
        let previousToken = SendableHistoryToken(token: lastHistoryToken)

        // The continuation runs on the context's queue (not MainActor).
        // Hop back to MainActor through `await` — Swift treats
        // `let result = await ...` as a clean MainActor-isolated
        // value, so the subsequent `lastHistoryToken = newToken`
        // write is race-free.
        let outcome: HistoryFetchOutcome = await Self.fetchHistory(
            after: previousToken,
            in: context
        )

        if outcome.failed { return }
        if let newToken = outcome.newToken {
            lastHistoryToken = newToken
            persist(token: newToken)
        }
        if outcome.hasNonLocal {
            changeToken = UUID()
        }
    }

    /// Result of one history-fetch pass. A struct (rather than enum
    /// with associated values) keeps `pattern_matching_keywords` and
    /// `UseLetInEveryBoundCaseVariable` from disagreeing about how to
    /// destructure two `let` bindings — both linters are happy with a
    /// plain property read.
    ///
    /// **`@unchecked Sendable` rationale:** `NSPersistentHistoryToken`
    /// is documented-immutable but not annotated `Sendable` in the SDK
    /// (FB-tracked). It's safe to send across the
    /// `Core Data context queue → MainActor` hop because we never
    /// mutate it — Apple's `CoreDataCloudKit` sample does the same
    /// thing. Same trade-off `CoreDataStack.model` makes for
    /// `NSManagedObjectModel`.
    /// `Sendable` wrapper around the input token to `fetchHistory`. See
    /// `HistoryFetchOutcome` for the same `@unchecked Sendable` rationale.
    /// `internal` (not `private`) so `RemoteChangeMonitorFailureTests`
    /// can construct one for the failure-path test (issue #114).
    struct SendableHistoryToken: @unchecked Sendable {
        let token: NSPersistentHistoryToken?
    }

    /// `internal` (not `private`) so the failure-path test can read
    /// the `failed` flag on the returned outcome (issue #114).
    struct HistoryFetchOutcome: @unchecked Sendable {
        var newToken: NSPersistentHistoryToken?
        var hasNonLocal: Bool
        var failed: Bool

        static let failure = HistoryFetchOutcome(
            newToken: nil,
            hasNonLocal: false,
            failed: true
        )

        static func success(
            newToken: NSPersistentHistoryToken?,
            hasNonLocal: Bool
        ) -> HistoryFetchOutcome {
            HistoryFetchOutcome(
                newToken: newToken,
                hasNonLocal: hasNonLocal,
                failed: false
            )
        }
    }

    /// Runs `NSPersistentHistoryChangeRequest.fetchHistory(after:)` on
    /// the supplied context's queue and returns the outcome.
    ///
    /// **Why `author != "local"` rather than a positive match for an
    /// expected remote author:** CloudKit-mirrored imports leave
    /// `transactionAuthor` as `nil` (Apple's sample code does the same
    /// negative filter). Anything we didn't stamp ourselves is, by
    /// definition, not us.
    ///
    /// Logger for history-fetch failures (issue #114). The execute call
    /// can throw on a corrupt history store, a token from a wiped
    /// store, or a schema-skew window after a Core Data migration.
    /// Pre-#114 the failure was swallowed silently and the next
    /// refresh re-ran the same range forever; logging at least makes
    /// it discoverable in Console.app under
    /// `subsystem:cc.mnmlst.nakedpantree, category:remote-change`.
    nonisolated private static let logger = Logger(
        subsystem: "cc.mnmlst.nakedpantree",
        category: "remote-change"
    )

    /// `nonisolated` so the continuation closure can call into it from
    /// the Core Data queue without crossing the MainActor boundary.
    /// `internal` (not `private`) so `RemoteChangeMonitorFailureTests`
    /// can drive the failure branch directly with a context that
    /// rejects `NSPersistentHistoryChangeRequest`.
    nonisolated static func fetchHistory(
        after token: SendableHistoryToken,
        in context: NSManagedObjectContext
    ) async -> HistoryFetchOutcome {
        await withCheckedContinuation { continuation in
            context.perform {
                let request = NSPersistentHistoryChangeRequest.fetchHistory(after: token.token)
                // `.transactionsAndChanges` is what makes
                // `result.result as? [NSPersistentHistoryTransaction]`
                // non-nil — the default result type returns an opaque
                // value with a nil `result` and the filter would
                // silently match nothing.
                request.resultType = .transactionsAndChanges

                do {
                    let executed =
                        try context.execute(request) as? NSPersistentHistoryResult
                    let transactions =
                        (executed?.result as? [NSPersistentHistoryTransaction]) ?? []
                    let newestToken = transactions.last?.token
                    let hasNonLocal = transactions.contains { transaction in
                        transaction.author != CoreDataStack.localTransactionAuthor
                    }
                    continuation.resume(
                        returning: .success(
                            newToken: newestToken,
                            hasNonLocal: hasNonLocal
                        )
                    )
                } catch {
                    // Pre-#114 silent swallow. The token is *not*
                    // updated, so `refresh()` will re-fetch the same
                    // range on the next remote-change tick — at
                    // worst, redundant CPU until the underlying error
                    // resolves (history store re-initializes,
                    // migration completes, etc.).
                    Self.logger.error(
                        "history fetch failed: \(error.localizedDescription, privacy: .public)"
                    )
                    continuation.resume(returning: .failure)
                }
            }
        }
    }

    private func persist(token: NSPersistentHistoryToken) {
        guard let defaults else { return }
        do {
            let data = try NSKeyedArchiver.archivedData(
                withRootObject: token,
                requiringSecureCoding: true
            )
            defaults.set(data, forKey: Self.historyTokenDefaultsKey)
        } catch {
            // Token persistence is best-effort; on the next launch we
            // refetch from epoch and the worst case is one redundant
            // reload. Logging would just spam.
        }
    }
}

extension EnvironmentValues {
    @Entry var remoteChangeMonitor = RemoteChangeMonitor()
}
