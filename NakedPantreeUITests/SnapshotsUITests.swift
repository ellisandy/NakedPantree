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
        settle()
        attach(name: "01-sidebar")
        // testSidebar leaves `sidebarSelection` nil. On iPhone the
        // sidebar is the front column; on iPad it's the left column.
        // Either way the sidebar's nav-bar identifier is "Naked Pantree"
        // — see RootView's `navigationTitle("Naked Pantree")` on the
        // sidebar selection-nil path.
        waitForColumn(app, navbar: "Naked Pantree")
        XCTAssertTrue(
            app.staticTexts["All Items"].firstMatch.waitForExistence(timeout: dataTimeout),
            "Sidebar didn't render — snapshot fixtures may not be seeded."
        )
    }

    func testAllItems() throws {
        let app = launch(env: [
            "SNAPSHOT_MODE": "1",
            "SNAPSHOT_SIDEBAR": "smartList:allItems",
        ])
        settle()
        attach(name: "02-all-items")
        waitForColumn(app, navbar: "All Items")
        XCTAssertTrue(
            app.staticTexts["Olive oil"].firstMatch.waitForExistence(timeout: dataTimeout),
            "All Items list didn't show fixture content."
        )
    }

    func testFridgeLocation() throws {
        let app = launch(env: [
            "SNAPSHOT_MODE": "1",
            "SNAPSHOT_SIDEBAR": "location:Fridge",
        ])
        settle()
        attach(name: "03-location-fridge")
        waitForColumn(app, navbar: "Fridge")
        XCTAssertTrue(
            app.staticTexts["Whole milk"].firstMatch.waitForExistence(timeout: dataTimeout),
            "Fridge contents didn't render."
        )
    }

    func testItemDetail() throws {
        let app = launch(env: [
            "SNAPSHOT_MODE": "1",
            "SNAPSHOT_SIDEBAR": "location:Fridge",
            "SNAPSHOT_ITEM": "Whole milk",
        ])
        settle()
        attach(name: "04-item-detail")
        // Detail column's nav-bar is the item name once routing has
        // landed. Waiting on it (rather than the content column's
        // "Fridge" navbar) ensures both the content selection AND the
        // detail selection have been applied before we look for
        // "Quantity".
        waitForColumn(app, navbar: "Whole milk")
        XCTAssertTrue(
            app.staticTexts["Quantity"].firstMatch.waitForExistence(timeout: dataTimeout),
            "Item detail didn't render."
        )
    }

    // MARK: - Helpers
    //
    // Order-of-operations: launch, settle, **attach (deliverable),**
    // assert (regression signal). The deliverable comes before any
    // XCUITest query because XCUITest's "Failed to get matching
    // snapshots" error on iPad raises through Swift's `defer`
    // (NSException → not catchable from Swift), which is why the
    // earlier defer-based pattern lost two of four iPad PNGs in
    // run #25027159236. Capturing the screenshot before any query
    // makes the deliverable independent of XCUITest query
    // reliability.
    //
    // The workflow's `Capture snapshots` step still runs
    // `continue-on-error: true` so a failed assertion doesn't block
    // the artifact upload, but with this order the upload would land
    // even without that gate — they're complementary belts.

    /// Tolerance for the structural wait. iPad CI has occasionally
    /// hit the framework's ~30s a11y-query ceiling (a separate,
    /// XCUITest-internal timeout we can't extend) — when that
    /// happens the assertion red-marks but the screenshot has
    /// already been captured.
    private var bootstrapTimeout: TimeInterval { 60 }

    /// Tolerance for the data wait once the structural element is up.
    /// 10s is well past comfortable for an in-memory fetch.
    private var dataTimeout: TimeInterval { 10 }

    /// How long to wait between `app.launch()` returning and
    /// capturing the screenshot. Empirically, the iPad sim on
    /// `macos-26` runners needs ~30–35s after launch before the
    /// content / detail columns finish their first render — the
    /// `Wait for ... to idle` reading from XCUITest's automation
    /// session is too optimistic in practice (it fires while
    /// SwiftUI's first body pass is still running). 45s provides
    /// margin over that floor. iPhone runs eat the same delay
    /// — acceptable since this workflow is manually triggered and
    /// the deliverable is the screenshot, not throughput.
    private var settleDuration: TimeInterval { 45 }

    /// Pure `Thread.sleep` settle — deliberately not a
    /// `waitForExistence` poll, since query-based waits are the
    /// thing that raises through defer on iPad. Sleeping is the
    /// cheapest reliable way to give the simulator time to render
    /// before the screenshot capture.
    private func settle() {
        Thread.sleep(forTimeInterval: settleDuration)
    }

    private func launch(env: [String: String]) -> XCUIApplication {
        let app = XCUIApplication()
        for (key, value) in env {
            app.launchEnvironment[key] = value
        }
        app.launch()
        return app
    }

    /// Phase-1 wait: blocks until the requested column's
    /// `NavigationBar` exists in the accessibility tree. Acts as a
    /// proxy for "bootstrap is past `LaunchView` and the
    /// `NavigationSplitView` column has rendered". Failures here
    /// indicate a structural problem (env vars not picked up,
    /// bootstrap stuck, column not routing) — distinct from the
    /// downstream data-row check, which surfaces a fixture / load
    /// regression.
    private func waitForColumn(
        _ app: XCUIApplication,
        navbar identifier: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            app.navigationBars[identifier].firstMatch.waitForExistence(
                timeout: bootstrapTimeout
            ),
            """
            Navigation bar '\(identifier)' didn't appear within \
            \(Int(bootstrapTimeout))s — app didn't reach the expected \
            column. Bootstrap may be stuck, or the snapshot env vars \
            may not be routing.
            """,
            file: file,
            line: line
        )
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
