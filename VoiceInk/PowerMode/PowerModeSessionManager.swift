import Foundation
import AppKit
import OSLog

struct ApplicationState: Codable {
    var selectedLanguage: String?
    var transcriptionModelName: String?
}

struct PowerModeSession: Codable {
    let id: UUID
    let startTime: Date
    var originalState: ApplicationState
}

@MainActor
class PowerModeSessionManager {
    static let shared = PowerModeSessionManager()
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "PowerModeSessionManager")
    private let sessionKey = "powerModeActiveSession.v1"
    private var isApplyingPowerModeConfig = false

    private weak var stateProvider: (any PowerModeStateProvider)?

    private init() {
        recoverSession()
    }

    /// Configure with new VoiceInkEngine-based provider.
    func configure(engine: any PowerModeStateProvider) {
        self.stateProvider = engine
    }

    func beginSession(with config: PowerModeConfig) async {
        guard let stateProvider = stateProvider else {
            logger.error("PowerModeSessionManager beginSession called before configuration")
            return
        }

        // Only capture baseline if NO session exists
        if loadSession() == nil {
            let originalState = ApplicationState(
                selectedLanguage: UserDefaults.standard.string(forKey: "SelectedLanguage"),
                transcriptionModelName: stateProvider.currentTranscriptionModel?.name
            )

            let newSession = PowerModeSession(
                id: UUID(),
                startTime: Date(),
                originalState: originalState
            )
            saveSession(newSession)

            NotificationCenter.default.addObserver(self, selector: #selector(updateSessionSnapshot), name: .AppSettingsDidChange, object: nil)
        }

        // Always apply the new configuration
        isApplyingPowerModeConfig = true
        await applyConfiguration(config)
        isApplyingPowerModeConfig = false
    }

    var hasActiveSession: Bool {
        return loadSession() != nil
    }

    func endSession() async {
        guard let session = loadSession() else { return }

        isApplyingPowerModeConfig = true
        await restoreState(session.originalState)
        isApplyingPowerModeConfig = false

        NotificationCenter.default.removeObserver(self, name: .AppSettingsDidChange, object: nil)

        clearSession()
    }

    @objc func updateSessionSnapshot() {
        guard !isApplyingPowerModeConfig else { return }

        guard var session = loadSession(),
              let stateProvider = stateProvider else { return }

        let updatedState = ApplicationState(
            selectedLanguage: UserDefaults.standard.string(forKey: "SelectedLanguage"),
            transcriptionModelName: stateProvider.currentTranscriptionModel?.name
        )

        session.originalState = updatedState
        saveSession(session)
    }

    private func applyConfiguration(_ config: PowerModeConfig) async {
        guard let stateProvider = stateProvider else { return }

        await MainActor.run {
            if let language = config.selectedLanguage {
                UserDefaults.standard.set(language, forKey: "SelectedLanguage")
                NotificationCenter.default.post(name: .languageDidChange, object: nil)
            }
        }

        if let modelName = config.selectedTranscriptionModelName,
           let selectedModel = await stateProvider.allAvailableModels.first(where: { $0.name == modelName }),
           stateProvider.currentTranscriptionModel?.name != modelName {
            await handleModelChange(to: selectedModel)
        }

        await MainActor.run {
            NotificationCenter.default.post(name: .powerModeConfigurationApplied, object: nil)
        }
    }

    private func restoreState(_ state: ApplicationState) async {
        guard let stateProvider = stateProvider else { return }

        await MainActor.run {
            if let language = state.selectedLanguage {
                UserDefaults.standard.set(language, forKey: "SelectedLanguage")
                NotificationCenter.default.post(name: .languageDidChange, object: nil)
            }
        }

        if let modelName = state.transcriptionModelName,
           let selectedModel = await stateProvider.allAvailableModels.first(where: { $0.name == modelName }),
           stateProvider.currentTranscriptionModel?.name != modelName {
            await handleModelChange(to: selectedModel)
        }
    }

    private func handleModelChange(to newModel: any TranscriptionModel) async {
        guard let stateProvider = stateProvider else { return }

        await stateProvider.setDefaultTranscriptionModel(newModel)

        switch newModel.provider {
        case .whisper:
            await stateProvider.cleanupModelResources()
            if let whisperModel = await stateProvider.availableModels.first(where: { $0.name == newModel.name }) {
                do {
                    try await stateProvider.loadModel(whisperModel)
                } catch {
                    logger.error("Power Mode failed to load local model \(whisperModel.name, privacy: .public): \(AppLogRedaction.errorSummary(error), privacy: .public)")
                }
            }
        case .fluidAudio:
            await stateProvider.cleanupModelResources()
        default:
            await stateProvider.cleanupModelResources()
        }
    }

    private func recoverSession() {
        guard loadSession() != nil else { return }
        logger.notice("Recovering abandoned Power Mode session")
        Task {
            await endSession()
        }
    }

    private func saveSession(_ session: PowerModeSession) {
        do {
            let data = try JSONEncoder().encode(session)
            UserDefaults.standard.set(data, forKey: sessionKey)
        } catch {
            logger.error("Failed to save Power Mode session: \(AppLogRedaction.errorSummary(error), privacy: .public)")
        }
    }

    private func loadSession() -> PowerModeSession? {
        guard let data = UserDefaults.standard.data(forKey: sessionKey) else { return nil }
        do {
            return try JSONDecoder().decode(PowerModeSession.self, from: data)
        } catch {
            logger.error("Failed to load Power Mode session: \(AppLogRedaction.errorSummary(error), privacy: .public)")
            return nil
        }
    }

    private func clearSession() {
        UserDefaults.standard.removeObject(forKey: sessionKey)
    }
}
