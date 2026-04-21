//
//  VoiceInkUITests.swift
//  VoiceInkUITests
//
//  Created by Prakash Joshi on 15/10/2024.
//

import XCTest

final class VoiceInkUITests: XCTestCase {
    private let appSupportOverrideEnvironmentKey = "VOICEWINK_APP_SUPPORT_OVERRIDE"

    private func launchApp(environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "YES",
            "-autoUpdateCheck", "NO",
            "-ApplePersistenceIgnoreState", "YES",
        ]
        app.launchEnvironment.merge(environment) { _, newValue in newValue }
        app.launch()
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func openSidebarItem(_ identifier: String, in app: XCUIApplication) {
        let item = element(identifier, in: app)
        XCTAssertTrue(item.waitForExistence(timeout: 10), "Missing sidebar item \(identifier)")
        item.click()
    }

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        let app = launchApp()

        XCTAssertFalse(element("sidebar.license", in: app).exists)
        XCTAssertFalse(element("sidebar.enhancement", in: app).exists)
        XCTAssertTrue(app.staticTexts["Why VoiceWink Exists"].waitForExistence(timeout: 10))

        openSidebarItem("sidebar.transcribeAudio", in: app)
        XCTAssertTrue(app.staticTexts["Drop audio or video files here"].waitForExistence(timeout: 10))

        openSidebarItem("sidebar.history", in: app)
        XCTAssertTrue(
            app.textFields["Search transcriptions..."].waitForExistence(timeout: 10) ||
            app.staticTexts["No transcriptions yet"].waitForExistence(timeout: 10)
        )

        openSidebarItem("sidebar.audioInput", in: app)
        XCTAssertTrue(element("audioInput.inputModeLabel", in: app).waitForExistence(timeout: 10))

        openSidebarItem("sidebar.permissions", in: app)
        XCTAssertTrue(app.staticTexts["Microphone Access"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Screen Recording Access"].exists)

        openSidebarItem("sidebar.settings", in: app)
        XCTAssertTrue(app.staticTexts["Shortcut 1"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.switches["Show Announcements"].exists)
        XCTAssertFalse(app.staticTexts["Paste Last Transcription (Enhanced)"].exists)
    }

    @MainActor
    func testVoiceWinkUsesOnlyItsConfiguredHistoryStore() throws {
        let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let currentSupportDirectory = rootDirectory.appendingPathComponent("VoiceWinkSupport", isDirectory: true)

        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let app = launchApp(environment: [
            appSupportOverrideEnvironmentKey: currentSupportDirectory.path,
        ])

        openSidebarItem("sidebar.history", in: app)
        XCTAssertTrue(app.textFields["Search transcriptions..."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["No transcriptions yet"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testModelManagementShowsOnlyLocalTranscriptionProviders() throws {
        let app = launchApp()

        openSidebarItem("sidebar.models", in: app)

        XCTAssertTrue(element("models.filter.recommended", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(element("models.filter.local", in: app).exists)
        XCTAssertFalse(app.buttons["Cloud"].exists)
        XCTAssertFalse(app.buttons["Custom"].exists)

        XCTAssertTrue(app.staticTexts["Base (English)"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Parakeet V2"].exists)
        XCTAssertTrue(app.staticTexts["Large v3 Turbo (Quantized)"].exists)
        XCTAssertFalse(app.staticTexts["Whisper Large v3 Turbo (Groq)"].exists)

        element("models.filter.local", in: app).click()
        XCTAssertTrue(element("models.importLocal", in: app).waitForExistence(timeout: 10))
    }

    @MainActor
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
