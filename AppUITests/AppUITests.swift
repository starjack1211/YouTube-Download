import XCTest

final class AppUITests: XCTestCase {
    func testDownloadScreenAndLinkInput() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["影片下載"].waitForExistence(timeout: 20))
        let download = app.buttons["下載到相簿"]
        XCTAssertTrue(download.exists)
        XCTAssertFalse(download.isEnabled)
        let field = app.textFields.firstMatch.exists ? app.textFields.firstMatch : app.textViews.firstMatch
        XCTAssertTrue(field.exists)
        field.tap()
        field.typeText("https://youtu.be/_pJQFrTU4aQ")
        XCTAssertTrue(download.isEnabled)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Download screen"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
