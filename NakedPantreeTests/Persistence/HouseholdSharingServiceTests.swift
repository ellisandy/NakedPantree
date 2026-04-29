import Foundation
import Testing

@testable import NakedPantreePersistence

/// Unit-level coverage for the share-preparation path. Phase 3 sharing
/// shipped without any automated coverage — see `SharingUITests` for
/// the UI-level smoke test, and `StubHouseholdSharingServiceTests` for
/// the stub coverage.
///
/// **Why this file is intentionally light:** the lookup branch of
/// `CloudHouseholdSharingService.prepareShare` calls
/// `NSPersistentCloudKitContainer.performBackgroundTask` which on a
/// `CODE_SIGNING_ALLOWED=NO` simulator binary (the CI configuration)
/// hangs the test runner — confirmed by the apps#98 diagnostic run,
/// which produced `[CK] Significant issue ... missing entitlement`
/// followed by "Restarting after unexpected exit, crash, or test
/// timeout." The ~28-second hang is correlated with CloudKit pre-flight
/// against a binary lacking `com.apple.developer.icloud-services`.
///
/// Reinstating the lookup test requires either: (a) refactoring
/// `CloudHouseholdSharingService.init` to take `NSPersistentContainer`
/// (parent class) and downcast at the CK call sites, or (b) running the
/// test against a code-signed simulator binary in CI. Tracked as a
/// follow-up to #90 — for now, the conformance check below + the
/// UI test in `SharingUITests` + the stub tests cover the realistic
/// surface.
@Suite("Household sharing service")
struct HouseholdSharingServiceTests {
    @Test("CloudHouseholdSharingService conforms to HouseholdSharingService")
    func conformance() throws {
        // No need to load a real container — this test is purely a
        // compile-time assertion that the protocol seam holds.
        // Constructing the class would trigger the simulator hang
        // described in the file-level comment, even without exercising
        // any methods.
        func acceptsServiceProtocol(_ service: any HouseholdSharingService) {}
        // We can't instantiate `CloudHouseholdSharingService` without
        // a real container — but if the type doesn't conform to
        // `HouseholdSharingService`, this expression won't compile.
        let metatype: any HouseholdSharingService.Type = CloudHouseholdSharingService.self
        _ = metatype
        _ = acceptsServiceProtocol
    }
}
