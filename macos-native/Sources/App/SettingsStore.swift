import Foundation
import Combine
import Security

public enum KeychainHelper {
    public static let service = "com.gistyt.app"
    public static let account = "GeminiAPIKey"

    @discardableResult
    public static func saveKey(_ key: String) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        if key.isEmpty {
            SecItemDelete(query as CFDictionary)
            return true
        }

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var newQuery = query
            newQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(newQuery as CFDictionary, nil)
            return addStatus == errSecSuccess
        }
        return status == errSecSuccess
    }

    public static func loadKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, let key = String(data: data, encoding: .utf8) {
            return key
        }
        return nil
    }

    @discardableResult
    public static func deleteKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

public final class SettingsStore: ObservableObject {
    public static let shared = SettingsStore()

    private let defaults = UserDefaults.standard
    private let keyDefaultsKey = "gistYT_GeminiAPIKey"
    private let saveDirDefaultsKey = "gistYT_SaveDirectory"
    private let langDefaultsKey = "gistYT_Languages"
    private let browserCookiesKey = "gistYT_BrowserCookies"

    // Legacy fallback keys
    private let legacyKeyDefaultsKey = "GistYT_GeminiAPIKey"
    private let legacySaveDirDefaultsKey = "GistYT_SaveDirectory"
    private let legacyLangDefaultsKey = "GistYT_Languages"
    private let legacyBrowserCookiesKey = "GistYT_BrowserCookies"

    @Published public var apiKey: String = "" {
        didSet {
            KeychainHelper.saveKey(apiKey)
            // Remove from defaults if it was previously stored there
            defaults.removeObject(forKey: keyDefaultsKey)
            defaults.removeObject(forKey: legacyKeyDefaultsKey)
        }
    }

    @Published public var saveDirectoryPath: String = "" {
        didSet {
            defaults.set(saveDirectoryPath, forKey: saveDirDefaultsKey)
        }
    }

    @Published public var languagePreferences: String = "en" {
        didSet {
            defaults.set(languagePreferences, forKey: langDefaultsKey)
        }
    }

    @Published public var browserCookies: String = "none" {
        didSet {
            defaults.set(browserCookies, forKey: browserCookiesKey)
        }
    }

    public init() {
        // Load API key from Keychain first
        if let keychainKey = KeychainHelper.loadKey(), !keychainKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.apiKey = keychainKey
        } else if let saved = (defaults.string(forKey: keyDefaultsKey) ?? defaults.string(forKey: legacyKeyDefaultsKey)), !saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Migrate from legacy UserDefaults to Keychain
            self.apiKey = saved
            KeychainHelper.saveKey(saved)
            defaults.removeObject(forKey: keyDefaultsKey)
            defaults.removeObject(forKey: legacyKeyDefaultsKey)
        } else if let envKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !envKey.isEmpty {
            self.apiKey = envKey
        } else if let foundKey = Self.findEnvFileKey() {
            self.apiKey = foundKey
        }

        // Save directory
        if let savedDir = defaults.string(forKey: saveDirDefaultsKey) ?? defaults.string(forKey: legacySaveDirDefaultsKey), !savedDir.isEmpty {
            self.saveDirectoryPath = savedDir
        } else {
            self.saveDirectoryPath = StorageService.defaultBaseDirectory.path
        }

        // Language preferences
        if let savedLang = defaults.string(forKey: langDefaultsKey) ?? defaults.string(forKey: legacyLangDefaultsKey), !savedLang.isEmpty {
            self.languagePreferences = savedLang
        }

        // Browser cookies
        if let savedCookies = defaults.string(forKey: browserCookiesKey) ?? defaults.string(forKey: legacyBrowserCookiesKey), !savedCookies.isEmpty {
            self.browserCookies = savedCookies
        }
    }

    public var effectiveSaveDirectory: URL {
        let trimmed = saveDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return URL(fileURLWithPath: trimmed, isDirectory: true)
        }
        return StorageService.defaultBaseDirectory
    }

    public var parsedLanguages: [String] {
        return languagePreferences.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func findEnvFileKey() -> String? {
        let currentDir = FileManager.default.currentDirectoryPath
        let candidates = [
            URL(fileURLWithPath: currentDir).appendingPathComponent("cli/.env"),
            URL(fileURLWithPath: currentDir).appendingPathComponent(".env"),
            URL(fileURLWithPath: currentDir).deletingLastPathComponent().appendingPathComponent("cli/.env"),
            URL(fileURLWithPath: currentDir).deletingLastPathComponent().appendingPathComponent(".env"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".env")
        ]

        for candidate in candidates {
            if let content = try? String(contentsOf: candidate, encoding: .utf8) {
                for line in content.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.hasPrefix("GEMINI_API_KEY=") {
                        var val = String(trimmed.dropFirst("GEMINI_API_KEY=".count))
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if val.hasPrefix("\"") && val.hasSuffix("\"") && val.count >= 2 {
                            val = String(val.dropFirst().dropLast())
                        } else if val.hasPrefix("'") && val.hasSuffix("'") && val.count >= 2 {
                            val = String(val.dropFirst().dropLast())
                        }
                        if !val.isEmpty { return val }
                    }
                }
            }
        }
        return nil
    }
}
