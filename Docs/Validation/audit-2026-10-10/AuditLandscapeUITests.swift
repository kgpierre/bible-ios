import XCTest

/// Compare full-device and application captures after an actual simulator rotation.
final class AuditLandscapeUITests: XCTestCase {
    @MainActor func testLandscapeDeviceCapture() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["BIBLE_TEST_STORE"] = UUID().uuidString
        app.launchEnvironment["BIBLE_TEST_CHAPTER"] = "JHN:3"
        app.launch()
        XCTAssertTrue(app.textViews["chapterText"].waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        app.buttons["appearanceButton"].tap()
        app.descendants(matching: .any)["pageLayoutPicker"].tap()
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND elementType IN %@", "Two Pages", [XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.menuItem.rawValue])).firstMatch.tap()
        app.buttons["appearanceDoneButton"].tap()
        XCTAssertTrue(app.textViews["spreadPageLeft"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textViews["spreadPageRight"].exists)
        for (name, screenshot) in [("Full device landscape", XCUIScreen.main.screenshot()), ("App landscape", app.screenshot())] {
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        }
        let left = app.textViews["spreadPageLeft"].frame
        let right = app.textViews["spreadPageRight"].frame
        let frames = XCTAttachment(string: "app=\(app.frame) window=\(app.windows.firstMatch.frame) left=\(left) right=\(right)")
        frames.name = "Landscape frames"; frames.lifetime = .keepAlways; add(frames)
    }
}
