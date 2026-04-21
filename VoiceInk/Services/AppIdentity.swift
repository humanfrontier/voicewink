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
