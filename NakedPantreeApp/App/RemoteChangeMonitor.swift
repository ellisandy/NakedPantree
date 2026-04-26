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
/// needs persistent-history-token bookkeeping (Phase 2.4).
@Observable
@MainActor
final class RemoteChangeMonitor {
    private(set) var changeToken = UUID()

    // `nonisolated(unsafe)` so `deinit` (which Swift treats as
    // nonisolated) can cancel the task. The task only writes `task`
    // once at init time and reads it once at deinit; no concurrent
    // mutation.
    nonisolated(unsafe) private var task: Task<Void, Never>?

    /// No-op monitor for previews and tests. Never bumps `changeToken`.
    /// `nonisolated` so the `@Entry` environment default value (which
    /// must run in a non-isolated context) can construct one.
    nonisolated init() {}

    init(coordinator: NSPersistentStoreCoordinator) {
        let stream = NotificationCenter.default.notifications(
            named: .NSPersistentStoreRemoteChange,
            object: coordinator
        )
        task = Task { @MainActor [weak self] in
            for await _ in stream {
                self?.changeToken = UUID()
            }
        }
    }

    deinit {
        task?.cancel()
    }
}

extension EnvironmentValues {
    @Entry var remoteChangeMonitor = RemoteChangeMonitor()
}
