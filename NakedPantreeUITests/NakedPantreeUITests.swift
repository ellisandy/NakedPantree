import XCTest

final class NakedPantreeUITests: XCTestCase {
    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launch()
        // Smart Lists section is always present in the sidebar — see
        // ARCHITECTURE.md §7. "All Items" is the canonical static row;
        // Locations are data-driven and may be empty on first launch.
        XCTAssertTrue(app.staticTexts["All Items"].waitForExistence(timeout: 5))
    }
}
