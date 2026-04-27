import CoreData
import SwiftUI

/// Bumps `changeToken` whenever the persistence layer reports a remote
/// change — local writes by another household member that CloudKit's
/// mirror has imported, in Phase 2's same-account-sync world. Views read
/// the token via `.task(id:)` and re-fetch when it ticks.
///
/// **Architectural note:** this lives in the app layer rather than behind
/// a `NakedPantreeDomain` protocol. The monitor only consumes
/// `NSPersistentStoreRemoteChange` posts off `NotificationCenter` — it
/// never calls into `NSPersistentCloudKitContainer` itself, so the
/// "no app code talks to CloudKit container directly" rule in
/// `AGENTS.md` §2 still holds. If a non-iOS surface (the future macOS
/// CLI, an AppIntent extension) needs the same signal, lift the
/// observer behind a Domain protocol then. Premature now.
///
/// **Self-emission caveat:** Phase 2.1 enables
/// `NSPersistentStoreRemoteChangeNotificationPostOptionKey` on both
/// stores, so a local `context.save()` also fires this notification.
/// Form callbacks (`SidebarView` / `ItemsView` `onSave`) still trigger
/// an explicit reload, which means a local edit reloads twice — once
/// optimistically, once via the token. The double-fire is idempotent
/// and the second pass is cheap; filtering self vs remote properly
/// needs persistent-history-token bookkeeping (issue #28).
///
/// **Debounce:** notifications fan out — CloudKit fires per-store on
/// save (private + shared) and per-transaction on initial sync. A
/// single user action can produce 5+ notifications across one frame,
/// each previously bumping `changeToken` and triggering SwiftUI's
/// "onChange tried to update multiple times per frame" warning plus
/// a thundering herd of `.task(id:)` cancellations on app launch.
/// We coalesce into one bump per ~120ms quiet window.
@Observable
@MainActor
final class RemoteChangeMonitor {
    private(set) var changeToken = UUID()

    /// `true` for the production initializer (real coordinator);
    /// `false` for the no-op preview/test initializer. Phase 8.2's
    /// deferred bootstrap consults this to skip the
    /// wait-for-first-tick race when there's no source of remote
    /// changes — otherwise the in-memory test target would always
    /// hit the bootstrap timeout, since the no-op monitor's
    /// `changeToken` never bumps.
    nonisolated let isObserving: Bool

    // `nonisolated(unsafe)` so `deinit` (which Swift treats as
    // nonisolated) can cancel the task. The compiler nudges to drop
    // the `(unsafe)` since `Task<Void, Never>` is Sendable, but the
    // `@Observable` macro's generated backing storage rejects bare
    // `nonisolated` on mutable stored properties — so we keep
    // `(unsafe)` and live with the warning.
    nonisolated(unsafe) private var task: Task<Void, Never>?

    /// Pending debounce timer. Each incoming notification cancels the
    /// previous timer and starts a new one — only the last
    /// notification followed by ~120ms of quiet actually bumps the
    /// token. Stays on the main actor; no deinit cleanup needed since
    /// the task self-terminates after the sleep.
    private var debounceTask: Task<Void, Never>?

    /// No-op monitor for previews and tests. Never bumps `changeToken`.
    /// `nonisolated` so the `@Entry` environment default value (which
    /// must run in a non-isolated context) can construct one.
    nonisolated init() {
        self.isObserving = false
    }

    init(coordinator: NSPersistentStoreCoordinator) {
        self.isObserving = true
        let stream = NotificationCenter.default.notifications(
            named: .NSPersistentStoreRemoteChange,
            object: coordinator
        )
        task = Task { @MainActor [weak self] in
            for await _ in stream {
                self?.scheduleBump()
            }
        }
    }

    deinit {
        task?.cancel()
    }

    private func scheduleBump() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(120))
                self?.changeToken = UUID()
            } catch {
                // Cancelled by a newer notification — that newer
                // notification owns the next bump.
            }
        }
    }
}

extension EnvironmentValues {
    @Entry var remoteChangeMonitor = RemoteChangeMonitor()
}
