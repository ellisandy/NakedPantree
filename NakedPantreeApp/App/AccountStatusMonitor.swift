import CloudKit
import SwiftUI

/// Maps `CKAccountStatus` to the cases the UI actually distinguishes —
/// the SDK enum has slightly more states than the banner cares about.
enum AccountStatus: Sendable, Hashable {
    /// Signed in and ready. Banner is hidden.
    case available
    /// User is not signed into iCloud at all. Banner offers "Open Settings".
    case noAccount
    /// iCloud is restricted (parental controls, MDM, …). No remediation
    /// from inside the app — banner explains and steps back.
    case restricted
    /// Couldn't reach iCloud servers. Usually transient (offline,
    /// captive portal). Banner explains; status will recheck when
    /// `.CKAccountChanged` fires.
    case couldNotDetermine
    /// iOS 15+: account exists but iCloud is unavailable right now
    /// (Apple-side issue or device throttling). Banner explains; same
    /// recheck path as `.couldNotDetermine`.
    case temporarilyUnavailable
}

/// Tracks the user's iCloud account state and surfaces problems via a
/// banner above the main UI. Voice rules in `DESIGN_GUIDELINES.md` §9
/// classify sync failures as off-limits for personality — copy here
/// stays plain, calm, and direct.
///
/// Same architectural trade-off as `RemoteChangeMonitor`: lives in the
/// app layer because it consumes a `CKContainer` API + a
/// `NotificationCenter` post, never touching `NSPersistentCloudKitContainer`.
/// If a non-iOS surface needs the same signal later, lift behind a
/// Domain protocol then.
///
/// Default state is `.available` so previews and tests render without
/// a banner. The production initializer kicks off an immediate probe
/// and refreshes whenever `.CKAccountChanged` fires; the brief moment
/// before the first probe finishes shows no banner, which is the same
/// outcome as a healthy account — acceptable.
@Observable
@MainActor
final class AccountStatusMonitor {
    private(set) var status: AccountStatus = .available

    /// Cancellation handle for the in-flight account-status fetch.
    /// Stored inside a `Sendable` holder so `deinit` (nonisolated)
    /// can read it without hopping back to the main actor.
    /// `@ObservationIgnored` keeps the `@Observable` macro from
    /// observing an implementation detail.
    ///
    /// Earlier versions used `nonisolated(unsafe) private var task`,
    /// which the Swift 6 compiler flags with a "has no effect, consider
    /// using 'nonisolated'" warning — but bare `nonisolated` is then
    /// rejected for mutable stored properties. The holder is the clean
    /// way out: `let`-stored so `nonisolated` reads work, with the
    /// mutable slot living inside a `Sendable` reference type.
    @ObservationIgnored
    nonisolated private let taskHolder = MutableTaskHolder()

    /// No-op monitor for previews and tests. Status stays `.available`
    /// so the banner is hidden. `nonisolated` so the `@Entry` default
    /// can construct one outside any actor.
    nonisolated init() {}

    init(container: CKContainer) {
        let stream = NotificationCenter.default.notifications(named: .CKAccountChanged)
        taskHolder.task = Task { @MainActor [weak self] in
            await self?.refresh(using: container)
            for await _ in stream {
                await self?.refresh(using: container)
            }
        }
    }

    deinit {
        taskHolder.task?.cancel()
    }

    private func refresh(using container: CKContainer) async {
        do {
            let raw = try await container.accountStatus()
            status = Self.map(raw)
        } catch {
            status = .couldNotDetermine
        }
    }

    /// `nonisolated internal` (not `private`) so
    /// `AccountStatusMonitorMappingTests` can pin every
    /// `CKAccountStatus → AccountStatus` case directly (issue #112).
    /// Pure function with no actor-dependent state; the enclosing
    /// class is `@MainActor` only because of the published `status`
    /// property and the `task` lifecycle. The mapping itself doesn't
    /// touch either.
    nonisolated static func map(_ raw: CKAccountStatus) -> AccountStatus {
        switch raw {
        case .available: .available
        case .noAccount: .noAccount
        case .restricted: .restricted
        case .couldNotDetermine: .couldNotDetermine
        case .temporarilyUnavailable: .temporarilyUnavailable
        @unknown default: .couldNotDetermine
        }
    }
}

extension EnvironmentValues {
    @Entry var accountStatusMonitor = AccountStatusMonitor()
}

/// Reference-type box that holds the in-flight `Task` for
/// `AccountStatusMonitor` and `RemoteChangeMonitor`. Lives outside
/// either class so a `nonisolated let taskHolder` field can be read
/// from `deinit` without re-entering the main actor — the mutable
/// slot is inside a `@unchecked Sendable` class instead of being a
/// mutable stored property on the `@MainActor` enclosing type.
///
/// `@unchecked Sendable` is honest here: the `task` slot is only
/// written from the enclosing class's MainActor-isolated init / setter
/// paths, and only read from `deinit`. There's no concurrent mutation
/// to checked-Sendable away.
final class MutableTaskHolder: @unchecked Sendable {
    var task: Task<Void, Never>?
}
