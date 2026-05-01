import NakedPantreeDomain
import SwiftUI

/// Issue #155 — `EnvironmentValues` entries for the Reminders
/// integration. The binding type is the protocol (`any RemindersService`)
/// so consumers don't transitively pull in EventKit; the production
/// branch in `LiveDependencies` builds an `EventKitRemindersService`
/// and assigns it to this slot.
///
/// Default value is `InMemoryRemindersService()` — same shape as
/// `Repositories.makePreview()`. `#Preview` blocks render without
/// setup; `LiveDependencies.makeProduction*` overrides on launch
/// for the real builds.
extension EnvironmentValues {
    @Entry var remindersService: any RemindersService = InMemoryRemindersService()
}
