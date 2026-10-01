import XCTest

final class LumaUITests: XCTestCase {
    @MainActor
    func testNavigationAndGlassScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Weniger Lärm.\nMehr Lieblingsvideos."].waitForExistence(timeout: 15))
        screenshot("01-Entdecken")
        app.tabBars.buttons["Suchen"].tap()
        XCTAssertTrue(app.staticTexts["Was inspiriert dich?"].waitForExistence(timeout: 5))
        screenshot("02-Suchen")
        app.tabBars.buttons["Abos"].tap()
        XCTAssertTrue(app.buttons["Konto verbinden"].waitForExistence(timeout: 5))
        screenshot("03-Abos")
        app.tabBars.buttons["Mediathek"].tap()
        XCTAssertTrue(app.staticTexts["Lokal gemerkt"].waitForExistence(timeout: 5))
        screenshot("04-Mediathek")
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.buttons["connectAccountButton"].waitForExistence(timeout: 5))
        screenshot("05-Einstellungen")
    }
    @MainActor
    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
