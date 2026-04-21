import Foundation
import OSLog
import SwiftData

class LastTranscriptionService: ObservableObject {
    private static let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "LastTranscriptionService")
    
    static func getLastTranscription(from modelContext: ModelContext) -> Transcription? {
        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        
        do {
            let transcriptions = try modelContext.fetch(descriptor)
            return transcriptions.first
        } catch {
            logger.error("Failed to fetch last transcription: \(AppLogRedaction.errorSummary(error), privacy: .public)")
            return nil
        }
    }
    
    static func copyLastTranscription(from modelContext: ModelContext) {
        guard let lastTranscription = getLastTranscription(from: modelContext) else {
            Task { @MainActor in
                NotificationManager.shared.showNotification(
                    title: "No transcription available",
                    type: .error
                )
            }
            return
        }
        
        let success = ClipboardManager.copyToClipboard(lastTranscription.text)
        
        Task { @MainActor in
            if success {
                NotificationManager.shared.showNotification(
                    title: "Last transcription copied",
                    type: .success
                )
            } else {
                NotificationManager.shared.showNotification(
                    title: "Failed to copy transcription",
                    type: .error
                )
            }
        }
    }

    static func pasteLastTranscription(from modelContext: ModelContext) {
        guard let lastTranscription = getLastTranscription(from: modelContext) else {
            Task { @MainActor in
                NotificationManager.shared.showNotification(
                    title: "No transcription available",
                    type: .error
                )
            }
            return
        }
        
        let textToPaste = lastTranscription.text

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let pasteOutcome = CursorPaster.pasteAtCursor(textToPaste)

            if case .copiedToClipboardAccessibilityRequired = pasteOutcome {
                Task { @MainActor in
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
            }
        }
    }
    
    static func retryLastTranscription(from modelContext: ModelContext, transcriptionModelManager: TranscriptionModelManager, serviceRegistry: TranscriptionServiceRegistry) {
        Task { @MainActor in
            guard let lastTranscription = getLastTranscription(from: modelContext),
                  let audioURLString = lastTranscription.audioFileURL,
                  let audioURL = URL(string: audioURLString),
                  FileManager.default.fileExists(atPath: audioURL.path) else {
                NotificationManager.shared.showNotification(
                    title: "Cannot retry: Audio file not found",
                    type: .error
                )
                return
            }

            guard let currentModel = transcriptionModelManager.currentTranscriptionModel else {
                NotificationManager.shared.showNotification(
                    title: "No transcription model selected",
                    type: .error
                )
                return
            }

            let transcriptionService = AudioTranscriptionService(
                modelContext: modelContext,
                serviceRegistry: serviceRegistry
            )
            do {
                let newTranscription = try await transcriptionService.retranscribeAudio(from: audioURL, using: currentModel)

                _ = ClipboardManager.copyToClipboard(newTranscription.text)

                NotificationManager.shared.showNotification(
                    title: "Copied to clipboard",
                    type: .success
                )
            } catch {
                logger.error("Retry last transcription failed: \(AppLogRedaction.errorSummary(error), privacy: .public)")
                NotificationManager.shared.showNotification(
                    title: "Retry failed: \(error.localizedDescription)",
                    type: .error
                )
            }
        }
    }
}
