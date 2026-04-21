import Foundation
import KeyboardShortcuts

enum AutoSendKey: String, Codable, CaseIterable {
    case none = "none"
    case enter = "enter"
    case shiftEnter = "shiftEnter"
    case commandEnter = "commandEnter"

    var displayName: String {
        switch self {
        case .none: return "None"
        case .enter: return "Return (⏎)"
        case .shiftEnter: return "Shift + Return (⇧⏎)"
        case .commandEnter: return "Command + Return (⌘⏎)"
        }
    }

    var isEnabled: Bool {
        self != .none
    }
}

struct PowerModeConfig: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var emoji: String
    var appConfigs: [AppConfig]?
    var urlConfigs: [URLConfig]?
    var selectedTranscriptionModelName: String?
    var selectedLanguage: String?
    var autoSendKey: AutoSendKey = .none
    var isEnabled: Bool = true
    var isDefault: Bool = false
    var hotkeyShortcut: String? = nil
        
    init(id: UUID = UUID(), name: String, emoji: String, appConfigs: [AppConfig]? = nil,
         urlConfigs: [URLConfig]? = nil, selectedTranscriptionModelName: String? = nil,
         selectedLanguage: String? = nil, autoSendKey: AutoSendKey = .none, isEnabled: Bool = true, isDefault: Bool = false, hotkeyShortcut: String? = nil) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.appConfigs = appConfigs
        self.urlConfigs = urlConfigs
        self.selectedTranscriptionModelName = selectedTranscriptionModelName ?? UserDefaults.standard.string(forKey: "CurrentTranscriptionModel")
        self.selectedLanguage = selectedLanguage ?? UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "en"
        self.autoSendKey = autoSendKey
        self.isEnabled = isEnabled
        self.isDefault = isDefault
        self.hotkeyShortcut = hotkeyShortcut
    }
    
    static func == (lhs: PowerModeConfig, rhs: PowerModeConfig) -> Bool {
        lhs.id == rhs.id
    }
}

struct AppConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var bundleIdentifier: String
    var appName: String
    
    init(id: UUID = UUID(), bundleIdentifier: String, appName: String) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
    }
    
    static func == (lhs: AppConfig, rhs: AppConfig) -> Bool {
        lhs.id == rhs.id
    }
}

struct URLConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var url: String
    
    init(id: UUID = UUID(), url: String) {
        self.id = id
        self.url = url
    }
    
    static func == (lhs: URLConfig, rhs: URLConfig) -> Bool {
        lhs.id == rhs.id
    }
}

class PowerModeManager: ObservableObject {
    static let shared = PowerModeManager()
    @Published var configurations: [PowerModeConfig] = []
    @Published var activeConfiguration: PowerModeConfig?

    private let configKey = "powerModeConfigurationsV2"
    private let activeConfigIdKey = "activeConfigurationId"

    private init() {
        loadConfigurations()

        if let activeConfigIdString = UserDefaults.standard.string(forKey: activeConfigIdKey),
           let activeConfigId = UUID(uuidString: activeConfigIdString) {
            activeConfiguration = configurations.first { $0.id == activeConfigId }
        } else {
            activeConfiguration = nil
        }
    }

    private func loadConfigurations() {
        if let data = UserDefaults.standard.data(forKey: configKey),
           let configs = try? JSONDecoder().decode([PowerModeConfig].self, from: data) {
            configurations = configs
        }
    }

    func saveConfigurations() {
        if let data = try? JSONEncoder().encode(configurations) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
        NotificationCenter.default.post(name: NSNotification.Name("PowerModeConfigurationsDidChange"), object: nil)
    }

    func addConfiguration(_ config: PowerModeConfig) {
        if !configurations.contains(where: { $0.id == config.id }) {
            configurations.append(config)
            saveConfigurations()
        }
    }

    func removeConfiguration(with id: UUID) {
        KeyboardShortcuts.setShortcut(nil, for: .powerMode(id: id))
        configurations.removeAll { $0.id == id }
        saveConfigurations()
    }

    func getConfiguration(with id: UUID) -> PowerModeConfig? {
        return configurations.first { $0.id == id }
    }

    func updateConfiguration(_ config: PowerModeConfig) {
        if let index = configurations.firstIndex(where: { $0.id == config.id }) {
            configurations[index] = config
            saveConfigurations()
        }
    }

    func moveConfigurations(fromOffsets: IndexSet, toOffset: Int) {
        configurations.move(fromOffsets: fromOffsets, toOffset: toOffset)
        saveConfigurations()
    }

    func getConfigurationForURL(_ url: String) -> PowerModeConfig? {
        let cleanedURL = cleanURL(url)
        
        for config in configurations.filter({ $0.isEnabled }) {
            if let urlConfigs = config.urlConfigs {
                for urlConfig in urlConfigs {
                    let configURL = cleanURL(urlConfig.url)
                    
                    if cleanedURL.contains(configURL) {
                        return config
                    }
                }
            }
        }
        return nil
    }
    
    func getConfigurationForApp(_ bundleId: String) -> PowerModeConfig? {
        for config in configurations.filter({ $0.isEnabled }) {
            if let appConfigs = config.appConfigs {
                if appConfigs.contains(where: { $0.bundleIdentifier == bundleId }) {
                    return config
                }
            }
        }
        return nil
    }
    
    func getDefaultConfiguration() -> PowerModeConfig? {
        return configurations.first { $0.isEnabled && $0.isDefault }
    }
    
    func hasDefaultConfiguration() -> Bool {
        return configurations.contains { $0.isDefault }
    }
    
    func setAsDefault(configId: UUID, skipSave: Bool = false) {
        for index in configurations.indices {
            configurations[index].isDefault = false
        }

        if let index = configurations.firstIndex(where: { $0.id == configId }) {
            configurations[index].isDefault = true
        }

        if !skipSave {
            saveConfigurations()
        }
    }
    
    func enableConfiguration(with id: UUID) {
        if let index = configurations.firstIndex(where: { $0.id == id }) {
            configurations[index].isEnabled = true
            saveConfigurations()
        }
    }
    
    func disableConfiguration(with id: UUID) {
        if let index = configurations.firstIndex(where: { $0.id == id }) {
            configurations[index].isEnabled = false
            saveConfigurations()
        }
    }
    
    var enabledConfigurations: [PowerModeConfig] {
        return configurations.filter { $0.isEnabled }
    }

    func addAppConfig(_ appConfig: AppConfig, to config: PowerModeConfig) {
        if var updatedConfig = configurations.first(where: { $0.id == config.id }) {
            var configs = updatedConfig.appConfigs ?? []
            configs.append(appConfig)
            updatedConfig.appConfigs = configs
            updateConfiguration(updatedConfig)
        }
    }

    func removeAppConfig(_ appConfig: AppConfig, from config: PowerModeConfig) {
        if var updatedConfig = configurations.first(where: { $0.id == config.id }) {
            updatedConfig.appConfigs?.removeAll(where: { $0.id == appConfig.id })
            updateConfiguration(updatedConfig)
        }
    }

    func addURLConfig(_ urlConfig: URLConfig, to config: PowerModeConfig) {
        if var updatedConfig = configurations.first(where: { $0.id == config.id }) {
            var configs = updatedConfig.urlConfigs ?? []
            configs.append(urlConfig)
            updatedConfig.urlConfigs = configs
            updateConfiguration(updatedConfig)
        }
    }

    func removeURLConfig(_ urlConfig: URLConfig, from config: PowerModeConfig) {
        if var updatedConfig = configurations.first(where: { $0.id == config.id }) {
            updatedConfig.urlConfigs?.removeAll(where: { $0.id == urlConfig.id })
            updateConfiguration(updatedConfig)
        }
    }

    func cleanURL(_ url: String) -> String {
        return url.lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func setActiveConfiguration(_ config: PowerModeConfig?) {
        activeConfiguration = config
        UserDefaults.standard.set(config?.id.uuidString, forKey: activeConfigIdKey)
        self.objectWillChange.send()
    }

    var currentActiveConfiguration: PowerModeConfig? {
        return activeConfiguration
    }

    func getAllAvailableConfigurations() -> [PowerModeConfig] {
        return configurations
    }

    func isEmojiInUse(_ emoji: String) -> Bool {
        return configurations.contains { $0.emoji == emoji }
    }
} 
