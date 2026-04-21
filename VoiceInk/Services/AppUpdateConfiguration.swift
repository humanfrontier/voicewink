import Foundation

struct AppUpdateConfiguration: Equatable, Sendable {
    let sparkleFeedURL: URL?
    let releasesPageURL: URL?
    let sparklePublicEDKey: String?

    init(bundle: Bundle = .main, userDefaults: UserDefaults = .standard) {
        self.init(infoDictionary: bundle.infoDictionary ?? [:], userDefaults: userDefaults)
    }

    init(infoDictionary: [String: Any], userDefaults: UserDefaults = .standard) {
        sparkleFeedURL = Self.parseURL(
            primary: userDefaults.string(forKey: AppIdentity.updateFeedURLOverrideKey),
            fallback: infoDictionary[AppIdentity.updateFeedURLInfoKey] as? String
        )
        releasesPageURL = Self.parseURL(
            primary: userDefaults.string(forKey: AppIdentity.releasesPageURLOverrideKey),
            fallback: infoDictionary[AppIdentity.releasesPageURLInfoKey] as? String
        )
        sparklePublicEDKey = Self.normalizedString(infoDictionary["SUPublicEDKey"] as? String)
    }

    var supportsSparkleUpdater: Bool {
        sparkleFeedURL != nil && sparklePublicEDKey != nil
    }

    var supportsAutomaticChecks: Bool {
        supportsSparkleUpdater
    }

    var supportsManualChecks: Bool {
        supportsSparkleUpdater || releasesPageURL != nil
    }

    private static func parseURL(primary: String?, fallback: String?) -> URL? {
        if let primary = normalizedString(primary), let url = URL(string: primary) {
            return url
        }
        if let fallback = normalizedString(fallback), let url = URL(string: fallback) {
            return url
        }
        return nil
    }

    private static func normalizedString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
