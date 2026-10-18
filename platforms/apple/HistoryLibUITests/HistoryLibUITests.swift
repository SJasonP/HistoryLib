import XCTest

/// Run on Duo in both closed and open poses, plus a conventional iPhone/iPad.
@MainActor
final class HistoryLibUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp(tab: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HISTORYLIB_UI_TESTING"] = "1"
        app.launchArguments = [
            "-enable_icloud_sync", "NO", "-show_site_icons", "NO",
            "-last_selected_tab", tab, "-AppleLanguages", "(en)",
            "-persistence_launch_icloud_enabled", "NO",
            "-AppleLocale", "en_US", "-show_direct_search_results_on_iphone", "YES",
        ]
        app.launch()
        return app
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSearchSurvivesRotation() throws {
        let app = launchApp(tab: "library")
        let field = app.searchFields.firstMatch
        if !field.exists {
            app.buttons["Search"].firstMatch.tap()
        }
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        field.tap()
        field.typeText("Adaptive")
        let record = app.staticTexts["Adaptive layout record 11"]
        XCTAssertTrue(record.waitForExistence(timeout: 10), app.debugDescription)
        capture("search-before-resize")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Adaptive")
        capture("search-landscape")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Adaptive")
    }

    func testExportPasswordSurvivesRotation() throws {
        let app = launchApp(tab: "manage")
        let field = app.secureTextFields["Password (Optional)"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        field.tap()
        field.typeText("synthetic-layout-password")
        let confirmation = app.secureTextFields["Confirm Password"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        let passwordValue = field.value as? String
        XCTAssertNotEqual(passwordValue, "Password (Optional)")
        capture("export-before-resize")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, passwordValue)
        capture("export-landscape")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
    }

    func testLibraryNavigationSurvivesRotation() throws {
        let app = launchApp(tab: "library")
        let year = app.buttons.containing(.staticText, identifier: "2026").firstMatch
        XCTAssertTrue(year.waitForExistence(timeout: 10), app.debugDescription)
        year.tap()
        capture("library-before-resize")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.staticTexts["2026"].firstMatch.waitForExistence(timeout: 5))
        capture("library-landscape")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.staticTexts["2026"].firstMatch.waitForExistence(timeout: 5))
    }
}
