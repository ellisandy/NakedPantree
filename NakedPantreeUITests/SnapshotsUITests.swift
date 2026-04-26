import XCTest

/// Captures App Store / TestFlight screenshots from the seeded
/// snapshot fixture data (`SnapshotFixtures.makeSeededRepositories`).
///
/// Each test launches the app with `SNAPSHOT_MODE=1` plus optional
/// `SNAPSHOT_SIDEBAR` / `SNAPSHOT_ITEM` env vars that route the app
/// straight to the surface we want to capture — no UI taps, which keeps
/// these reliable across iPhone (compact) and iPad (regular) size
/// classes. `RootView` reads those env vars on first appear.
///
/// PNGs are attached via `XCUIScreen.main.screenshot()` +
/// `XCTAttachment(lifetime: .keepAlways)` so they survive in the
/// xcresult bundle. `scripts/extract-screenshots.sh` extracts them
/// into a Fastlane-shaped `screenshots/<locale>/<device>/` tree.
///
/// Run via:
///
///     xcodebuild test \
///       -project NakedPantree.xcodeproj \
///       -scheme NakedPantree \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=latest' \
///       -only-testing:NakedPantreeUITests/SnapshotsUITests \
///       -resultBundlePath Snapshots.xcresult
///
/// See [issue #12](https://github.com/ellisandy/NakedPantree/issues/12)
/// for the larger pipeline this slots into.
final class SnapshotsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSidebar() throws {
        let app = launch(env: ["SNAPSHOT_MODE": "1"])
        XCTAssertTrue(
            app.staticTexts["All Items"].firstMatch.waitForExistence(timeout: 5),
            "Sidebar didn't render — snapshot fixtures may not be seeded."
        )
        attach(name: "01-sidebar")
    }

    func testAllItems() throws {
        let app = launch(env: [
            "SNAPSHOT_MODE": "1",
            "SNAPSHOT_SIDEBAR": "smartList:allItems",
        ])
        XCTAssertTrue(
            app.staticTexts["Olive oil"].firstMatch.waitForExistence(timeout: 5),
            "All Items list didn't show fixture content."
        )
        attach(name: "02-all-items")
    }

    func testFridgeLocation() throws {
        let app = launch(env: [
            "SNAPSHOT_MODE": "1",
            "SNAPSHOT_SIDEBAR": "location:Fridge",
        ])
        XCTAssertTrue(
            app.staticTexts["Whole milk"].firstMatch.waitForExistence(timeout: 5),
            "Fridge contents didn't render."
        )
        attach(name: "03-location-fridge")
    }

    func testItemDetail() throws {
        let app = launch(env: [
            "SNAPSHOT_MODE": "1",
            "SNAPSHOT_SIDEBAR": "location:Fridge",
            "SNAPSHOT_ITEM": "Whole milk",
        ])
        XCTAssertTrue(
            app.staticTexts["Quantity"].firstMatch.waitForExistence(timeout: 5),
            "Item detail didn't render."
        )
        attach(name: "04-item-detail")
    }

    // MARK: - Helpers

    private func launch(env: [String: String]) -> XCUIApplication {
        let app = XCUIApplication()
        for (key, value) in env {
            app.launchEnvironment[key] = value
        }
        app.launch()
        return app
    }

    /// Attaches a screenshot of the current screen with `keepAlways`
    /// lifetime so it survives in the xcresult bundle even on green
    /// runs (default attachment lifetime is `deleteOnSuccess`).
    private func attach(name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
