import XCTest

/// The iPhone Duo's vertical bar (0018, owner refinements of 7 November 2026): the system tab bar
/// sits in the column with the status bar, the reader's top controls carry a drag lens, and the
/// passage control floats bottom trailing. Skips wherever the system doesn't stack its bars.
final class DuoRailUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    private func launch(_ chapter: String = "GEN:1", fakeSpeech: Bool = false) throws -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["BIBLE_TEST_STORE"] = UUID().uuidString
        app.launchEnvironment["BIBLE_TEST_CHAPTER"] = chapter
        if fakeSpeech { app.launchEnvironment["BIBLE_TEST_FAKE_SPEECH"] = "1" }
        app.launch()
        XCTAssertTrue(app.textViews.matching(NSPredicate(format: "identifier IN %@", ["chapterText", "spreadPageLeft"]))
            .firstMatch.waitForExistence(timeout: 10))
        // In the vertical bar the system tabs are buttons stacked in one column, not a tab bar element.
        let read = tab(app, "Read"), search = tab(app, "Search")
        guard read.waitForExistence(timeout: 2), search.exists,
              abs(read.frame.midX - search.frame.midX) < 2, search.frame.minY > read.frame.maxY else {
            throw XCTSkip("The system places a vertical bar only on the iPhone Duo.")
        }
        return app
    }

    @MainActor
    private func tab(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch
    }

    @MainActor
    func testSystemTabsSwitchInTheVerticalBar() throws {
        let app = try launch()
        for name in ["Saved", "Search", "Read"] {
            let tab = tab(app, name)
            XCTAssertTrue(tab.isHittable, "\(name) should be reachable")
            tab.tap()
            XCTAssertTrue(tab.wait(for: \.isSelected, toEqual: true, timeout: 3), "\(name) should become selected")
        }
        let passage = app.buttons["passageButton"].frame
        XCTAssertLessThan(passage.maxX, tab(app, "Read").frame.minX, "The passage control floats beside the vertical bar")
        XCTAssertGreaterThan(passage.minY, app.windows.firstMatch.frame.midY, "…at the bottom")
    }

    /// The reader's top controls carry the lens; releasing over Save Chapter saves it.
    @MainActor
    func testDraggingAcrossTopControlsActivatesReleasedControl() throws {
        let app = try launch()
        let appearance = app.buttons["appearanceButton"], save = app.buttons["saveChapterButton"]
        XCTAssertEqual(save.label, "Save Chapter")
        XCTAssertEqual(appearance.frame.midX, save.frame.midX, accuracy: 2, "The controls stack vertically")
        appearance.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.2, thenDragTo: save.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
                   withVelocity: 120, thenHoldForDuration: 0.3)
        XCTAssertTrue(save.wait(for: \.label, toEqual: "Remove Saved Chapter", timeout: 3), "Releasing over Save Chapter saves it")
        // Released far from the capsule, a drag cancels.
        save.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.2, thenDragTo: save.coordinate(withNormalizedOffset: CGVector(dx: -4, dy: 0.5)),
                   withVelocity: 120, thenHoldForDuration: 0.3)
        XCTAssertEqual(save.label, "Remove Saved Chapter")
    }

    /// Read Aloud's player shares the passage control's capsule beside the vertical bar.
    @MainActor
    func testReadAloudSharesThePassageCapsule() throws {
        let app = try launch("JHN:3", fakeSpeech: true)
        app.buttons["More"].firstMatch.tap()
        let item = app.buttons["Read Chapter Aloud"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        item.tap()
        let player = app.descendants(matching: .any)["narrationMiniPlayer"].firstMatch
        XCTAssertTrue(player.waitForExistence(timeout: 10))
        let passage = app.buttons["passageButton"].frame
        XCTAssertEqual(player.frame.midY, passage.midY, accuracy: 4, "The player shares the passage control's row")
        XCTAssertGreaterThan(player.frame.minX, passage.maxX - 1, "The player follows the passage control")
        XCTAssertLessThan(player.frame.maxX, tab(app, "Read").frame.minX)
        XCTAssertTrue(app.buttons["narrationPlayPause"].isHittable)
        XCTAssertTrue(app.buttons["narrationStop"].isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "vertical-bar-read-aloud"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["narrationStop"].tap()
    }
}
