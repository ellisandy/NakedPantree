import CloudKit
import NakedPantreePersistence
import SwiftUI
import os

/// Issue #105: app-layer wrapper around `ShareAcceptanceService` that
/// observes import errors and surfaces them as user-visible alert state.
/// Replaces the silent `print()` failure path that #105 flagged as a
/// Phase 3.2 blocker.
///
/// The coordinator owns the service so SwiftUI views can hold a single
/// `@Observable` reference rather than threading both a service and an
/// error sink through the environment. `@MainActor` because the alert
/// state binds straight into a SwiftUI `.alert(...)` and SwiftUI reads
/// observable state from the main actor.
///
/// **Layering:** `@Observable` deliberately doesn't live in
/// `NakedPantreePersistence` — the persistence package stays pure
/// throws-on-error, and the UI-facing wrapper lives here.
@Observable
@MainActor
final class ShareAcceptanceCoordinator {
    /// Body of the user-facing alert when the most recent
    /// `accept(metadata:)` failed. `nil` while no error is in flight,
    /// either because nothing has thrown yet or because the user
    /// dismissed / retried successfully.
    private(set) var lastErrorMessage: String?

    /// Last failed accept captured as a closure so the user's "Try
    /// Again" tap on the alert can re-attempt without re-receiving the
    /// system invite. Stored as a closure (rather than the raw
    /// `CKShare.Metadata`) because `CKShare.Metadata.init()` is
    /// `unavailable`, so tests can't construct one to drive the retry
    /// path — exposing the closure-based seam (`runFallible(_:)`)
    /// gives tests a way in without resorting to runtime tricks. See
    /// `ShareAcceptanceCoordinatorTests` for the test-side usage.
    private var lastFailedOperation: (@MainActor @Sendable () async throws -> Void)?

    private let service: any ShareAcceptanceService

    /// Trace lines come out under the same subsystem/category as the
    /// rest of the share path so a single Console.app filter captures
    /// the full flow.
    private static let logger = Logger(
        subsystem: "cc.mnmlst.nakedpantree",
        category: "sharing"
    )

    /// `nonisolated` so SwiftUI's `@Entry` macro can construct the
    /// default coordinator from the synthesized environment-key
    /// `defaultValue`, which is synchronous and not MainActor-isolated.
    /// The init only assigns the (`Sendable`) service to a stored
    /// property — no MainActor state is touched.
    nonisolated init(service: any ShareAcceptanceService) {
        self.service = service
    }

    /// Imports the share. On failure, populates `lastErrorMessage` so
    /// the alert in `RootView` presents and remembers the failed
    /// attempt so `retry()` can re-attempt. On success, clears any
    /// prior error state — successive accepts shouldn't carry over a
    /// stale alert.
    func accept(metadata: CKShare.Metadata) async {
        let service = self.service
        await runFallible {
            try await service.acceptShare(metadata: metadata)
        }
    }

    /// Re-attempts the most recent failed accept. No-op when there's
    /// nothing to retry — the alert binding only renders the button
    /// when `lastErrorMessage != nil`, so the guard exists for safety
    /// rather than a real reachable case.
    func retry() async {
        guard let operation = lastFailedOperation else { return }
        await runFallible(operation)
    }

    /// Clears the alert state without re-attempting. Bound to the
    /// alert's "Dismiss" button.
    func dismissError() {
        lastErrorMessage = nil
        lastFailedOperation = nil
    }

    /// `internal` test seam: runs `operation`, publishes a user-visible
    /// message on throw, clears state on success, and captures the
    /// throwing closure so `retry()` can replay it. Production routes
    /// here from `accept(metadata:)`; tests use it directly so they
    /// can pin the publish / retry / clear-on-success contract
    /// without constructing a `CKShare.Metadata` (whose `init()` is
    /// `unavailable`).
    internal func runFallible(
        _ operation: @escaping @MainActor @Sendable () async throws -> Void
    ) async {
        do {
            try await operation()
            Self.logger.notice("ShareAcceptanceCoordinator: accept succeeded")
            lastErrorMessage = nil
            lastFailedOperation = nil
        } catch {
            Self.logger.error(
                "ShareAcceptanceCoordinator: accept failed: \(error.localizedDescription, privacy: .public)"
            )
            lastErrorMessage = Self.userMessage(for: error)
            lastFailedOperation = operation
        }
    }

    /// Voice-rule §9 copy: sync failures stay plain. The `.localizedDescription`
    /// from a `CKError` is often technical ("CKErrorDomain error 7" /
    /// "Couldn't communicate with a helper application") so we map to a
    /// short, useful, user-readable line. The underlying error still
    /// goes to the unified log above for diagnosis.
    private static func userMessage(for error: Error) -> String {
        if let cloudShareError = error as? CloudShareAcceptanceError {
            switch cloudShareError {
            case .sharedStoreUnavailable:
                return
                    "Couldn't import that household — iCloud isn't ready yet. Try again in a moment."
            }
        }
        return
            "Couldn't import that household. Try again — if it keeps happening, ask the sender to re-share."
    }
}

/// No-op `ShareAcceptanceService` for previews and tests. Lives in the
/// app target (alongside `ShareAcceptanceCoordinator`) so the env-value
/// default doesn't need to spin up a `CloudShareAcceptance`.
struct NoOpShareAcceptanceService: ShareAcceptanceService {
    func acceptShare(metadata: CKShare.Metadata) async throws {
        // Intentionally empty — the `@Environment` default coordinator
        // is the only consumer, and it should never be called from a
        // preview / test surface.
    }
}

extension EnvironmentValues {
    /// Default coordinator wraps the no-op service so previews / tests
    /// don't construct a real CloudKit container. Production replaces
    /// this via `AppLauncher.makeProductionDependencies`.
    @Entry var shareAcceptanceCoordinator = ShareAcceptanceCoordinator(
        service: NoOpShareAcceptanceService()
    )
}
