import XCTest

/// Bug regression: from build #52, opening **Settings → Add Location**
/// briefly presents the `LocationFormView` sheet, which then immediately
/// dismisses on its own and drops the user back to the sidebar. The
/// form never gets a chance to be filled in, so users can't add
/// locations from Settings — the only path to add them after #131
/// moved create/edit/delete out of the sidebar.
///
/// **What this test pins:** after tapping `settings.locations.add`,
/// the New Location form's `staticTexts["New Location"]` (its
/// inline navigation title) must remain visible long enough to type
/// a name. A flake-resistant 3-second observation window catches
/// the auto-dismiss without depending on tap timing.
///
/// `EMPTY_STORE=1` is the same env used by `BootstrapUITests` /
/// `NewItemTabUITests`. Bootstrap seeds Kitchen, but this test
/// doesn't depend on that — it only needs Settings to load and the
/// Locations section to render.
@MainActor
final class AddLocationFromSettingsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAddLocationSheetStaysPresented() throws {
        let app = XCUIApplication()
        app.launchEnvironment["EMPTY_STORE"] = "1"
        app.launch()

        // Wait for bootstrap before navigating into Settings — the
        // Locations section reads from the same household repo and
        // a too-fast tap pre-bootstrap would land on a sheet whose
        // backing data is still nil.
        XCTAssertTrue(
            app.staticTexts["Kitchen"].firstMatch.waitForExistence(timeout: 10),
            "First-launch bootstrap didn't populate the sidebar."
        )

        // Open Settings via the sidebar's gear (`settings.toolbar.entry`).
        // On iPhone this lives in the secondary-action overflow menu;
        // try several heuristics matching the pattern in
        // `SharingUITests.testShareHouseholdSheetPopulatesContent`.
        try openSettings(in: app)

        // Confirm Settings opened by waiting for its household name row.
        XCTAssertTrue(
            app.staticTexts["settings.household.name"].waitForExistence(timeout: 5),
            "Settings sheet didn't show the household-name row."
        )

        let addLocationButton = app.buttons["settings.locations.add"]
        XCTAssertTrue(
            addLocationButton.waitForExistence(timeout: 5),
            "Add Location row missing from the Settings Locations section."
        )
        addLocationButton.tap()

        // The form's inline navigation title is "New Location" on
        // `.create` mode. Wait for it to appear — that's the
        // happy-path "form did present" signal.
        let formTitle = app.staticTexts["New Location"]
        XCTAssertTrue(
            formTitle.waitForExistence(timeout: 5),
            "New Location form didn't appear after tapping Add Location."
        )

        // The bug: form appears for a moment, then auto-dismisses.
        // Observe the title for 3 seconds — if the form genuinely
        // stayed presented this is a no-op; if the form dismisses
        // mid-window, `formTitle.exists` flips false and the
        // assertion fails with the regression message.
        let stillPresented = waitForElementToRemain(
            element: formTitle,
            forSeconds: 3
        )
        XCTAssertTrue(
            stillPresented,
            "New Location form auto-dismissed within 3 seconds — Settings → Add Location regression."
        )
    }

    /// Polls `element.exists` every 0.25s for `forSeconds`. Returns
    /// `false` the first time the element is gone — that's the
    /// auto-dismiss signature. Returns `true` if the element stays
    /// reachable through the entire window.
    private func waitForElementToRemain(
        element: XCUIElement,
        forSeconds seconds: TimeInterval
    ) -> Bool {
        let pollInterval: TimeInterval = 0.25
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if !element.exists {
                return false
            }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        return element.exists
    }

    /// Reaches the gear button across iPhone / iPad layouts. Mirrors
    /// the heuristic in `SharingUITests` — try the identifier
    /// directly, then the localized "Settings" label, then the
    /// overflow-menu candidates that iPhone uses to collapse
    /// secondary toolbar actions.
    private func openSettings(in app: XCUIApplication) throws {
        let direct = app.buttons["settings.toolbar.entry"]
        if direct.waitForExistence(timeout: 2) {
            direct.tap()
            return
        }
        let byLabel = app.buttons["Settings"]
        if byLabel.waitForExistence(timeout: 1) {
            byLabel.tap()
            return
        }
        for candidate in ["More", "…", "More Options"] {
            let button = app.buttons[candidate]
            if button.waitForExistence(timeout: 1) {
                button.tap()
                break
            }
        }
        if direct.waitForExistence(timeout: 5) {
            direct.tap()
            return
        }
        if byLabel.waitForExistence(timeout: 1) {
            byLabel.tap()
            return
        }
        XCTFail("Settings entry unreachable from current accessibility hierarchy.")
    }
}
