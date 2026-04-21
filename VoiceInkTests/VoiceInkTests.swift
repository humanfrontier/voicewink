import Foundation
import CoreAudio
import SwiftData
import Testing
@testable import VoiceWink

struct VoiceWinkPhase02Tests {
    @Test
    func voiceWinkIdentityUsesDedicatedNamespace() {
        #expect(AppIdentity.bundleIdentifier == "com.prakashjoshipax.VoiceWink")
        #expect(AppIdentity.cloudKitContainerIdentifier == "iCloud.com.prakashjoshipax.VoiceWink")
    }

    @Test @MainActor
    func bundledStarterBootstrapsAndBecomesDefaultFallback() throws {
        let suiteName = "VoiceWinkPhase02Tests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create a dedicated UserDefaults suite for PHASE-02 tests.")
            return
        }

        defer { defaults.removePersistentDomain(forName: suiteName) }

        let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let modelsDirectory = rootDirectory.appendingPathComponent("WhisperModels", isDirectory: true)
        let bundledResourceDirectory = rootDirectory.appendingPathComponent("Bundle/models", isDirectory: true)
        let bundledModelURL = bundledResourceDirectory.appendingPathComponent(AppIdentity.bundledStarterWhisperFilename)

        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        try FileManager.default.createDirectory(at: bundledResourceDirectory, withIntermediateDirectories: true)
        try Data("starter-model".utf8).write(to: bundledModelURL)

        let whisperModelManager = WhisperModelManager(
            modelsDirectory: modelsDirectory,
            fileManager: .default,
            bundledModelURLProvider: { filename in
                bundledResourceDirectory.appendingPathComponent(filename)
            }
        )

        whisperModelManager.createModelsDirectoryIfNeeded()
        try whisperModelManager.bootstrapBundledStarterModelIfNeeded()
        whisperModelManager.loadAvailableModels()

        #expect(
            whisperModelManager.availableModels.contains(where: { $0.name == AppIdentity.bundledStarterWhisperModelName })
        )

        let transcriptionModelManager = TranscriptionModelManager(
            whisperModelManager: whisperModelManager,
            fluidAudioModelManager: FluidAudioModelManager(),
            userDefaults: defaults
        )

        transcriptionModelManager.refreshAllAvailableModels()
        transcriptionModelManager.loadCurrentTranscriptionModel()

        #expect(transcriptionModelManager.currentTranscriptionModel?.name == AppIdentity.bundledStarterWhisperModelName)
        #expect(defaults.string(forKey: "CurrentTranscriptionModel") == AppIdentity.bundledStarterWhisperModelName)
    }

    @Test @MainActor
    func savedSelectionWinsOverBundledFallback() throws {
        let suiteName = "VoiceWinkPhase02Tests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create a dedicated UserDefaults suite for PHASE-02 tests.")
            return
        }

        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("apple-speech", forKey: "CurrentTranscriptionModel")

        let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let modelsDirectory = rootDirectory.appendingPathComponent("WhisperModels", isDirectory: true)
        let bundledResourceDirectory = rootDirectory.appendingPathComponent("Bundle/models", isDirectory: true)
        let bundledModelURL = bundledResourceDirectory.appendingPathComponent(AppIdentity.bundledStarterWhisperFilename)

        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        try FileManager.default.createDirectory(at: bundledResourceDirectory, withIntermediateDirectories: true)
        try Data("starter-model".utf8).write(to: bundledModelURL)

        let whisperModelManager = WhisperModelManager(
            modelsDirectory: modelsDirectory,
            fileManager: .default,
            bundledModelURLProvider: { filename in
                bundledResourceDirectory.appendingPathComponent(filename)
            }
        )

        whisperModelManager.createModelsDirectoryIfNeeded()
        try whisperModelManager.bootstrapBundledStarterModelIfNeeded()
        whisperModelManager.loadAvailableModels()

        let transcriptionModelManager = TranscriptionModelManager(
            whisperModelManager: whisperModelManager,
            fluidAudioModelManager: FluidAudioModelManager(),
            userDefaults: defaults
        )

        transcriptionModelManager.refreshAllAvailableModels()
        transcriptionModelManager.loadCurrentTranscriptionModel()

        #expect(transcriptionModelManager.currentTranscriptionModel?.name == "apple-speech")
        #expect(defaults.string(forKey: "CurrentTranscriptionModel") == "apple-speech")
    }

    @Test
    func transcriptionModelRegistryExposesOnlyOnDeviceProviders() {
        let providers = Set(TranscriptionModelRegistry.models.map(\.provider))

        #expect(providers == Set([.whisper, .fluidAudio, .nativeApple]))
        #expect(!TranscriptionModelRegistry.models.contains(where: { $0.name == "whisper-large-v3-turbo" }))
    }

    @Test
    func cleanCutResetClearsIncompatibleVoiceWinkState() throws {
        let suiteName = "VoiceWinkPhase03Tests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create a dedicated UserDefaults suite for PHASE-03 clean-cut tests.")
            return
        }

        defer { defaults.removePersistentDomain(forName: suiteName) }

        let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let appSupportDirectory = rootDirectory.appendingPathComponent("Application Support", isDirectory: true)
        let storeURL = appSupportDirectory.appendingPathComponent("default.store")
        let walURL = appSupportDirectory.appendingPathComponent("default.store-wal")
        let shmURL = appSupportDirectory.appendingPathComponent("default.store-shm")

        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        try FileManager.default.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
        try Data("legacy-store".utf8).write(to: storeURL)
        try Data("legacy-wal".utf8).write(to: walURL)
        try Data("legacy-shm".utf8).write(to: shmURL)

        defaults.set("apple-speech", forKey: "CurrentTranscriptionModel")
        defaults.set(Data("legacy-power-mode".utf8), forKey: "powerModeConfigurationsV2")
        defaults.set(Data("legacy-session".utf8), forKey: "powerModeActiveSession.v1")
        defaults.set("OpenAI", forKey: "selectedAIProvider")
        defaults.set("gpt-4o-mini", forKey: "selectedAIModel")
        defaults.set(true, forKey: "isAIEnhancementEnabled")
        defaults.set(Data("legacy-prompts".utf8), forKey: "customPromptsData")

        VoiceWinkCleanCutReset.applyIfNeeded(
            userDefaults: defaults,
            fileManager: .default,
            appSupportDirectory: appSupportDirectory
        )

        #expect(defaults.string(forKey: "CurrentTranscriptionModel") == "apple-speech")
        #expect(defaults.object(forKey: "powerModeConfigurationsV2") == nil)
        #expect(defaults.object(forKey: "powerModeActiveSession.v1") == nil)
        #expect(defaults.object(forKey: "selectedAIProvider") == nil)
        #expect(defaults.object(forKey: "selectedAIModel") == nil)
        #expect(defaults.object(forKey: "isAIEnhancementEnabled") == nil)
        #expect(defaults.object(forKey: "customPromptsData") == nil)
        #expect(!FileManager.default.fileExists(atPath: storeURL.path))
        #expect(!FileManager.default.fileExists(atPath: walURL.path))
        #expect(!FileManager.default.fileExists(atPath: shmURL.path))
    }

    @Test @MainActor
    func bundledStarterProducesNonEmptyLocalTranscript() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let modelsDirectory = rootDirectory.appendingPathComponent("WhisperModels", isDirectory: true)
        let bundledResourceDirectory = rootDirectory.appendingPathComponent("Bundle/models", isDirectory: true)
        let bundledModelURL = bundledResourceDirectory.appendingPathComponent(AppIdentity.bundledStarterWhisperFilename)
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceBundledModelURL = sourceRoot
            .appendingPathComponent("VoiceInk/Resources/models", isDirectory: true)
            .appendingPathComponent(AppIdentity.bundledStarterWhisperFilename)
        let spokenSampleURL = rootDirectory.appendingPathComponent("spoken-sample.aiff")
        let wavSampleURL = rootDirectory.appendingPathComponent("spoken-sample.wav")

        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        try FileManager.default.createDirectory(at: bundledResourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: sourceBundledModelURL, to: bundledModelURL)

        let sayProcess = Process()
        sayProcess.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        sayProcess.arguments = [
            "-v", "Samantha",
            "-o", spokenSampleURL.path,
            "VoiceWink bundled transcription test."
        ]
        try sayProcess.run()
        sayProcess.waitUntilExit()

        #expect(sayProcess.terminationStatus == 0)

        let whisperModelManager = WhisperModelManager(
            modelsDirectory: modelsDirectory,
            fileManager: .default,
            bundledModelURLProvider: { filename in
                bundledResourceDirectory.appendingPathComponent(filename)
            }
        )

        whisperModelManager.createModelsDirectoryIfNeeded()
        try whisperModelManager.bootstrapBundledStarterModelIfNeeded()
        whisperModelManager.loadAvailableModels()

        let audioProcessor = AudioProcessor()
        let samples = try await audioProcessor.processAudioToSamples(spokenSampleURL)
        try audioProcessor.saveSamplesAsWav(samples: samples, to: wavSampleURL)

        let model = TranscriptionModelRegistry.models.first {
            $0.name == AppIdentity.bundledStarterWhisperModelName
        }
        #expect(model != nil)

        let service = WhisperTranscriptionService(
            modelsDirectory: modelsDirectory,
            modelProvider: whisperModelManager
        )

        let text = try await service.transcribe(audioURL: wavSampleURL, model: try #require(model))

        #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test
    func applicationSupportDirectoryUsesVoiceWinkBundleIdentifier() {
        #expect(AppPaths.applicationSupportDirectory.lastPathComponent == AppIdentity.bundleIdentifier)
    }

    @Test
    func transcriptionLogRedactionSummariesExcludeTranscriptContents() {
        let rawTranscript = "my ssn is 123-45-6789 and the launch code is swordfish"
        let filteredTranscript = "launch code is swordfish"

        let summary = AppLogRedaction.textSummary(rawTranscript)
        let changeSummary = AppLogRedaction.changeSummary(before: rawTranscript, after: filteredTranscript)

        #expect(!summary.contains(rawTranscript))
        #expect(!summary.contains("123-45-6789"))
        #expect(!summary.contains("swordfish"))
        #expect(summary.contains("characters="))
        #expect(summary.contains("words="))

        #expect(!changeSummary.contains(rawTranscript))
        #expect(!changeSummary.contains(filteredTranscript))
        #expect(!changeSummary.contains("123-45-6789"))
        #expect(!changeSummary.contains("swordfish"))
        #expect(changeSummary.contains("changed=true"))
    }

    @Test
    func appLogRedactionURLAndErrorSummariesExcludeSensitiveContents() {
        let url = "https://example.com/private/path?token=super-secret"
        let error = NSError(
            domain: "VoiceWinkTests",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "failed while processing super-secret token"]
        )

        let urlSummary = AppLogRedaction.urlSummary(url)
        let errorSummary = AppLogRedaction.errorSummary(error)

        #expect(!urlSummary.contains(url))
        #expect(!urlSummary.contains("super-secret"))
        #expect(urlSummary.contains("scheme=https"))
        #expect(urlSummary.contains("hasQuery=true"))

        #expect(!errorSummary.contains("super-secret"))
        #expect(errorSummary.contains("domain=VoiceWinkTests"))
        #expect(errorSummary.contains("code=42"))
    }

    @Test
    func updateConfigurationRequiresFeedAndSparkleKeyForAutomaticChecks() {
        let config = AppUpdateConfiguration(infoDictionary: [
            AppIdentity.updateFeedURLInfoKey: "https://example.com/appcast.xml",
            "SUPublicEDKey": "voicewink-public-key"
        ])

        #expect(config.supportsSparkleUpdater)
        #expect(config.supportsAutomaticChecks)
        #expect(config.sparkleFeedURL?.absoluteString == "https://example.com/appcast.xml")
    }

    @Test
    func updateConfigurationFallsBackToReleasePageWithoutSparkleKey() {
        let config = AppUpdateConfiguration(infoDictionary: [
            AppIdentity.releasesPageURLInfoKey: "https://github.com/example/VoiceWink/releases"
        ])

        #expect(!config.supportsSparkleUpdater)
        #expect(!config.supportsAutomaticChecks)
        #expect(config.supportsManualChecks)
        #expect(config.releasesPageURL?.absoluteString == "https://github.com/example/VoiceWink/releases")
    }

    @Test
    func powerModeConfigIgnoresRemovedScreenContextFields() throws {
        let json = """
        {
          "id": "7A5A50D3-3E53-4C6D-B37D-8CB7D9E0A1A1",
          "name": "Legacy",
          "emoji": "💼",
          "isAIEnhancementEnabled": true,
          "selectedPrompt": "6E0B1D11-5C98-4B8D-AE10-A8D5C6C2B0F8",
          "selectedLanguage": "en",
          "useScreenCapture": true,
          "selectedAIProvider": "OpenAI",
          "selectedAIModel": "gpt-4o-mini",
          "autoSendKey": "none",
          "isEnabled": true,
          "isDefault": false
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(PowerModeConfig.self, from: json)

        #expect(config.name == "Legacy")
        #expect(config.selectedLanguage == "en")
        #expect(config.selectedTranscriptionModelName == nil)
    }

    @Test @MainActor
    func recorderRoutesSelectedDeviceIntoCoreAudioRecorder() async throws {
        let fakeDeviceManager = FakeAudioDeviceManager(
            currentDevice: 42,
            availableDevices: [(id: 42, uid: "selected-device", name: "USB Mic")]
        )
        let fakeRecorder = FakeCoreAudioRecorder()
        let previousLastUsedDevice = UserDefaults.standard.string(forKey: "lastUsedMicrophoneDeviceID")

        defer {
            if let previousLastUsedDevice {
                UserDefaults.standard.set(previousLastUsedDevice, forKey: "lastUsedMicrophoneDeviceID")
            } else {
                UserDefaults.standard.removeObject(forKey: "lastUsedMicrophoneDeviceID")
            }
        }

        UserDefaults.standard.set("42", forKey: "lastUsedMicrophoneDeviceID")

        let recorder = Recorder(
            deviceManager: fakeDeviceManager,
            recorderFactory: { fakeRecorder },
            mediaController: FakeMediaController(),
            playbackController: FakePlaybackController()
        )
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        try await recorder.startRecording(toOutputFile: outputURL)
        recorder.stopRecording()

        #expect(fakeRecorder.startedDeviceID == 42)
        #expect(fakeRecorder.startedOutputURL == outputURL)
        #expect(fakeDeviceManager.isRecordingActive == false)
        #expect(fakeRecorder.stopCallCount == 1)
    }

    @Test @MainActor
    func configuredHotkeyLoadsAfterRelaunchAndTogglesRecorder() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let currentSupportDirectory = rootDirectory.appendingPathComponent("VoiceWinkSupport", isDirectory: true)
        let modelsDirectory = rootDirectory.appendingPathComponent("WhisperModels", isDirectory: true)

        let trackedKeys = [
            "selectedHotkey1",
            "selectedHotkey2",
            "hotkeyMode1",
            "hotkeyMode2",
        ]
        let previousDefaults = Dictionary(uniqueKeysWithValues: trackedKeys.map { key in
            (key, UserDefaults.standard.object(forKey: key))
        })
        let previousApplicationSupportOverride = AppPaths.applicationSupportDirectoryOverride

        defer {
            for key in trackedKeys {
                if let previousValue = previousDefaults[key] {
                    UserDefaults.standard.set(previousValue, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
            AppPaths.applicationSupportDirectoryOverride = previousApplicationSupportOverride
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        AppPaths.applicationSupportDirectoryOverride = currentSupportDirectory

        UserDefaults.standard.set(HotkeyManager.HotkeyOption.rightCommand.rawValue, forKey: "selectedHotkey1")
        UserDefaults.standard.set(HotkeyManager.HotkeyOption.none.rawValue, forKey: "selectedHotkey2")
        UserDefaults.standard.set(HotkeyManager.HotkeyMode.toggle.rawValue, forKey: "hotkeyMode1")
        UserDefaults.standard.set(HotkeyManager.HotkeyMode.hybrid.rawValue, forKey: "hotkeyMode2")

        let modelContainer = try makeTranscriptionContainer(at: rootDirectory.appendingPathComponent("hotkeys.store"), inMemoryOnly: true)
        let whisperModelManager = WhisperModelManager(modelsDirectory: modelsDirectory)
        let transcriptionModelManager = TranscriptionModelManager(
            whisperModelManager: whisperModelManager,
            fluidAudioModelManager: FluidAudioModelManager()
        )
        let engine = VoiceInkEngine(
            modelContext: modelContainer.mainContext,
            whisperModelManager: whisperModelManager,
            transcriptionModelManager: transcriptionModelManager
        )
        let fakeRecorderController = FakeRecorderHotkeyController()
        let hotkeyManager = HotkeyManager(
            engine: engine,
            recorderUIManager: fakeRecorderController,
            monitoringEnabled: false
        )

        #expect(hotkeyManager.selectedHotkey1 == .rightCommand)
        #expect(hotkeyManager.hotkeyMode1 == .toggle)

        await hotkeyManager.simulatePrimaryHotkeyCycle()
        await hotkeyManager.simulatePrimaryHotkeyCycle()

        #expect(fakeRecorderController.toggleCallCount == 2)
        #expect(fakeRecorderController.isMiniRecorderVisible == false)
    }
}

private final class FakeAudioDeviceManager: AudioDeviceManaging {
    var availableDevices: [(id: AudioDeviceID, uid: String, name: String)]
    var isRecordingActive = false

    private let currentDevice: AudioDeviceID

    init(currentDevice: AudioDeviceID, availableDevices: [(id: AudioDeviceID, uid: String, name: String)]) {
        self.currentDevice = currentDevice
        self.availableDevices = availableDevices
    }

    func getCurrentDevice() -> AudioDeviceID {
        currentDevice
    }
}

private final class FakeCoreAudioRecorder: CoreAudioRecording, @unchecked Sendable {
    var onAudioChunk: ((Data) -> Void)?
    var averagePower: Float = -160
    var peakPower: Float = -160
    var startedDeviceID: AudioDeviceID?
    var startedOutputURL: URL?
    var stopCallCount = 0

    func startRecording(toOutputFile url: URL, deviceID: AudioDeviceID) throws {
        startedOutputURL = url
        startedDeviceID = deviceID
    }

    func stopRecording() {
        stopCallCount += 1
    }

    func switchDevice(to newDeviceID: AudioDeviceID) throws {
        startedDeviceID = newDeviceID
    }
}

private final class FakeMediaController: SystemAudioMuting {
    func muteSystemAudio() async -> Bool { true }
    func unmuteSystemAudio() async {}
}

private final class FakePlaybackController: MediaPlaybackControlling {
    func pauseMedia() async {}
    func resumeMedia() async {}
}

@MainActor
private final class FakeRecorderHotkeyController: RecorderHotkeyControlling {
    var isMiniRecorderVisible = false
    var toggleCallCount = 0

    func toggleRecorderFromHotkey() async {
        toggleCallCount += 1
        isMiniRecorderVisible.toggle()
    }
}

@MainActor
private func makeTranscriptionContainer(at storeURL: URL, inMemoryOnly: Bool) throws -> ModelContainer {
    let schema = Schema([Transcription.self])

    if inMemoryOnly {
        let configuration = ModelConfiguration(
            "default",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: configuration)
    }

    try FileManager.default.createDirectory(
        at: storeURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )

    let configuration = ModelConfiguration(
        "default",
        schema: schema,
        url: storeURL,
        cloudKitDatabase: .none
    )
    return try ModelContainer(for: schema, configurations: configuration)
}
