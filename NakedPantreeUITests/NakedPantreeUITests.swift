import XCTest

final class NakedPantreeUITests: XCTestCase {
    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Naked Pantree"].waitForExistence(timeout: 5))
    }
}
