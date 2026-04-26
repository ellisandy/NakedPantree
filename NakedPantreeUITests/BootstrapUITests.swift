import XCTest

/// Regression coverage for the first-launch bootstrap race: on a fresh
/// store the default `Kitchen` location must appear in the sidebar
/// before the user has a chance to tap anything.
///
/// Pre-fix, `RootView` ran bootstrap inside `.task` while
/// `SidebarView`'s `.task` ran concurrently — the empty-fetch raced
/// the bootstrap insert and won, so the sidebar's Locations section
/// stayed empty until the user manually triggered a refresh.
final class BootstrapUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFirstLaunchShowsKitchen() throws {
        let app = XCUIApplication()
        // `EMPTY_STORE=1` swaps the Core Data stack for empty in-memory
        // repos, so the bootstrap flow runs every time the test launches
        // — independent of whatever the simulator's Application Support
        // directory carries from a previous run.
        app.launchEnvironment["EMPTY_STORE"] = "1"
        app.launch()
        XCTAssertTrue(
            app.staticTexts["Kitchen"].firstMatch.waitForExistence(timeout: 5),
            "Kitchen location didn't appear in the sidebar after first-launch bootstrap."
        )
    }
}
