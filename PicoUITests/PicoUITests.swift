import XCTest

final class PicoUITests: XCTestCase {
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Pico"].waitForExistence(timeout: 3))
    }
}

