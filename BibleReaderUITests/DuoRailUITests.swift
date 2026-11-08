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
        assertPassageBesideRail(app)
    }

    /// Dragging across the rail carries a lens with the finger and selects where it's released,
    /// like the system tab bar (owner request, 7 November 2026).
    @MainActor
    func testDraggingAcrossRailSelectsReleasedDestination() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["BIBLE_TEST_STORE"] = UUID().uuidString
        app.launchEnvironment["BIBLE_TEST_CHAPTER"] = "GEN:1"
        app.launch()
        XCTAssertTrue(app.textViews["chapterText"].waitForExistence(timeout: 10))
        guard app.descendants(matching: .any)["sideDestinations"].waitForExistence(timeout: 2) else {
            throw XCTSkip("The side rail appears only on the Duo outer display.")
        }
        let read = app.buttons["destination-read"], search = app.buttons["destination-search"]
        XCTAssertTrue(read.isSelected)
        let start = read.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = search.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: end, withVelocity: 120, thenHoldForDuration: 0.3)
        XCTAssertTrue(search.wait(for: \.isSelected, toEqual: true, timeout: 3), "Releasing over Search selects it")
        XCTAssertFalse(read.isSelected)
    }

    /// The reader's top controls carry the same drag lens; releasing over Save Chapter saves it.
    @MainActor
    func testDraggingAcrossTopControlsActivatesReleasedControl() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["BIBLE_TEST_STORE"] = UUID().uuidString
        app.launchEnvironment["BIBLE_TEST_CHAPTER"] = "GEN:1"
        app.launch()
        XCTAssertTrue(app.textViews["chapterText"].waitForExistence(timeout: 10))
        guard app.descendants(matching: .any)["sideDestinations"].waitForExistence(timeout: 2) else {
            throw XCTSkip("The side rail appears only on the Duo outer display.")
        }
        let appearance = app.buttons["appearanceButton"], save = app.buttons["saveChapterButton"]
        XCTAssertEqual(save.label, "Save Chapter")
        XCTAssertEqual(appearance.frame.midX, save.frame.midX, accuracy: 2, "The controls stack vertically")
        appearance.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.2, thenDragTo: save.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
                   withVelocity: 120, thenHoldForDuration: 0.3)
        XCTAssertTrue(save.wait(for: \.label, toEqual: "Remove Saved Chapter", timeout: 3), "Releasing over Save Chapter saves it")
        XCTAssertFalse(app.sheets.firstMatch.exists)
    }

    /// Read Aloud keeps the rail instead of bringing back the bottom tab bar, and its player shares
    /// one bottom-trailing capsule with the passage control (owner direction, 7 November 2026).
    @MainActor
    func testRailStaysWhileReadingAloud() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["BIBLE_TEST_STORE"] = UUID().uuidString
        app.launchEnvironment["BIBLE_TEST_CHAPTER"] = "JHN:3"
        app.launchEnvironment["BIBLE_TEST_FAKE_SPEECH"] = "1"
        app.launch()
        XCTAssertTrue(app.textViews["chapterText"].waitForExistence(timeout: 10))
        let rail = app.descendants(matching: .any)["sideDestinations"]
        guard rail.waitForExistence(timeout: 2) else { throw XCTSkip("The side rail appears only on the Duo outer display.") }

        app.buttons["More"].firstMatch.tap()
        let item = app.buttons["Read Chapter Aloud"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        item.tap()
        let player = app.descendants(matching: .any)["narrationMiniPlayer"].firstMatch
        XCTAssertTrue(player.waitForExistence(timeout: 10))
        XCTAssertTrue(rail.exists, "Read Aloud keeps the side rail")
        let passage = app.buttons["passageButton"].frame
        XCTAssertEqual(player.frame.midY, passage.midY, accuracy: 4, "The player shares the passage control's row")
        XCTAssertGreaterThan(player.frame.minX, passage.maxX - 1, "The player follows the passage control")
        XCTAssertTrue(app.buttons["narrationPlayPause"].isHittable)
        XCTAssertTrue(app.buttons["narrationStop"].isHittable)
        assertPassageBesideRail(app)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "rail-read-aloud"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["narrationStop"].tap()
    }

    /// The passage control sits bottom trailing in the reading area, not in the rail, so the rail
    /// stays clear of the system toolbar when the Dynamic Island expands.
    @MainActor
    private func assertPassageBesideRail(_ app: XCUIApplication) {
        let passage = app.buttons["passageButton"].frame, read = app.buttons["destination-read"].frame
        let search = app.buttons["destination-search"].frame
        XCTAssertLessThan(passage.maxX, read.minX, "The passage control is left of the rail")
        XCTAssertEqual(passage.maxY, search.maxY, accuracy: 12, "The passage control lines up with the rail's bottom")
        XCTAssertGreaterThanOrEqual(passage.height, 44)
    }
}
