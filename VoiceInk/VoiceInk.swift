import SwiftUI
import SwiftData
@preconcurrency import Sparkle
import AppKit
import OSLog
import AppIntents
import FluidAudio

@main
struct VoiceWinkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let container: ModelContainer
    let containerInitializationFailed: Bool

    @StateObject private var engine: VoiceInkEngine
    @StateObject private var whisperModelManager: WhisperModelManager
    @StateObject private var fluidAudioModelManager: FluidAudioModelManager
    @StateObject private var transcriptionModelManager: TranscriptionModelManager
    @StateObject private var recorderUIManager: RecorderUIManager
    @StateObject private var hotkeyManager: HotkeyManager
    @StateObject private var updaterViewModel: UpdaterViewModel
    @StateObject private var menuBarManager: MenuBarManager
    @StateObject private var activeWindowService = ActiveWindowService.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showMenuBarIcon = true

    // Audio cleanup manager for automatic deletion of old audio files
    private let audioCleanupManager = AudioCleanupManager.shared

    // Transcription auto-cleanup service for zero data retention
    private let transcriptionAutoCleanupService = TranscriptionAutoCleanupService.shared

    // Model prewarm service for optimizing model on wake from sleep
    @StateObject private var prewarmService: ModelPrewarmService

    init() {
        // Disable HTTP response caching — prevents API responses from being stored in Cache.db
        URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0)

        AppDefaults.registerDefaults()
        VoiceWinkCleanCutReset.applyIfNeeded()

        if UserDefaults.standard.object(forKey: "powerModeUIFlag") == nil {
            let hasEnabledPowerModes = PowerModeManager.shared.configurations.contains { $0.isEnabled }
            UserDefaults.standard.set(hasEnabledPowerModes, forKey: "powerModeUIFlag")
        }

        let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "Initialization")
        let schema = Schema([
            Transcription.self,
            VocabularyWord.self,
            WordReplacement.self
        ])
        var initializationFailed = false

        // Attempt 1: Try persistent storage
        if let persistentContainer = Self.createPersistentContainer(schema: schema, logger: logger) {
            container = persistentContainer
        }
        // Attempt 2: Try in-memory storage
        else if let memoryContainer = Self.createInMemoryContainer(schema: schema, logger: logger) {
            container = memoryContainer

            logger.warning("Using in-memory storage as fallback. Data will not persist between sessions.")

            // Show alert to user about storage issue
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Storage Warning"
                alert.informativeText = "VoiceWink couldn't access its storage location. Your transcriptions will not be saved between sessions."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
        // All attempts failed
        else {
            logger.critical("ModelContainer initialization failed")
            initializationFailed = true

            // Create minimal in-memory container to satisfy initialization
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            container = (try? ModelContainer(for: schema, configurations: [config])) ?? {
                preconditionFailure("Unable to create ModelContainer. SwiftData is unavailable.")
            }()
        }

        containerInitializationFailed = initializationFailed

        let updaterViewModel = UpdaterViewModel()
        _updaterViewModel = StateObject(wrappedValue: updaterViewModel)

        // 2. Create model managers
        let whisperModelManager = WhisperModelManager(modelsDirectory: AppPaths.modelsDirectory)
        let fluidAudioModelManager = FluidAudioModelManager()
        let transcriptionModelManager = TranscriptionModelManager(
            whisperModelManager: whisperModelManager,
            fluidAudioModelManager: fluidAudioModelManager
        )

        // 3. Create UI manager
        let recorderUIManager = RecorderUIManager()

        // 4. Create engine
        let engine = VoiceInkEngine(
            modelContext: container.mainContext,
            whisperModelManager: whisperModelManager,
            transcriptionModelManager: transcriptionModelManager
        )

        // 5. Configure circular deps
        recorderUIManager.configure(engine: engine, recorder: engine.recorder)
        engine.recorderUIManager = recorderUIManager

        // 6. Initialize model state
        whisperModelManager.createModelsDirectoryIfNeeded()
        do {
            try whisperModelManager.bootstrapBundledStarterModelIfNeeded()
        } catch {
            logger.error("❌ Failed to copy the bundled starter model: \(error.localizedDescription, privacy: .public)")
        }
        whisperModelManager.loadAvailableModels()
        transcriptionModelManager.refreshAllAvailableModels()
        transcriptionModelManager.loadCurrentTranscriptionModel()

        _whisperModelManager = StateObject(wrappedValue: whisperModelManager)
        _fluidAudioModelManager = StateObject(wrappedValue: fluidAudioModelManager)
        _transcriptionModelManager = StateObject(wrappedValue: transcriptionModelManager)
        _recorderUIManager = StateObject(wrappedValue: recorderUIManager)
        _engine = StateObject(wrappedValue: engine)

        // 7. Create other services that depend on engine
        let hotkeyManager = HotkeyManager(engine: engine, recorderUIManager: recorderUIManager)
        _hotkeyManager = StateObject(wrappedValue: hotkeyManager)

        let menuBarManager = MenuBarManager()
        _menuBarManager = StateObject(wrappedValue: menuBarManager)
        menuBarManager.configure(modelContainer: container, engine: engine)

        let activeWindowService = ActiveWindowService.shared
        activeWindowService.configure()
        _activeWindowService = StateObject(wrappedValue: activeWindowService)

        let prewarmService = ModelPrewarmService(
            transcriptionModelManager: transcriptionModelManager,
            whisperModelManager: whisperModelManager
        )
        _prewarmService = StateObject(wrappedValue: prewarmService)

        appDelegate.menuBarManager = menuBarManager

        // Ensure no lingering recording state from previous runs
        Task {
            await recorderUIManager.resetOnLaunch()
        }

        AppShortcuts.updateAppShortcutParameters()

        // Start cleanup service for the app's lifetime, not tied to window lifecycle
        TranscriptionAutoCleanupService.shared.startMonitoring(modelContext: container.mainContext)
    }

    // MARK: - Container Creation Helpers

    private static func createPersistentContainer(schema: Schema, logger: Logger) -> ModelContainer? {
        do {
            let appSupportURL = AppPaths.applicationSupportDirectory

            // Create the directory if it doesn't exist
            try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

            // Define storage locations
            let defaultStoreURL = appSupportURL.appendingPathComponent("default.store")
            let dictionaryStoreURL = appSupportURL.appendingPathComponent("dictionary.store")

            // Transcript configuration
            let transcriptSchema = Schema([Transcription.self])
            let transcriptConfig = ModelConfiguration(
                "default",
                schema: transcriptSchema,
                url: defaultStoreURL,
                cloudKitDatabase: .none
            )

            // Dictionary configuration
            let dictionarySchema = Schema([VocabularyWord.self, WordReplacement.self])
            #if LOCAL_BUILD
            let dictionaryCloudKit: ModelConfiguration.CloudKitDatabase = .none
            #else
            let dictionaryCloudKit: ModelConfiguration.CloudKitDatabase = .private(AppIdentity.cloudKitContainerIdentifier)
            #endif
            let dictionaryConfig = ModelConfiguration(
                "dictionary",
                schema: dictionarySchema,
                url: dictionaryStoreURL,
                cloudKitDatabase: dictionaryCloudKit
            )

            // Initialize container
            return try ModelContainer(
                for: schema,
                configurations: transcriptConfig, dictionaryConfig
            )
        } catch {
            logger.error("❌ Failed to create persistent ModelContainer: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func createInMemoryContainer(schema: Schema, logger: Logger) -> ModelContainer? {
        do {
            // Transcript configuration
            let transcriptSchema = Schema([Transcription.self])
            let transcriptConfig = ModelConfiguration(
                "default",
                schema: transcriptSchema,
                isStoredInMemoryOnly: true
            )

            // Dictionary configuration
            let dictionarySchema = Schema([VocabularyWord.self, WordReplacement.self])
            let dictionaryConfig = ModelConfiguration(
                "dictionary",
                schema: dictionarySchema,
                isStoredInMemoryOnly: true
            )

            return try ModelContainer(for: schema, configurations: transcriptConfig, dictionaryConfig)
        } catch {
            logger.error("❌ Failed to create in-memory ModelContainer: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                ContentView()
                    .environmentObject(engine)
                    .environmentObject(whisperModelManager)
                    .environmentObject(fluidAudioModelManager)
                    .environmentObject(transcriptionModelManager)
                    .environmentObject(recorderUIManager)
                    .environmentObject(hotkeyManager)
                    .environmentObject(updaterViewModel)
                    .environmentObject(menuBarManager)
                    .modelContainer(container)
                    .onAppear {
                        // Check if container initialization failed
                        if containerInitializationFailed {
                            let alert = NSAlert()
                            alert.messageText = "Critical Storage Error"
                            alert.informativeText = "VoiceWink cannot initialize its storage system. The app cannot continue.\n\nPlease try reinstalling the app or contact support if the issue persists."
                            alert.alertStyle = .critical
                            alert.addButton(withTitle: "Quit")
                            alert.runModal()

                            NSApplication.shared.terminate(nil)
                            return
                        }

                        updaterViewModel.silentlyCheckForUpdates()

                        // Start the automatic audio cleanup process only if transcript cleanup is not enabled
                        if !UserDefaults.standard.bool(forKey: "IsTranscriptionCleanupEnabled") {
                            audioCleanupManager.startAutomaticCleanup(modelContext: container.mainContext)
                        }

                        // Process any pending open-file request now that the main ContentView is ready.
                        if let pendingURL = appDelegate.pendingOpenFileURL {
                            NotificationCenter.default.post(name: .navigateToDestination, object: nil, userInfo: ["destination": "Transcribe Audio"])
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                NotificationCenter.default.post(name: .openFileForTranscription, object: nil, userInfo: ["url": pendingURL])
                            }
                            appDelegate.pendingOpenFileURL = nil
                        }
                    }
                    .background(WindowAccessor { window in
                        WindowManager.shared.configureWindow(window)
                    })
                    .onDisappear {
                        whisperModelManager.unloadModel()

                        // Stop the automatic audio cleanup process
                        audioCleanupManager.stopAutomaticCleanup()
                    }
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .environmentObject(hotkeyManager)
                    .environmentObject(engine)
                    .environmentObject(whisperModelManager)
                    .environmentObject(fluidAudioModelManager)
                    .environmentObject(transcriptionModelManager)
                    .environmentObject(recorderUIManager)
                    .frame(minWidth: 880, minHeight: 780)
                    .background(WindowAccessor { window in
                        if window.identifier == nil || window.identifier != NSUserInterfaceItemIdentifier("com.prakashjoshipax.voicewink.onboardingWindow") {
                            WindowManager.shared.configureOnboardingPanel(window)
                        }
                    })
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 950, height: 730)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }

            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updaterViewModel: updaterViewModel)
            }
        }

        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarView()
                .environmentObject(engine)
                .environmentObject(whisperModelManager)
                .environmentObject(fluidAudioModelManager)
                .environmentObject(transcriptionModelManager)
                .environmentObject(recorderUIManager)
                .environmentObject(hotkeyManager)
                .environmentObject(menuBarManager)
                .environmentObject(updaterViewModel)
        } label: {
            let image: NSImage = {
                $0.isTemplate = true
                let ratio = $0.size.height / $0.size.width
                $0.size.height = 22
                $0.size.width = 22 / ratio
                return $0
            }(NSImage(named: "menuBarIcon")!)

            Image(nsImage: image)
        }
        .menuBarExtraStyle(.menu)

        #if DEBUG
        WindowGroup("Debug") {
            Button("Toggle Menu Bar Only") {
                menuBarManager.isMenuBarOnly.toggle()
            }
        }
        #endif
    }
}

final class UpdaterViewModel: NSObject, ObservableObject, SPUUpdaterDelegate {
    private let configuration: AppUpdateConfiguration
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )
    private var canCheckObservation: NSKeyValueObservation?

    @Published private(set) var canCheckForUpdates = true
    @Published private(set) var supportsAutomaticChecks = false

    @MainActor
    init(configuration: AppUpdateConfiguration = AppUpdateConfiguration()) {
        self.configuration = configuration
        super.init()

        supportsAutomaticChecks = configuration.supportsAutomaticChecks

        canCheckObservation = updaterController.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            guard let self else { return }
            Task { @MainActor in
                self.canCheckForUpdates = self.configuration.supportsSparkleUpdater ? updater.canCheckForUpdates : true
            }
        }

        guard configuration.supportsSparkleUpdater else {
            canCheckForUpdates = true
            return
        }

        _ = updaterController.updater.clearFeedURLFromUserDefaults()
        updaterController.updater.automaticallyChecksForUpdates = UserDefaults.standard.object(forKey: "autoUpdateCheck") as? Bool ?? true
        updaterController.updater.updateCheckInterval = 24 * 60 * 60
        updaterController.startUpdater()
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        configuration.sparkleFeedURL?.absoluteString
    }

    @MainActor
    func toggleAutoUpdates(_ value: Bool) {
        guard configuration.supportsSparkleUpdater else { return }
        updaterController.updater.automaticallyChecksForUpdates = value
    }

    @MainActor
    func checkForUpdates() {
        guard configuration.supportsSparkleUpdater else {
            if let releasesPageURL = configuration.releasesPageURL {
                NSWorkspace.shared.open(releasesPageURL)
            } else {
                presentMissingUpdateConfigurationAlert()
            }
            return
        }

        updaterController.checkForUpdates(nil)
    }

    @MainActor
    func silentlyCheckForUpdates() {
        guard configuration.supportsSparkleUpdater else { return }
        guard UserDefaults.standard.object(forKey: "autoUpdateCheck") as? Bool ?? true else { return }
        updaterController.updater.checkForUpdatesInBackground()
    }

    @MainActor
    var automaticUpdateHelpText: String? {
        guard !supportsAutomaticChecks else { return nil }

        if configuration.releasesPageURL != nil {
            return "Automatic checks are disabled for this build until a VoiceWink Sparkle feed is configured. Manual checks still open the configured release page."
        }

        return "Automatic checks are disabled for this build until a VoiceWink update source is configured. Local builds can still use Check for Updates for pull-and-rebuild instructions."
    }

    @MainActor
    private func presentMissingUpdateConfigurationAlert() {
        let alert = NSAlert()
        alert.messageText = "Local Update Instructions"
        alert.informativeText = "This VoiceWink build does not define a release feed yet. To update locally, pull the latest VoiceWink changes and rebuild with `make local`. Once a VoiceWink release page or Sparkle feed is configured, Check for Updates will use it automatically."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject var updaterViewModel: UpdaterViewModel

    var body: some View {
        Button("Check for Updates…", action: updaterViewModel.checkForUpdates)
            .disabled(!updaterViewModel.canCheckForUpdates)
    }
}

struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                callback(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
