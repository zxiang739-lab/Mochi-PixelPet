import XCTest

final class MochiUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-MochiUITestMode"]
        app.launch()
        return app
    }

    func testHomeShowsPetAndActionDock() {
        let app = launchApp()

        XCTAssertTrue(app.staticTexts["Mochi"].waitForExistence(timeout: 20), "pet name should appear on launch")

        for label in ["抚摸", "喂食", "玩耍", "清理", "探索"] {
            XCTAssertTrue(app.buttons[label].exists, "action dock is missing \(label)")
        }
    }

    func testAllTabsAreReachable() {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["Mochi"].waitForExistence(timeout: 20))

        for (tab, title) in [("背包", "背包"), ("日记", "日记"), ("成长", "成长"), ("设置", "设置")] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(
                app.navigationBars[title].waitForExistence(timeout: 8),
                "\(title) screen did not appear"
            )
        }
    }

    func testPettingShowsFeedback() {
        let app = launchApp()

        let stroke = app.buttons["抚摸"]
        XCTAssertTrue(stroke.waitForExistence(timeout: 20))
        stroke.tap()

        let toast = app.staticTexts
            .containing(NSPredicate(format: "label CONTAINS %@", "眯起了眼睛"))
            .firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 6), "petting should produce a visible receipt")
    }

    func testFeedingSheetOpensAndListsFood() {
        let app = launchApp()

        let feed = app.buttons["喂食"]
        XCTAssertTrue(feed.waitForExistence(timeout: 20))
        feed.tap()

        XCTAssertTrue(app.navigationBars["喂点什么"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["晨露浆果"].exists)
    }
}
