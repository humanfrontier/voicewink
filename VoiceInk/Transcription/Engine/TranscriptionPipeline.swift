import Foundation
import AVFoundation
import SwiftData
import os

/// Handles the full post-recording pipeline:
/// transcribe → filter → format → word-replace → save → paste → dismiss
@MainActor
class TranscriptionPipeline {
    private let modelContext: ModelContext
    private let serviceRegistry: TranscriptionServiceRegistry
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "TranscriptionPipeline")

    init(
        modelContext: ModelContext,
        serviceRegistry: TranscriptionServiceRegistry
    ) {
        self.modelContext = modelContext
        self.serviceRegistry = serviceRegistry
    }

    /// Run the full pipeline for a given transcription record.
    /// - Parameters:
    ///   - transcription: The pending Transcription SwiftData object to populate and save.
    ///   - audioURL: The recorded audio file.
    ///   - model: The transcription model to use.
    ///   - session: An active streaming session if one was prepared, otherwise nil.
    ///   - onStateChange: Called when the pipeline moves to a new recording state.
    ///   - shouldCancel: Returns true if the user requested cancellation.
    ///   - onCleanup: Called when cancellation is detected to release model resources.
    ///   - onDismiss: Called at the end to dismiss the recorder panel.
    func run(
        transcription: Transcription,
        audioURL: URL,
        model: any TranscriptionModel,
        session: TranscriptionSession?,
        onStateChange: @escaping (RecordingState) -> Void,
        shouldCancel: () -> Bool,
        onCleanup: @escaping () async -> Void,
        onDismiss: @escaping () async -> Void
    ) async {
        if shouldCancel() {
            await onCleanup()
            return
        }

        Task {
            let isSystemMuteEnabled = UserDefaults.standard.bool(forKey: "isSystemMuteEnabled")
            if isSystemMuteEnabled {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            SoundManager.shared.playStopSound()
        }

        var finalPastedText: String?
        logger.notice("🔄 Starting transcription...")

        do {
            let transcriptionStart = Date()
            var text: String
            if let session {
                text = try await session.transcribe(audioURL: audioURL)
            } else {
                text = try await serviceRegistry.transcribe(audioURL: audioURL, model: model)
            }
            logger.notice("📝 Transcript: \(text, privacy: .public)")
            text = TranscriptionOutputFilter.filter(text)
            logger.notice("📝 Output filter result: \(text, privacy: .public)")
            let transcriptionDuration = Date().timeIntervalSince(transcriptionStart)

            let powerModeManager = PowerModeManager.shared
            let activePowerModeConfig = powerModeManager.currentActiveConfiguration
            let powerModeName = (activePowerModeConfig?.isEnabled == true) ? activePowerModeConfig?.name : nil
            let powerModeEmoji = (activePowerModeConfig?.isEnabled == true) ? activePowerModeConfig?.emoji : nil

            if shouldCancel() { await onCleanup(); return }

            text = text.trimmingCharacters(in: .whitespacesAndNewlines)

            if UserDefaults.standard.bool(forKey: "IsTextFormattingEnabled") {
                text = WhisperTextFormatter.format(text)
                logger.notice("📝 Formatted transcript: \(text, privacy: .public)")
            }

            text = WordReplacementService.shared.applyReplacements(to: text, using: modelContext)
            logger.notice("📝 WordReplacement: \(text, privacy: .public)")

            let audioAsset = AVURLAsset(url: audioURL)
            let actualDuration = (try? CMTimeGetSeconds(await audioAsset.load(.duration))) ?? 0.0

            transcription.text = text
            transcription.duration = actualDuration
            transcription.transcriptionModelName = model.displayName
            transcription.transcriptionDuration = transcriptionDuration
            transcription.powerModeName = powerModeName
            transcription.powerModeEmoji = powerModeEmoji
            finalPastedText = text

            transcription.transcriptionStatus = TranscriptionStatus.completed.rawValue

        } catch {
            let errorDescription = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            let recoverySuggestion = (error as? LocalizedError)?.recoverySuggestion ?? ""
            let fullErrorText = recoverySuggestion.isEmpty ? errorDescription : "\(errorDescription) \(recoverySuggestion)"

            transcription.text = "Transcription Failed: \(fullErrorText)"
            transcription.transcriptionStatus = TranscriptionStatus.failed.rawValue
        }

        try? modelContext.save()
        NotificationCenter.default.post(name: .transcriptionCompleted, object: transcription)

        if shouldCancel() { await onCleanup(); return }

        if let textToPaste = finalPastedText,
           transcription.transcriptionStatus == TranscriptionStatus.completed.rawValue {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                let appendSpace = UserDefaults.standard.bool(forKey: "AppendTrailingSpace")
                let pasteOutcome = CursorPaster.pasteAtCursor(textToPaste + (appendSpace ? " " : ""))

                if case .copiedToClipboardAccessibilityRequired = pasteOutcome {
                    NotificationManager.shared.showNotification(
                        title: AppIdentity.accessibilityPasteWarningTitle,
                        type: .warning,
                        duration: 5.0,
                        actionButton: (
                            label: "Permissions",
                            action: {
                                CursorPaster.openAccessibilitySettings()
                            }
                        )
                    )
                }

                let powerMode = PowerModeManager.shared
                if let activeConfig = powerMode.currentActiveConfiguration, activeConfig.autoSendKey.isEnabled {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        CursorPaster.performAutoSend(activeConfig.autoSendKey)
                    }
                }
            }
        }

        await onDismiss()
    }
}
