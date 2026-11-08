import XCTest

/// Read Aloud with deterministic speech (`BIBLE_TEST_FAKE_SPEECH`): each segment "speaks" for three
/// seconds, so these tests check controls and state, not Simulator audio.
final class NarrationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testReadChapterAloudFromMoreThenPauseResumeAndStop() throws {
        let app = application()
        app.launch()
        startFromMore(app)
        let player = element(app, "narrationMiniPlayer")
        XCTAssertTrue(player.waitForExistence(timeout: 10))
        let reference = progress(app)
        // The announcement, then verses. XCTest's idle waits are slow next to scripted pacing, so
        // check for any John 3 verse rather than a specific one.
        XCTAssertTrue(reference.waitForExistence(timeout: 5))
        XCTAssertTrue(wait(for: reference, valueContaining: "John 3:", timeout: 10))
        capture(app, name: "Read Aloud — playing")

        let playPause = app.buttons["narrationPlayPause"]
        XCTAssertEqual(playPause.label, "Pause")
        playPause.tap()
        XCTAssertTrue(wait(for: playPause, labelContaining: "Resume", timeout: 3))
        let paused = text(reference)
        sleep(3)
        XCTAssertEqual(text(reference), paused, "Paused narration must not advance")
        playPause.tap()
        XCTAssertTrue(wait(for: playPause, labelContaining: "Pause", timeout: 3))

        let before = text(reference)
        app.buttons["narrationNextVerse"].tap()
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@ AND value BEGINSWITH 'John 3:'", before), object: reference)
        XCTAssertEqual(XCTWaiter().wait(for: [moved], timeout: 5), .completed)

        // Audio continues across destinations, so the controls stay available.
        destination(app, "Saved").tap()
        XCTAssertTrue(player.waitForExistence(timeout: 3))
        destination(app, "Read").tap()

        // Stop is on the player itself, not in its menu.
        app.buttons["narrationMenu"].tap()
        XCTAssertTrue(app.buttons["Read Aloud Settings…"].firstMatch.waitForExistence(timeout: 3))
        // Only the player's own Stop button; the open menu has none.
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Stop Reading Aloud")).count, 1)
        let settingsItem = app.buttons["Read Aloud Settings…"].firstMatch
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        XCTAssertTrue(waitForDisappearance(settingsItem, timeout: 3))
        app.buttons["narrationStop"].tap()
        XCTAssertTrue(waitForDisappearance(player, timeout: 3))
        app.buttons["More"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Read Chapter Aloud"].firstMatch.waitForExistence(timeout: 3))
    }

    @MainActor
    func testReadAloudKeyboardShortcutTogglesPlayback() throws {
        let app = application()
        app.launch()
        XCTAssertTrue(reader(app).waitForExistence(timeout: 10))
        app.typeKey("l", modifierFlags: [.command, .shift])
        let playPause = app.buttons["narrationPlayPause"]
        XCTAssertTrue(playPause.waitForExistence(timeout: 5))
        XCTAssertTrue(wait(for: playPause, labelContaining: "Pause", timeout: 5))
        app.typeKey("l", modifierFlags: [.command, .shift])
        XCTAssertTrue(wait(for: playPause, labelContaining: "Resume", timeout: 3))
    }

    @MainActor
    func testReadAloudAtLargestTextKeepsEveryDestination() throws {
        let app = application()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        startFromMore(app)
        let player = element(app, "narrationMiniPlayer")
        XCTAssertTrue(player.waitForExistence(timeout: 10))
        for id in ["narrationPlayPause", "narrationPreviousVerse", "narrationNextVerse", "narrationStop", "narrationMenu", "narrationReference"] {
            XCTAssertTrue(app.buttons[id].isHittable, "\(id) should be reachable")
        }
        for label in ["Read", "Saved", "Search"] {
            XCTAssertTrue(destination(app, label).exists, "\(label) should stay reachable")
        }
        capture(app, name: "Read Aloud — accessibility text")
    }

    @MainActor
    func testReadAloudFromHereStartsAtSelectionAndHighlightingStillWorks() throws {
        let app = application()
        app.launch()
        let reader = reader(app)
        XCTAssertTrue(reader.waitForExistence(timeout: 10))
        let verse = reader.textViews.matching(NSPredicate(format: "label CONTAINS %@", "The same came to Jesus by night")).firstMatch
        XCTAssertTrue(verse.waitForExistence(timeout: 5))
        verse.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 15, dy: 8)).press(forDuration: 0.6)
        XCTAssertTrue(app.menuItems["Blue"].waitForExistence(timeout: 5))
        let readAloud = try XCTUnwrap(revealMenuItem(app, "Read Aloud from Here"), "Read Aloud from Here should be in the selection menu")
        readAloud.tap()
        let reference = progress(app)
        XCTAssertTrue(reference.waitForExistence(timeout: 5))
        // Starting here skips the chapter announcement and verse 1. XCTest's idle waits are slow
        // next to scripted pacing, so allow a few verses of progress (the unit test checks the exact anchor).
        XCTAssertTrue(wait(for: reference, valueContaining: "John 3:", timeout: 5))
        let started = Int(text(reference).split(separator: ":").last ?? "") ?? 0
        XCTAssertTrue((2...6).contains(started), "Started at \(text(reference))")
        capture(app, name: "Read Aloud from Here")

        // Annotation still saves while narration plays.
        verse.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 15, dy: 8)).press(forDuration: 0.6)
        XCTAssertTrue(app.menuItems["Blue"].waitForExistence(timeout: 5))
        app.menuItems["Blue"].tap()
        destination(app, "Saved").tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "savedItem-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["narrationPlayPause"].exists)
    }

    @MainActor
    func testScrollingReaderFollowsReadAloud() throws {
        let app = application(speech: "fast")
        app.launch()
        let reader = reader(app)
        XCTAssertTrue(reader.waitForExistence(timeout: 10))
        guard app.textViews["chapterText"].exists else { throw XCTSkip("Scrolling reader check") }
        let verse = reader.textViews.matching(NSPredicate(format: "label CONTAINS %@", "For God so loved the world")).firstMatch
        startFromMore(app)
        let reference = progress(app)
        XCTAssertTrue(reference.waitForExistence(timeout: 5))
        XCTAssertTrue(wait(for: reference, valueContaining: "John 3:17", timeout: 45), "Narration should reach John 3:17")
        XCTAssertTrue(verse.exists)
        let window = app.windows.firstMatch.frame
        // Without following, 3:16 would still be below the window. Its first line may already have
        // scrolled above a short viewport (the Duo outer display stacks the player over the passage
        // control), so check that the verse is in view rather than its first line.
        XCTAssertTrue(window.intersects(verse.frame),
                      "The reader follows narration: John 3:16 \(verse.frame) should be on screen \(window)")
        capture(app, name: "Read Aloud — following in the scrolling reader")
    }

    @MainActor
    func testTwoPagesTurnsWithReadAloudIntoTheNextChapter() throws {
        let app = application(speech: "fast")
        app.launch()
        guard app.frame.width > 600 else { throw XCTSkip("iPad landscape Two Pages check") }
        defer { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .landscapeLeft
        let left = app.textViews["spreadPageLeft"]
        guard left.waitForExistence(timeout: 10) else { throw XCTSkip("Two Pages is not the current layout") }
        // Each page is named for its place in the chapter, for example "John 3, page 1 of 8".
        let firstShown = left.label
        startFromMore(app)
        let turned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", firstShown), object: left)
        XCTAssertEqual(XCTWaiter().wait(for: [turned], timeout: 45), .completed, "Two Pages should turn with narration")
        capture(app, name: "Read Aloud — Two Pages turned")
        XCTAssertTrue(wait(for: app.buttons["passageButton"], labelContaining: "4", timeout: 60), "The reader follows into John 4")
        XCTAssertTrue(text(progress(app)).hasPrefix("John 4"))
    }

    // MARK: Helpers

    /// The selection menu may place later actions behind its overflow chevron, which expands
    /// it into a list whose rows are not menu items.
    @MainActor
    private func revealMenuItem(_ app: XCUIApplication, _ title: String) -> XCUIElement? {
        let item = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title)).firstMatch
        for _ in 0..<3 {
            if item.exists { return item }
            // "Next Page" on iPhone, "Forward" on iPad.
            let more = app.buttons.matching(NSPredicate(format: "label IN %@", ["Next Page", "Forward"])).firstMatch
            guard more.exists else { return nil }
            // A plain coordinate tap: XCTest's element tap can dismiss the edit menu first.
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: more.frame.midX, dy: more.frame.midY)).tap()
            _ = item.waitForExistence(timeout: 1)
        }
        return item.exists ? item : nil
    }

    @MainActor
    private func application(speech: String = "1") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["BIBLE_TEST_STORE"] = UUID().uuidString
        app.launchEnvironment["BIBLE_TEST_CHAPTER"] = "JHN:3"
        app.launchEnvironment["BIBLE_TEST_FAKE_SPEECH"] = speech
        return app
    }

    @MainActor
    func testReadAloudSettingsOfferVersePausesAndVoiceGuidance() throws {
        let app = application()
        app.launch()
        startFromMore(app)
        XCTAssertTrue(element(app, "narrationMiniPlayer").waitForExistence(timeout: 10))
        app.buttons["narrationMenu"].tap()
        app.buttons["Read Aloud Settings…"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Read Aloud"].waitForExistence(timeout: 5))
        // With only basic voices (the simulator), the checklist steps can be ticked off.
        let step = app.buttons["voiceGuideStep-0"]
        if step.waitForExistence(timeout: 2) {
            XCTAssertEqual(step.value as? String, "Not done")
            step.tap()
            XCTAssertEqual(step.value as? String, "Done")
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Read Aloud settings"
        shot.lifetime = .keepAlways
        add(shot)
        let pause = element(app, "narrationVersePause")
        for _ in 0..<4 where !pause.exists { app.swipeUp() }
        XCTAssertTrue(pause.waitForExistence(timeout: 3))
        // The empty pronunciation list hides its setting until reviewed entries ship.
        XCTAssertFalse(app.switches["Use Pronunciation Hints"].exists)
        app.buttons["narrationSettingsDone"].tap()
        XCTAssertTrue(waitForDisappearance(pause, timeout: 3))
    }

    @MainActor
    private func startFromMore(_ app: XCUIApplication) {
        XCTAssertTrue(reader(app).waitForExistence(timeout: 10))
        let more = app.buttons["More"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        let item = app.buttons["Read Chapter Aloud"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        item.tap()
    }

    @MainActor
    private func reader(_ app: XCUIApplication) -> XCUIElement {
        app.textViews.matching(NSPredicate(format: "identifier IN %@", ["chapterText", "spreadPageLeft"])).firstMatch
    }

    /// The player reports the spoken reference as its value, even where a narrow capsule hides it.
    @MainActor
    private func progress(_ app: XCUIApplication) -> XCUIElement { element(app, "narrationMiniPlayer") }

    @MainActor
    private func text(_ element: XCUIElement) -> String { element.value as? String ?? "" }

    @MainActor
    private func wait(for element: XCUIElement, valueContaining text: String, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", text), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// Compact capsules, or the regular-width top tab bar.
    @MainActor
    private func destination(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let compact = app.buttons["destination-" + label.lowercased()]
        if compact.exists { return compact }
        let predicate = NSPredicate(format: "label == %@ AND elementType IN %@", label,
                                    [XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.cell.rawValue])
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    @MainActor
    private func wait(for element: XCUIElement, labelContaining text: String, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
