import XCTest

/// Issue #132: regression coverage for the sidebar plus button being
/// repurposed from "New Location" to "New Item." Pre-#131/#132 the
/// `+` opened the location form, which beta testers consistently
/// misread.
///
/// **What this test pins:** with the bootstrap-seeded Kitchen as the
/// only location, tapping the sidebar `+` skips the multi-location
/// picker and opens `ItemFormView` directly in `.create` mode (the
/// 1-location branch of `SidebarView.handleNewItemTap()`). The
/// 0-location and 2+-location branches are plain switch logic that
/// reads straight off `locations.count`; they don't need their own
/// XCUITest coverage to be trusted.
///
/// `EMPTY_STORE=1` is the same launch environment `BootstrapUITests`
/// uses — bootstrap seeds Kitchen and the test runs against an
/// in-memory repo instead of whatever Application Support carries.
@MainActor
final class NewItemTabUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTappingPlusWithSingleLocationOpensItemForm() throws {
        let app = XCUIApplication()
        app.launchEnvironment["EMPTY_STORE"] = "1"
        app.launch()

        // Wait for bootstrap to populate the sidebar before tapping —
        // a fast-finger tap before bootstrap finishes would land on
        // the zero-locations alert (the "no locations yet" branch),
        // not the form.
        XCTAssertTrue(
            app.staticTexts["Kitchen"].firstMatch.waitForExistence(timeout: 10),
            "Kitchen didn't populate before plus-button tap — bootstrap still in flight."
        )

        // The primary toolbar action stays directly visible on iPhone
        // (only secondary actions collapse into the overflow "More"
        // menu), so this lookup doesn't need the overflow-menu dance
        // that `SharingUITests` has to do for the gear.
        let newItemButton = app.buttons["sidebar.newItem"]
        XCTAssertTrue(
            newItemButton.waitForExistence(timeout: 5),
            "sidebar.newItem button is missing — toolbar wiring may have regressed."
        )
        newItemButton.tap()

        // The form opens with `New Item` as its inline navigation
        // title — the form has no other accessibility identifiers
        // today and `staticTexts["New Item"]` matches the title text.
        XCTAssertTrue(
            app.staticTexts["New Item"].waitForExistence(timeout: 5),
            "New Item form didn't appear after plus-button tap on a 1-location household."
        )
    }
}
