import Foundation

enum AppPaths {
    static let applicationSupportOverrideEnvironmentKey = "VOICEWINK_APP_SUPPORT_OVERRIDE"

    static var applicationSupportDirectoryOverride: URL?

    static let resourceModelsSubdirectoryCandidates = [
        "models",
        "Resources/models",
    ]

    private static var applicationSupportRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private static func overrideURL(
        directOverride: URL?,
        environmentKey: String
    ) -> URL? {
        if let directOverride {
            return directOverride
        }

        guard let overridePath = ProcessInfo.processInfo.environment[environmentKey],
              overridePath.isEmpty == false else {
            return nil
        }

        return URL(fileURLWithPath: overridePath, isDirectory: true)
    }

    static var applicationSupportDirectory: URL {
        if let overrideURL = overrideURL(
            directOverride: applicationSupportDirectoryOverride,
            environmentKey: applicationSupportOverrideEnvironmentKey
        ) {
            return overrideURL
        }

        return applicationSupportRoot.appendingPathComponent(AppIdentity.bundleIdentifier, isDirectory: true)
    }

    static var modelsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("WhisperModels", isDirectory: true)
    }

    static var recordingsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Recordings", isDirectory: true)
    }

    static var customSoundsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("CustomSounds", isDirectory: true)
    }

    static func bundledModelURL(filename: String) -> URL? {
        for subdirectory in resourceModelsSubdirectoryCandidates {
            if let url = Bundle.main.url(forResource: filename, withExtension: nil, subdirectory: subdirectory) {
                return url
            }
        }

        return Bundle.main.url(forResource: filename, withExtension: nil)
    }
}
