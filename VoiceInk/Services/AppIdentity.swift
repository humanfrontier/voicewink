import Foundation

enum AppIdentity {
    static let displayName = "VoiceWink"

    static let bundleIdentifier = "com.prakashjoshipax.VoiceWink"

    static let cloudKitContainerIdentifier = "iCloud.com.prakashjoshipax.VoiceWink"

    static let bundledStarterWhisperModelName = "ggml-tiny.en"
    static let bundledStarterWhisperFilename = "ggml-tiny.en.bin"

    static let updateFeedURLInfoKey = "VoiceWinkUpdateFeedURL"
    static let releasesPageURLInfoKey = "VoiceWinkReleasesPageURL"
    static let updateFeedURLOverrideKey = "voicewink.updateFeedURLOverride"
    static let releasesPageURLOverrideKey = "voicewink.releasesPageURLOverride"

    #if LOCAL_BUILD
    static let accessibilityPasteWarningTitle =
        "VoiceWink copied the transcript. If paste stops working after a rebuild, re-add Accessibility access for the current app bundle."

    static let accessibilityPermissionHelp =
        "VoiceWink uses Accessibility permissions to paste text into other apps. Local `make local` builds use a stable self-signed VoiceWink identity, but macOS can still require the permission to be removed and re-added after a rebuild or if older VoiceWink entries are still present. If paste stops working, quit VoiceWink, remove every VoiceWink entry from Accessibility, add the current VoiceWink.app again, then relaunch it."
    #else
    static let accessibilityPasteWarningTitle =
        "VoiceWink copied the transcript. Enable Accessibility Access to paste automatically."

    static let accessibilityPermissionHelp =
        "VoiceWink uses Accessibility permissions to paste the transcribed text directly into other applications at your cursor's position. This allows for a seamless dictation experience across your Mac."
    #endif
}

enum AppLogRedaction {
    static func textSummary(_ text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let characterCount = trimmedText.count
        let wordCount = trimmedText.split(whereSeparator: \.isWhitespace).count

        return "characters=\(characterCount) words=\(wordCount) empty=\(trimmedText.isEmpty)"
    }

    static func changeSummary(before: String, after: String) -> String {
        "before{\(textSummary(before))} after{\(textSummary(after))} changed=\(before != after)"
    }

    static func errorSummary(_ error: Error) -> String {
        let nsError = error as NSError
        return "type=\(String(reflecting: type(of: error))) domain=\(nsError.domain) code=\(nsError.code)"
    }

    static func fileSummary(_ url: URL) -> String {
        let pathExtension = url.pathExtension.isEmpty ? "none" : url.pathExtension.lowercased()
        return "filenameLength=\(url.lastPathComponent.count) extension=\(pathExtension)"
    }

    static func urlSummary(_ text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedURL = URL(string: trimmedText)
        let scheme = parsedURL?.scheme ?? "unknown"
        let hasHost = parsedURL?.host != nil
        let hasPath = !(parsedURL?.path ?? "").isEmpty
        let hasQuery = parsedURL?.query != nil

        return "characters=\(trimmedText.count) scheme=\(scheme) hasHost=\(hasHost) hasPath=\(hasPath) hasQuery=\(hasQuery)"
    }
}
