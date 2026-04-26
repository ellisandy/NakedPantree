import XCTest

final class NakedPantreeUITests: XCTestCase {
    func testAppLaunches() throws {
        let app = XCUIApplication()
        // `EMPTY_STORE=1` skips the production CloudKit container — CI
        // simulators have no iCloud account, so `loadPersistentStores`
        // hangs without it. This is a smoke test for the UI shell, not
        // for CloudKit; sync verification belongs on a real device.
        app.launchEnvironment["EMPTY_STORE"] = "1"
        app.launch()
        // Smart Lists section is always present in the sidebar — see
        // ARCHITECTURE.md §7. "All Items" is the canonical static row;
        // Locations are data-driven and may be empty on first launch.
        XCTAssertTrue(app.staticTexts["All Items"].waitForExistence(timeout: 5))
    }
}
