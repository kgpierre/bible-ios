// Audit-only system photo-picker smoke test. Not part of the shipping test target.
// Uses the stock landscape photos installed in this simulator and a fresh UUID store.
import XCTest

final class AuditPhotoUITests: XCTestCase {
    @MainActor func testAboutCreditAndNoticesOnMinimumOS() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["BIBLE_TEST_STORE"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.textViews["chapterText"].waitForExistence(timeout: 10))
        app.buttons["More"].tap()
        app.buttons["About Bible"].tap()
        let credit = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Kyle Pierre")).firstMatch
        XCTAssertTrue(credit.waitForExistence(timeout: 5))
        let notice = app.buttons["Edition Notice"]
        for _ in 0..<3 where !notice.isHittable { app.swipeUp() }
        notice.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Crosswire Bible Society")).firstMatch.waitForExistence(timeout: 5))
        app.navigationBars["Edition Notice"].buttons.element(boundBy: 0).tap()
        app.buttons["aboutCloseButton"].tap()
        XCTAssertTrue(app.textViews["chapterText"].waitForExistence(timeout: 5))
    }

    @MainActor func testPhotoCardSaveAndReopen() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["BIBLE_TEST_STORE"] = UUID().uuidString
        app.launchEnvironment["BIBLE_TEST_CHAPTER"] = "JHN:3"
        app.launch()
        XCTAssertTrue(app.textViews["chapterText"].waitForExistence(timeout: 10))
        app.buttons["More"].tap()
        app.buttons["Save Chapter"].tap()
        app.buttons["destination-saved"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "savedItem-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.press(forDuration: 1)
        app.buttons["Make Widget"].tap()
        let photo = app.buttons["cardPhotoButton"]
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        for _ in 0..<3 where !photo.isHittable { app.swipeUp() }
        photo.tap()
        // The out-of-process picker is absent from the app's AX hierarchy. The first-row
        // middle stock photo was observed at this normalized point in the picker screenshot.
        let picker = expectation(for: NSPredicate { _, _ in !photo.isHittable }, evaluatedWith: nil)
        wait(for: [picker], timeout: 10)
        XCTAssertTrue(app.buttons["Photos"].waitForExistence(timeout: 20), "Wait for the system picker grid to finish loading")
        let pickerCapture = XCTAttachment(screenshot: app.screenshot())
        pickerCapture.name = "System photo picker"; pickerCapture.lifetime = .keepAlways; add(pickerCapture)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.43)).tap()
        let save = app.buttons["cardSaveButton"]
        let ready = expectation(for: NSPredicate { _, _ in save.isHittable && save.isEnabled && !app.buttons["cardPreset-paper"].isSelected }, evaluatedWith: nil)
        wait(for: [ready], timeout: 15)
        let preview = XCTAttachment(screenshot: app.screenshot())
        preview.name = "Photo card preview"; preview.lifetime = .keepAlways; add(preview)
        save.tap()
        app.buttons["savedWidgets"].tap()
        let card = app.buttons["card-John 3"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.buttons["cardPreset-paper"].waitForExistence(timeout: 5))
        for preset in ["paper", "evening", "sage", "dawn", "ink", "rose"] {
            XCTAssertFalse(app.buttons["cardPreset-" + preset].isSelected)
        }
        let reopened = XCTAttachment(screenshot: app.screenshot())
        reopened.name = "Photo card reopened"; reopened.lifetime = .keepAlways; add(reopened)
    }
}
