import Foundation
import SwiftUI
import os

@MainActor
class TranscriptionModelManager: ObservableObject {
    @Published var currentTranscriptionModel: (any TranscriptionModel)?
    @Published var allAvailableModels: [any TranscriptionModel] = TranscriptionModelRegistry.models

    private weak var whisperModelManager: WhisperModelManager?
    private weak var fluidAudioModelManager: FluidAudioModelManager?
    private let userDefaults: UserDefaults

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "TranscriptionModelManager")

    init(
        whisperModelManager: WhisperModelManager,
        fluidAudioModelManager: FluidAudioModelManager,
        userDefaults: UserDefaults = .standard
    ) {
        self.whisperModelManager = whisperModelManager
        self.fluidAudioModelManager = fluidAudioModelManager
        self.userDefaults = userDefaults

        // Wire up deletion callbacks so each manager notifies this manager.
        whisperModelManager.onModelDeleted = { [weak self] modelName in
            self?.handleModelDeleted(modelName)
        }
        fluidAudioModelManager.onModelDeleted = { [weak self] modelName in
            self?.handleModelDeleted(modelName)
        }

        // Wire up "models changed" callbacks so this manager rebuilds allAvailableModels.
        whisperModelManager.onModelsChanged = { [weak self] in
            self?.refreshAllAvailableModels()
        }
        fluidAudioModelManager.onModelsChanged = { [weak self] in
            self?.refreshAllAvailableModels()
        }
    }

    // MARK: - Computed: usable models

    var usableModels: [any TranscriptionModel] {
        allAvailableModels.filter { model in
            switch model.provider {
            case .whisper:
                return whisperModelManager?.availableModels.contains { $0.name == model.name } ?? false
            case .fluidAudio:
                return fluidAudioModelManager?.isFluidAudioModelDownloaded(named: model.name) ?? false
            case .nativeApple:
                return {
                    if #available(macOS 26, *) {
                        return true
                    }
                    return false
                }()
            }
        }
    }

    // MARK: - Model loading from UserDefaults

    func loadCurrentTranscriptionModel() {
        if let savedModelName = userDefaults.string(forKey: "CurrentTranscriptionModel"),
           let savedModel = allAvailableModels.first(where: { $0.name == savedModelName }) {
            currentTranscriptionModel = savedModel
            return
        }

        if let bundledModel = fallbackModelSelection() {
            setDefaultTranscriptionModel(bundledModel)
        }
    }

    // MARK: - Set default model

    func setDefaultTranscriptionModel(_ model: any TranscriptionModel) {
        self.currentTranscriptionModel = model
        userDefaults.set(model.name, forKey: "CurrentTranscriptionModel")

        if model.provider != .whisper {
            whisperModelManager?.loadedWhisperModel = nil
            whisperModelManager?.isModelLoaded = true
        }

        NotificationCenter.default.post(name: .didChangeModel, object: nil, userInfo: ["modelName": model.name])
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }

    // MARK: - Refresh all available models

    func refreshAllAvailableModels() {
        let currentModelName = currentTranscriptionModel?.name
        var models = TranscriptionModelRegistry.models

        for whisperModel in whisperModelManager?.availableModels ?? [] {
            if !models.contains(where: { $0.name == whisperModel.name }) {
                let importedModel = ImportedWhisperModel(fileBaseName: whisperModel.name)
                models.append(importedModel)
            }
        }

        allAvailableModels = models

        if let currentName = currentModelName,
           let updatedModel = allAvailableModels.first(where: { $0.name == currentName }) {
            setDefaultTranscriptionModel(updatedModel)
        } else if currentModelName == nil,
                  userDefaults.string(forKey: "CurrentTranscriptionModel") == nil,
                  let fallbackModel = fallbackModelSelection() {
            setDefaultTranscriptionModel(fallbackModel)
        }
    }

    // MARK: - Clear current model

    func clearCurrentTranscriptionModel() {
        currentTranscriptionModel = nil
        userDefaults.removeObject(forKey: "CurrentTranscriptionModel")
    }

    // MARK: - Handle model deletion callback

    /// Called by WhisperModelManager.onModelDeleted or FluidAudioModelManager.onModelDeleted.
    func handleModelDeleted(_ modelName: String) {
        if currentTranscriptionModel?.name == modelName {
            currentTranscriptionModel = nil
            userDefaults.removeObject(forKey: "CurrentTranscriptionModel")
            whisperModelManager?.loadedWhisperModel = nil
            whisperModelManager?.isModelLoaded = false
            userDefaults.removeObject(forKey: "CurrentModel")
        }
        refreshAllAvailableModels()
    }

    private func fallbackModelSelection() -> (any TranscriptionModel)? {
        if let bundledModel = allAvailableModels.first(where: { $0.name == AppIdentity.bundledStarterWhisperModelName }) {
            return bundledModel
        }

        return allAvailableModels.first(where: { $0.provider == .whisper })
    }
}
