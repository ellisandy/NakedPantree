import Foundation
import Testing
@testable import NakedPantree

@Suite("AccountStatus banner copy")
struct AccountStatusTests {
    @Test(".available has no banner message")
    func availableSuppressesBanner() {
        #expect(AccountStatus.available.message == nil)
    }

    @Test("Each non-available status has a non-empty plain-text message")
    func nonAvailableHaveMessages() {
        for status: AccountStatus in [
            .noAccount,
            .restricted,
            .couldNotDetermine,
            .temporarilyUnavailable,
        ] {
            let message = status.message
            #expect(message != nil, "\(status) should surface a banner message.")
            if let message {
                // Voice rule §10: useful + short. Bound on the upper end —
                // banner runs single-line on iPhone in landscape with
                // generous DynamicType, so ~120 chars is the practical
                // ceiling before truncation.
                #expect(!message.isEmpty)
                #expect(message.count < 120, "\(status) message is too long: \(message)")
            }
        }
    }

    @Test("Sync-failure copy stays plain — no off-limits humor")
    func messagesAvoidPersonality() throws {
        // Voice rule §9: errors that block the user are off-limits for
        // personality. Spot-check obvious offenders so a future tweak
        // doesn't accidentally drop a joke into a sync-failure banner.
        let bannedSubstrings = ["pants", "naked", "🥫", "🧊", "😉"]
        for status: AccountStatus in [
            .noAccount,
            .restricted,
            .couldNotDetermine,
            .temporarilyUnavailable,
        ] {
            let lowered = (status.message ?? "").lowercased()
            for banned in bannedSubstrings {
                #expect(
                    !lowered.contains(banned),
                    "\(status) message contains off-limits substring \"\(banned)\"."
                )
            }
        }
    }
}
