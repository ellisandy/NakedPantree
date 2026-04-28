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
        // `defer` so the screenshot is captured even when the
        // assertions below time out — see the "screenshot is the
        // deliverable" note in `MARK: - Helpers`.
        defer { attach(name: "01-sidebar") }
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
        defer { attach(name: "02-all-items") }
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
        defer { attach(name: "03-location-fridge") }
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
        defer { attach(name: "04-item-detail") }
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
    // Screenshot-vs-assertion split: the deliverable is the screenshot
    // attachment, which fires from `defer` blocks at the top of each
    // test method and is committed to the xcresult before the
    // assertions below run. The assertions are a regression signal
    // only — when they fail (typically the iPad sim's a11y query
    // ceiling, see the `bootstrapTimeout` note) the screenshot still
    // ships. The workflow's `Capture snapshots` step is marked
    // `continue-on-error: true` and the extract / upload steps run
    // `if: always()` for the same reason.

    /// Tolerance for the structural wait — the iPad simulator on the
    /// `macos-26` GitHub Actions runner spends ~33s in
    /// "Setting up automation session" before the app's first frame
    /// renders. 60s gives headroom over that floor on iPhone-class
    /// destinations (which resolve in <2s typically). On iPad this
    /// often hits the framework's ~30s a11y-query ceiling instead —
    /// the failure is recorded as a regression signal but doesn't
    /// block the screenshot deliverable.
    private var bootstrapTimeout: TimeInterval { 60 }

    /// Tolerance for the data wait once the structural element is up.
    /// 10s is well past comfortable for an in-memory fetch.
    private var dataTimeout: TimeInterval { 10 }

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
