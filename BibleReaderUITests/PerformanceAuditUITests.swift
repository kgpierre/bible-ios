import XCTest

/// Run alone on an idle simulator. XCTest metrics are diagnostic, not device acceptance.
final class PerformanceAuditUITests: XCTestCase {
    @MainActor func testLaunchPerformance() {
        let app = XCUIApplication()
        app.launchEnvironment["BIBLE_TEST_STORE"] = UUID().uuidString
        let options = XCTMeasureOptions(); options.iterationCount = 5
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: options) {
            app.launch()
            XCTAssertTrue(app.textViews["chapterText"].waitForExistence(timeout: 10))
            app.terminate()
        }
    }

    @MainActor func testPsalmScrollingPerformance() {
        let app = XCUIApplication()
        app.launchEnvironment["BIBLE_TEST_STORE"] = UUID().uuidString
        app.launchEnvironment["BIBLE_TEST_CHAPTER"] = "PSA:119"
        app.launch()
        let reader = app.textViews["chapterText"]
        XCTAssertTrue(reader.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["passageButton"].label.contains("119"))
        let options = XCTMeasureOptions(); options.iterationCount = 5
        measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric,
                          XCTHitchMetric(application: app),
                          XCTMemoryMetric(application: app), XCTCPUMetric(application: app)], options: options) {
            reader.swipeUp(velocity: .fast)
            reader.swipeUp(velocity: .fast)
            reader.swipeDown(velocity: .fast)
            reader.swipeDown(velocity: .fast)
        }
    }
}
