import Foundation
import OSLog

enum VoiceWinkCleanCutReset {
    private static let markerKey = "voicewink-clean-cut-v1-applied"
    private static let transcriptStoreArtifacts = [
        "default.store",
        "default.store-shm",
        "default.store-wal",
    ]
    private static let obsoleteDefaultsKeys = [
        "activeConfigurationId",
        "customCloudModels",
        "customPromptsData",
        "EnhancementRetryOnTimeout",
        "EnhancementTimeoutSeconds",
        "isAIEnhancementEnabled",
        "isToggleEnhancementShortcutEnabled",
        "ollamaBaseURL",
        "ollamaSelectedModel",
        "powerModeActiveSession.v1",
        "powerModeConfigurationsV2",
        "selectedAIModel",
        "selectedAIProvider",
        "selectedPrompt",
        "selectedPromptId",
        "ShortEnhancementWordThreshold",
        "SkipShortEnhancement",
        "streaming-keys-migrated",
        "useClipboardContext",
    ]

    static func applyIfNeeded(
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        appSupportDirectory: URL = AppPaths.applicationSupportDirectory,
        logger: Logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "CleanCutReset")
    ) {
        guard !userDefaults.bool(forKey: markerKey) else { return }

        clearTranscriptStore(fileManager: fileManager, appSupportDirectory: appSupportDirectory, logger: logger)
        clearLegacyDefaults(userDefaults: userDefaults)

        userDefaults.set(true, forKey: markerKey)
        logger.notice("Applied one-time VoiceWink clean-cut reset")
    }

    private static func clearTranscriptStore(fileManager: FileManager, appSupportDirectory: URL, logger: Logger) {
        for artifact in transcriptStoreArtifacts {
            let url = appSupportDirectory.appendingPathComponent(artifact)
            guard fileManager.fileExists(atPath: url.path) else { continue }

            do {
                try fileManager.removeItem(at: url)
                logger.notice("Removed legacy transcript store artifact: \(artifact, privacy: .public)")
            } catch {
                logger.error("Failed to remove transcript store artifact \(artifact, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func clearLegacyDefaults(userDefaults: UserDefaults) {
        for key in obsoleteDefaultsKeys {
            userDefaults.removeObject(forKey: key)
        }
    }
}
