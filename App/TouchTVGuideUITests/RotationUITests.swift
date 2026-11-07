import XCTest

/// Proves the app really rotates: launches it, turns the device to landscape and back, and checks the window follows.
final class RotationUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func waitForShape(_ app: XCUIApplication, landscape: Bool, timeout: TimeInterval = 10) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            let f = app.windows.firstMatch.frame
            if f.width > 0 && (landscape ? f.width > f.height : f.height > f.width) { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }

    func testAppRotatesToLandscapeAndBack() {
        let app = XCUIApplication()
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(waitForShape(app, landscape: false), "app should start in portrait")
        add(XCTAttachment(screenshot: app.screenshot()))

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(waitForShape(app, landscape: true), "window did not become landscape after rotating the device")
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "landscape-left"; a.lifetime = .keepAlways; add(a)

        XCUIDevice.shared.orientation = .landscapeRight
        XCTAssertTrue(waitForShape(app, landscape: true), "landscape right should also work")

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(waitForShape(app, landscape: false), "app should return to portrait")
    }
}
