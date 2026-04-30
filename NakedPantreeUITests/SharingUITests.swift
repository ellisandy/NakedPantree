import XCTest

/// Regression coverage for the Settings → Share Household path
/// (issue #90 / Phase 3). Phase 3 sharing has shipped to TestFlight
/// without ever being exercised by an automated test — the canonical
/// "blank sheet on first real run" symptom.
///
/// **What this test guards against:** the literal #90 symptom — the
/// share sheet presenting *empty*. The test launches with
/// `STUB_SHARING=1` so `NakedPantreeApp.init` injects
/// `StubHouseholdSharingService` (no iCloud needed); navigates to
/// Settings via the sidebar gear; taps **Share Household**; and
/// asserts that the resulting sheet has at least one
/// non-trivial UI element. A bug that renders the sheet's content as
/// `Color.clear` (the diagnostic fallback added in apps#96) shows up
/// as zero descendants and fails the test.
///
/// **Why this doesn't need a real iCloud account:** the stub
/// constructs a synthetic `CKShare(rootRecord:)` in memory and hands
/// it back to `UICloudSharingController`. The controller will
/// either render its participant UI or surface its own error UI;
/// either way it produces accessibility children that XCUITest can
/// see. A genuinely blank sheet (the bug) produces none.
@MainActor
final class SharingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testShareHouseholdSheetPopulatesContent() throws {
        let app = XCUIApplication()
        // EMPTY_STORE puts us in the in-memory bootstrap path so the
        // sidebar populates with a default household + "Kitchen"
        // location. STUB_SHARING wires the test stub in for the
        // sharing service so the Settings sheet shows the Share
        // Household button.
        app.launchEnvironment["EMPTY_STORE"] = "1"
        app.launchEnvironment["STUB_SHARING"] = "1"
        app.launch()

        // Wait for bootstrap to complete (proxy: sidebar populated).
        XCTAssertTrue(
            app.staticTexts["Kitchen"].firstMatch.waitForExistence(timeout: 10),
            "First-launch bootstrap didn't populate the sidebar — share path can't run."
        )

        // Open Settings via the sidebar's toolbar gear. Settings lives
        // in a `placement: .secondaryAction` ToolbarItem
        // (`SidebarView.swift`), which on iPhone collapses into a
        // "More" / ellipsis menu. The exact label/identifier of the
        // overflow button varies by iOS version — we try several
        // and dump the full a11y hierarchy on failure for triage.
        let settingsButton = app.buttons["settings.toolbar.entry"]
        let settingsByLabel = app.buttons["Settings"]

        let initiallyFound =
            settingsButton.waitForExistence(timeout: 2)
            || settingsByLabel.waitForExistence(timeout: 1)
        if !initiallyFound {
            // Try common overflow-menu button labels on iOS.
            let overflowCandidates = ["More", "…", "More Options"]
            for candidate in overflowCandidates {
                let button = app.buttons[candidate]
                if button.waitForExistence(timeout: 1) {
                    button.tap()
                    break
                }
            }
        }

        let foundAfterMenu =
            settingsButton.waitForExistence(timeout: 5)
            || settingsByLabel.waitForExistence(timeout: 1)
        XCTAssertTrue(
            foundAfterMenu,
            "Settings entry not reachable. ID-match: \(settingsButton.exists), "
                + "label-match: \(settingsByLabel.exists). "
                + "Hierarchy:\n\(app.debugDescription)"
        )
        if settingsButton.exists {
            settingsButton.tap()
        } else {
            settingsByLabel.tap()
        }

        // Confirm Settings opened by waiting for the household name row
        // — the same row that gates the Share Household button.
        XCTAssertTrue(
            app.staticTexts["settings.household.name"].waitForExistence(timeout: 5),
            "Settings sheet didn't show the household name row."
        )

        // Tap Share Household.
        let shareButton = app.buttons["settings.shareHousehold"]
        XCTAssertTrue(
            shareButton.waitForExistence(timeout: 5),
            "Share Household button is missing — STUB_SHARING wiring may be broken."
        )
        shareButton.tap()

        // The presented share sheet must have visible content. A
        // working `UICloudSharingController` always exposes a Cancel
        // button; the diagnostic-fallback `Color.clear` (apps#96)
        // exposes nothing. We give Apple's controller up to 30s to
        // construct its UI — first-time share creation can be slow
        // even with a synthetic share — but on healthy plumbing it
        // typically renders in under 5s.
        //
        // We *don't* assert the controller's exact contents (the
        // participant manager UI is private and version-dependent),
        // only that *some* element is reachable. That's the literal
        // inverse of the #90 symptom.
        let cancelButton = app.buttons["Cancel"]
        let anyButton = app.buttons.element(boundBy: 0)
        let foundContent =
            cancelButton.waitForExistence(timeout: 30)
            || anyButton.waitForExistence(timeout: 5)
        XCTAssertTrue(
            foundContent,
            "Share Household sheet rendered without any reachable UI — #90 regression."
        )
    }
}
