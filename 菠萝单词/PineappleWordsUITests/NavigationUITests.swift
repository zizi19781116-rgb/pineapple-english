import XCTest

final class NavigationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testEmptyLibraryAndGlobalSearch() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing-empty"]; app.launch()
        XCTAssertTrue(app.staticTexts["从第一本词书开始"].waitForExistence(timeout: 15))
        app.buttons["全局搜索"].tap()
        let input = app.textFields["搜索单词、词组、笔记、词书"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("beautiful")
        XCTAssertTrue(app.staticTexts["没有找到相关内容"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "全局搜索空状态"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testLandscapeAndPortraitKeepNavigationAvailable() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing-empty"]; app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["全局搜索"].waitForExistence(timeout: 15))
        var attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "横屏首页"; attachment.lifetime = .keepAlways; add(attachment)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["全局搜索"].exists)
        attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "竖屏首页"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
