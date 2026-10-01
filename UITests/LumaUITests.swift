import XCTest

final class LumaUITests: XCTestCase {
    @MainActor
    func testPlayerUsesFullWidthAtTopAndStaysFixedWhileScrolling() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Ein neuer Blick auf die Welt")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        card.tap()
        let surface = app.otherElements["playerSurface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 10))
        let frame = surface.frame
        XCTAssertEqual(frame.minX, 0, accuracy: 1)
        XCTAssertEqual(frame.maxX, app.frame.width, accuracy: 1)
        XCTAssertEqual(frame.minY, 0, accuracy: 1)
        app.scrollViews["playerDetailsScroll"].swipeUp()
        XCTAssertEqual(surface.frame.minY, frame.minY, accuracy: 1)
        screenshot("06-Player")
        app.buttons["minimizePlayerButton"].tap()
        XCTAssertTrue(app.tabBars.buttons["Entdecken"].waitForExistence(timeout: 5))
    }

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
