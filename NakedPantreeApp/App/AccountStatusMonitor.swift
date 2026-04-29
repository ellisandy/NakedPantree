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

    nonisolated(unsafe) private var task: Task<Void, Never>?

    /// No-op monitor for previews and tests. Status stays `.available`
    /// so the banner is hidden. `nonisolated` so the `@Entry` default
    /// can construct one outside any actor.
    nonisolated init() {}

    init(container: CKContainer) {
        let stream = NotificationCenter.default.notifications(named: .CKAccountChanged)
        task = Task { @MainActor [weak self] in
            await self?.refresh(using: container)
            for await _ in stream {
                await self?.refresh(using: container)
            }
        }
    }

    deinit {
        task?.cancel()
    }

    private func refresh(using container: CKContainer) async {
        do {
            let raw = try await container.accountStatus()
            status = Self.map(raw)
        } catch {
            status = .couldNotDetermine
        }
    }

    /// `internal` (not `private`) so `AccountStatusMonitorMappingTests`
    /// can pin every `CKAccountStatus → AccountStatus` case directly
    /// (issue #112). Pure function with no dependencies; opening it
    /// up costs nothing at the type's usage surface.
    static func map(_ raw: CKAccountStatus) -> AccountStatus {
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
