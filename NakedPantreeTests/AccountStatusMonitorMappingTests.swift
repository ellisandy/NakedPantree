import CloudKit
import Foundation
import Testing

@testable import NakedPantree

/// Coverage for `AccountStatusMonitor.map(_:)` — the pure
/// `CKAccountStatus → AccountStatus` mapping that drives the iCloud
/// banner and the Share Household button visibility. Issue #112.
///
/// This is a static function with no side effects, so a regression
/// here would silently misclassify the user's iCloud state — a
/// no-account user could see no banner, or an available user could
/// see a "couldn't reach iCloud" banner. Pinned by case so any future
/// edit produces an explicit test failure.
@Suite("AccountStatusMonitor mapping")
struct AccountStatusMonitorMappingTests {
    @Test("CKAccountStatus.available maps to .available")
    func availableMapsToAvailable() {
        #expect(AccountStatusMonitor.map(.available) == .available)
    }

    @Test("CKAccountStatus.noAccount maps to .noAccount")
    func noAccountMapsToNoAccount() {
        #expect(AccountStatusMonitor.map(.noAccount) == .noAccount)
    }

    @Test("CKAccountStatus.restricted maps to .restricted")
    func restrictedMapsToRestricted() {
        #expect(AccountStatusMonitor.map(.restricted) == .restricted)
    }

    @Test("CKAccountStatus.couldNotDetermine maps to .couldNotDetermine")
    func couldNotDetermineMapsToCouldNotDetermine() {
        #expect(AccountStatusMonitor.map(.couldNotDetermine) == .couldNotDetermine)
    }

    @Test("CKAccountStatus.temporarilyUnavailable maps to .temporarilyUnavailable")
    func temporarilyUnavailableMapsToTemporarilyUnavailable() {
        #expect(AccountStatusMonitor.map(.temporarilyUnavailable) == .temporarilyUnavailable)
    }

    @Test("Every AccountStatus has a deterministic round-trip mapping")
    func everyCaseRoundTrips() {
        // Sanity check covering the @unknown default — if Apple adds a
        // new CKAccountStatus case, the switch must explicitly handle
        // it. The current default falls through to .couldNotDetermine.
        // We can't construct an unknown case in test (the enum is
        // closed at compile time for known values), but this loop
        // pins the behavior for every known case in one place.
        let cases: [(CKAccountStatus, AccountStatus)] = [
            (.available, .available),
            (.noAccount, .noAccount),
            (.restricted, .restricted),
            (.couldNotDetermine, .couldNotDetermine),
            (.temporarilyUnavailable, .temporarilyUnavailable),
        ]
        for (raw, expected) in cases {
            #expect(
                AccountStatusMonitor.map(raw) == expected,
                "CKAccountStatus(\(raw)) should map to AccountStatus.\(expected)"
            )
        }
    }
}
