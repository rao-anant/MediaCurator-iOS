//
//  MediaCuratorUITests.swift
//  MediaCuratorUITests
//

import XCTest

final class MediaCuratorUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// Grants the Photos "Allow Full Access" prompt and dismisses any first-run demo, then walks the
    /// gallery so I can see each step. Screenshots are attached to the result bundle.
    @MainActor
    func testGalleryWalk() throws {
        let app = XCUIApplication()
        app.launch()

        // 1) Photos permission prompt (system alert, owned by springboard).
        let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = sb.buttons["Allow Full Access"]
        if allow.waitForExistence(timeout: 10) { allow.tap() }

        // 2) First-run demo may auto-play — tap through / dismiss whatever's tappable.
        sleep(3)
        snap(app, "01-after-launch")

        // Try to get past onboarding: a "Get started"/"Done"/"Skip"/close control if present.
        for label in ["Get started", "Done", "Skip", "Continue", "Start curating", "Browse photos"] {
            let b = app.buttons[label]
            if b.exists && b.isHittable { b.tap(); sleep(1) }
        }
        // A close (X) button on the demo, if any.
        let closeX = app.buttons["xmark"]
        if closeX.exists && closeX.isHittable { closeX.tap(); sleep(1) }
        snap(app, "02-home")

        // 3) Into the gallery via the "Free up space" card (-> gallery).
        let freeUp = app.staticTexts["Free up space"]
        if freeUp.waitForExistence(timeout: 5) { freeUp.tap(); sleep(2) }
        snap(app, "03-gallery")

        // 4) Expand 2024 if collapsed.
        let y2024 = app.staticTexts["2024"]
        if y2024.waitForExistence(timeout: 5) { y2024.tap(); sleep(1) }
        snap(app, "04-2024")

        // 5) Open April 2024.
        let apr = app.staticTexts["April 2024"]
        if apr.waitForExistence(timeout: 5) { apr.tap(); sleep(2) }
        snap(app, "05-april-open")

        // 6) Scroll down into the photos.
        app.swipeUp(); sleep(1); app.swipeUp(); sleep(1)
        snap(app, "06-scrolled")

        app.swipeUp(); sleep(1)
        snap(app, "07-scrolled-more")
    }
}
