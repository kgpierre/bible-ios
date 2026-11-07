import XCTest

/// The Duo outer display's side rail (0018, owner refinements of 6–7 November 2026): icon-only
/// destinations with a glass selection lens. Skips wherever the rail isn't shown.
final class DuoRailUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testRailDestinationsSwitchAndKeepTheirNames() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["BIBLE_TEST_STORE"] = UUID().uuidString
        app.launchEnvironment["BIBLE_TEST_CHAPTER"] = "GEN:1"
        app.launch()
        XCTAssertTrue(app.textViews["chapterText"].waitForExistence(timeout: 10))
        let rail = app.descendants(matching: .any)["sideDestinations"]
        guard rail.waitForExistence(timeout: 2) else { throw XCTSkip("The side rail appears only on the Duo outer display.") }

        for (id, name) in [("saved", "Saved"), ("search", "Search"), ("read", "Read")] {
            let button = app.buttons["destination-\(id)"]
            XCTAssertTrue(button.isHittable, "\(name) should be reachable")
            // Icon-only, but VoiceOver still names each destination.
            XCTAssertEqual(button.label, name)
            XCTAssertGreaterThanOrEqual(button.frame.width, 44)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            button.tap()
            XCTAssertTrue(button.wait(for: \.isSelected, toEqual: true, timeout: 3), "\(name) should become selected")
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "rail-\(id)"
            shot.lifetime = .keepAlways
            add(shot)
        }
        XCTAssertFalse(app.buttons["destination-saved"].isSelected)
        XCTAssertEqual(app.buttons["passageButton"].frame.width, app.buttons["destination-read"].frame.width + 4, accuracy: 1,
                       "The passage control and destinations share one width")
    }
}
