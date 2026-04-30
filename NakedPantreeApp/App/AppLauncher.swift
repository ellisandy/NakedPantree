import CloudKit
import CoreData
import Foundation
import NakedPantreeDomain
import NakedPantreePersistence
import SwiftUI

/// Owns the wiring between "app boot" and "first user-visible screen".
///
/// **Issue #106:** `CoreDataStack.cloudKitContainer()` used to call
/// `fatalError` on store-load failure — an unrecoverable crash on every
/// launch for any user who hit a corrupt SQLite, a partially-written
/// migration, or a failed automatic mapping-model inference. The
/// launcher catches the throw, parks in a `.failed` state, and renders
/// `DataRecoveryView` instead. The user can then **Try Again** (handles
/// transient failures) or **Reset Local Data** (deletes the SQLite
/// files; CloudKit re-syncs on next start, gated on iCloud being
/// signed in to avoid permanent data loss).
///
/// Same architectural placement as the previous in-init logic — the
/// launcher just hosts the state machine and exposes a SwiftUI surface.
/// Snapshot / `EMPTY_STORE` / unit-test paths short-circuit straight
/// to `.ready` because they don't touch the failing code path.
@MainActor
@Observable
final class AppLauncher {
    enum State {
        /// Briefly between init and the first build attempt completing.
        /// Production currently transitions out of this state
        /// synchronously inside `init`; the case exists so SwiftUI's
        /// body is never asked to render an undefined state, and so
        /// retry / reset can flush back to "loading" before the next
        /// build attempt completes.
        case loading
        /// Happy path. `LiveDependencies` carries every environment
        /// value `RootView` needs; the launcher hands ownership over
        /// once we're here.
        case ready(LiveDependencies)
        /// Store load threw. Render `DataRecoveryView`.
        case failed(LoadFailure)
    }

    /// Bundle of state the failed surface needs.
    struct LoadFailure {
        /// Human-readable description of the underlying failure. Used
        /// verbatim in the recovery view's "details" disclosure.
        let errorDescription: String
        /// Live `AccountStatusMonitor` for the recovery view to read
        /// `status` from — gates the destructive "Reset Local Data"
        /// button on iCloud being available.
        let accountStatusMonitor: AccountStatusMonitor
    }

    private(set) var state: State = .loading

    /// Closure that builds the live dependencies. Defaults to the
    /// production builder; tests inject a stub that throws to drive
    /// the `.failed` path.
    private let buildDependencies: @MainActor () throws -> LiveDependencies
    /// Closure that returns the `AccountStatusMonitor` to attach to
    /// a failure. Default constructs the production monitor against
    /// the iCloud container; tests inject a no-op monitor.
    private let makeFailureAccountMonitor: @MainActor () -> AccountStatusMonitor
    /// Closure that deletes the on-disk SQLite stores. Default deletes
    /// the production files; tests inject a no-op recorder.
    /// `@MainActor`-typed for parameter homogeneity — the production
    /// implementation is nonisolated (just filesystem calls) but the
    /// launcher is `@MainActor` so the conversion is free.
    private let deleteLocalStores: @MainActor () -> Void

    init(
        buildDependencies: @escaping @MainActor () throws -> LiveDependencies =
            AppLauncher.makeProductionDependencies,
        makeFailureAccountMonitor: @escaping @MainActor () -> AccountStatusMonitor =
            AppLauncher.makeProductionFailureAccountMonitor,
        deleteLocalStores: @escaping @MainActor () -> Void =
            AppLauncher.deleteProductionLocalStores
    ) {
        self.buildDependencies = buildDependencies
        self.makeFailureAccountMonitor = makeFailureAccountMonitor
        self.deleteLocalStores = deleteLocalStores
        attemptLoad()
    }

    /// User tapped "Try Again". Re-runs the same build path. Handles
    /// transient failures (disk pressure, brief filesystem hiccup)
    /// without destroying any data.
    func retry() {
        state = .loading
        attemptLoad()
    }

    /// User tapped "Reset Local Data" and confirmed. Deletes the
    /// SQLite stores, then re-runs the build. CloudKit will re-sync
    /// the user's pantry on the next successful launch — provided
    /// they're signed into iCloud, which the recovery view enforces
    /// before exposing this action.
    func resetAndRetry() {
        deleteLocalStores()
        state = .loading
        attemptLoad()
    }

    private func attemptLoad() {
        do {
            state = .ready(try buildDependencies())
        } catch {
            state = .failed(
                LoadFailure(
                    errorDescription: error.localizedDescription,
                    accountStatusMonitor: makeFailureAccountMonitor()
                )
            )
        }
    }
}

/// Bundle of every environment value `RootView` reads. The launcher
/// builds this on the happy path and hands it to the body via
/// `.environment(...)`.
struct LiveDependencies {
    let repositories: Repositories
    let remoteChangeMonitor: RemoteChangeMonitor
    let accountStatusMonitor: AccountStatusMonitor
    let householdSharing: (any HouseholdSharingService)?
    /// Issue #105: app-layer wrapper around `CloudShareAcceptance` that
    /// routes accept errors into a user-visible alert. RootView observes
    /// it via `\.shareAcceptanceCoordinator`.
    let shareAcceptanceCoordinator: ShareAcceptanceCoordinator
    let notificationScheduler: NotificationScheduler
    let notificationRouting: NotificationRoutingService
    let notificationSettings: NotificationSettings
}

// MARK: - Production builders

extension AppLauncher {
    /// The previous `NakedPantreeApp.init()` body, lifted out so the
    /// launcher can call it as a closure. Same branch order:
    /// snapshot-mode → `EMPTY_STORE` → unit-test host → production.
    /// Only the production branch can throw (issue #106).
    @MainActor
    static func makeProductionDependencies() throws -> LiveDependencies {
        // Phase 4.2: a single routing service across all branches —
        // preview / snapshot / test surfaces never get tap callbacks
        // (no scheduled notifications) but the environment value still
        // needs to resolve, and a fresh service is cheap.
        let routing = NotificationRoutingService()

        if SnapshotFixtures.isSnapshotMode {
            // Bypass Core Data when the snapshot UI tests launch us —
            // they need a deterministic, populated state and never want
            // a stray SQLite file from a previous run leaking through.
            NakedPantreeAppDelegate.wireNotificationRouting(routing)
            return LiveDependencies(
                repositories: SnapshotFixtures.makeSeededRepositories(),
                remoteChangeMonitor: RemoteChangeMonitor(),
                accountStatusMonitor: AccountStatusMonitor(),
                householdSharing: nil,
                shareAcceptanceCoordinator: ShareAcceptanceCoordinator(
                    service: NoOpShareAcceptanceService()
                ),
                notificationScheduler: NotificationScheduler(),
                notificationRouting: routing,
                notificationSettings: NotificationSettings()
            )
        }
        if ProcessInfo.processInfo.environment["EMPTY_STORE"] == "1" {
            // UI-test escape hatch: empty in-memory repos that exercise
            // the real bootstrap flow without persisting anything to
            // disk. Used by `BootstrapUITests` to regression-test the
            // first-launch race.
            //
            // `STUB_SHARING=1` swaps in `StubHouseholdSharingService`
            // so `SharingUITests` can drive the Settings → Share
            // Household path on CI without an iCloud account.
            let stubSharing = ProcessInfo.processInfo.environment["STUB_SHARING"] == "1"
            let sharing: (any HouseholdSharingService)? =
                stubSharing ? StubHouseholdSharingService() : nil
            NakedPantreeAppDelegate.wireNotificationRouting(routing)
            return LiveDependencies(
                repositories: .makePreview(),
                remoteChangeMonitor: RemoteChangeMonitor(),
                accountStatusMonitor: AccountStatusMonitor(),
                householdSharing: sharing,
                shareAcceptanceCoordinator: ShareAcceptanceCoordinator(
                    service: NoOpShareAcceptanceService()
                ),
                notificationScheduler: NotificationScheduler(),
                notificationRouting: routing,
                notificationSettings: NotificationSettings()
            )
        }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            // Unit tests load us via BUNDLE_LOADER, but the simulator has
            // no iCloud account so `cloudKitContainer()` would fail to
            // load. Repository contract tests stand up their own
            // in-memory container — the host repos here are never read.
            NakedPantreeAppDelegate.wireNotificationRouting(routing)
            return LiveDependencies(
                repositories: .makePreview(),
                remoteChangeMonitor: RemoteChangeMonitor(),
                accountStatusMonitor: AccountStatusMonitor(),
                householdSharing: nil,
                shareAcceptanceCoordinator: ShareAcceptanceCoordinator(
                    service: NoOpShareAcceptanceService()
                ),
                notificationScheduler: NotificationScheduler(),
                notificationRouting: routing,
                notificationSettings: NotificationSettings()
            )
        }

        return try makeLiveProductionDependencies(routing: routing)
    }

    /// Production CloudKit-backed branch. Lifted out of
    /// `makeProductionDependencies` so the parent stays under
    /// SwiftLint's `function_body_length` ceiling once issue #105's
    /// share-acceptance coordinator wiring landed.
    @MainActor
    private static func makeLiveProductionDependencies(
        routing: NotificationRoutingService
    ) throws -> LiveDependencies {
        // Phase 2.1: production stack is CloudKit-mirrored. Phase 3
        // adds the sharing service against the same container.
        let container = try CoreDataStack.cloudKitContainer()
        let cloudKitContainer = CKContainer(
            identifier: CoreDataStack.cloudKitContainerIdentifier
        )
        let repositories = Repositories(
            household: CoreDataHouseholdRepository(container: container),
            location: CoreDataLocationRepository(container: container),
            item: CoreDataItemRepository(container: container),
            photo: CoreDataItemPhotoRepository(container: container)
        )
        let remoteChangeMonitor = RemoteChangeMonitor(container: container)
        let accountStatusMonitor = AccountStatusMonitor(container: cloudKitContainer)
        let householdSharing = CloudHouseholdSharingService(
            container: container,
            cloudKitContainer: cloudKitContainer
        )
        // Phase 3.2 / Issue #105: hand the share-acceptance coordinator
        // to the delegate so `application(_:userDidAcceptCloudKitShareWith:)`
        // can import shared records when a recipient taps an invite —
        // and surface failures via the coordinator's `lastErrorMessage`
        // alert state instead of swallowing them in `print`.
        let shareAcceptanceCoordinator = ShareAcceptanceCoordinator(
            service: CloudShareAcceptance(container: container)
        )
        NakedPantreeAppDelegate.wireShareAcceptanceCoordinator(shareAcceptanceCoordinator)
        let notificationSettings = NotificationSettings(defaults: .standard)
        let notificationScheduler = NotificationScheduler(
            center: .current(),
            settings: notificationSettings
        )
        // Phase 4.2: the delegate routes notification taps into this
        // service. Same static-var seam as the share-acceptance one —
        // delegate construction precedes app init, so the wire-up is a
        // post-hoc handoff.
        NakedPantreeAppDelegate.wireNotificationRouting(routing)

        return LiveDependencies(
            repositories: repositories,
            remoteChangeMonitor: remoteChangeMonitor,
            accountStatusMonitor: accountStatusMonitor,
            householdSharing: householdSharing,
            shareAcceptanceCoordinator: shareAcceptanceCoordinator,
            notificationScheduler: notificationScheduler,
            notificationRouting: routing,
            notificationSettings: notificationSettings
        )
    }

    /// Production failure path needs an `AccountStatusMonitor` so the
    /// recovery view can gate the destructive button on iCloud
    /// availability. The monitor is independent of Core Data — it
    /// only needs the iCloud `CKContainer`, which constructs cleanly
    /// even when `loadPersistentStores` failed.
    @MainActor
    static func makeProductionFailureAccountMonitor() -> AccountStatusMonitor {
        let cloudKitContainer = CKContainer(
            identifier: CoreDataStack.cloudKitContainerIdentifier
        )
        return AccountStatusMonitor(container: cloudKitContainer)
    }

    /// Deletes the production SQLite stores plus their `-shm` / `-wal`
    /// sidecar files. `try?` swallows missing-file errors — the user
    /// might have hit "Reset" twice in a row, and the second pass has
    /// nothing to delete.
    static func deleteProductionLocalStores() {
        let urls = CoreDataStack.cloudKitStoreFileURLs()
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
