import Foundation
import AppKit
import OSLog
import SelectedTextKit

private let selectedTextServiceLogger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "SelectedTextService")

class SelectedTextService {
    static func fetchSelectedText() async -> String? {
        let strategies: [TextStrategy] = [.accessibility, .menuAction]
        do {
            let selectedText = try await SelectedTextManager.shared.getSelectedText(strategies: strategies)
            return selectedText
        } catch {
            selectedTextServiceLogger.error("Failed to get selected text: \(AppLogRedaction.errorSummary(error), privacy: .public)")
            return nil
        }
    }
}
