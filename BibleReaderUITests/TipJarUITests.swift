import StoreKitTest
import XCTest

final class TipJarUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipIf(ProcessInfo.processInfo.environment["BIBLE_LOCAL_STOREKIT_TESTS"] != "1",
                      "Use the BibleReader-Tips scheme for local StoreKit integration tests.")
    }

    @MainActor
    func testTipPurchaseAndReturnToFreeReader() throws {
        let app = application()
        app.launch()
        let session = try makeSession()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        openTips(app)
        let small = app.buttons["dev.kpierre.bible.tip.small"]
        XCTAssertTrue(small.waitForExistence(timeout: 15))
        XCTAssertTrue(small.label.contains("$0.99"))
        XCTAssertTrue(app.buttons["dev.kpierre.bible.tip.medium"].label.contains("$2.99"))
        XCTAssertTrue(app.buttons["dev.kpierre.bible.tip.large"].label.contains("$4.99"))
        capture(app, "Tip choices")
        small.tap()
        let thanks = app.staticTexts["Thank you for supporting Bible!"]
        XCTAssertTrue(thanks.waitForExistence(timeout: 15))
        small.tap()
        XCTAssertTrue(thanks.waitForExistence(timeout: 15))
        capture(app, "Tip thank-you")
        app.buttons["tipsCloseButton"].tap()
        XCTAssertTrue(app.textViews["chapterText"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTipsAtLargestTypeInDarkAppearanceAndLandscape() throws {
        let app = application()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let session = try makeSession()
        defer { session.clearTransactions(); session.resetToDefaultState(); XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.textViews["chapterText"].waitForExistence(timeout: 10))
        app.buttons["appearanceButton"].tap()
        app.buttons["Dark"].tap()
        app.buttons["appearanceDoneButton"].tap()
        openTips(app)
        let small = app.buttons["dev.kpierre.bible.tip.small"]
        for _ in 0..<8 where !small.isHittable { app.swipeUp() }
        XCTAssertTrue(small.isHittable)
        capture(app, "Tips — largest text, dark")
        XCUIDevice.shared.orientation = .landscapeLeft
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width > app.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 10), .completed)
        let large = app.buttons["dev.kpierre.bible.tip.large"]
        // Swipe the list itself: after rotation, a window-level swipe can miss the scroll view.
        let list = app.collectionViews.firstMatch
        for _ in 0..<8 where !large.isHittable { list.swipeUp() }
        XCTAssertTrue(large.isHittable)
        capture(app, "Tips — largest text, landscape")
        app.buttons["tipsCloseButton"].tap()
        XCTAssertTrue(app.textViews["chapterText"].waitForExistence(timeout: 5))
    }

    @MainActor private func makeSession() throws -> SKTestSession {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "BibleTips", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        XCTAssertTrue(session.disableDialogs, "Local StoreKit must accept its test settings before any purchase.")
        return session
    }
    @MainActor private func application() -> XCUIApplication {
        // A failed rotation test can leave the simulator in landscape for the next launch.
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["BIBLE_TEST_STORE"] = UUID().uuidString
        return app
    }
    @MainActor private func openTips(_ app: XCUIApplication) {
        XCTAssertTrue(app.textViews["chapterText"].waitForExistence(timeout: 10))
        app.buttons["More"].tap()
        app.buttons["About Bible"].tap()
        let support = app.buttons["supportDevelopmentButton"]
        for _ in 0..<6 where !support.isHittable { app.swipeUp() }
        XCTAssertTrue(support.isHittable)
        support.tap()
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
