import Foundation

enum KeychainKey: String {
    case vultrAPIKey = "vultr-api-key"
    case tailscaleAuthKey = "tailscale-auth-key"
    case tailscaleAPIKey = "tailscale-api-key"
}

/// Simple file-based secret storage in Application Support.
/// Uses UserDefaults-style storage — not as secure as Keychain but avoids
/// repeated password prompts for unsigned/dev-signed apps.
struct KeychainService {
    private static let storageURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("ExitLauncher", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("secrets.json")
    }()

    private static func loadAll() -> [String: String] {
        guard let data = try? Data(contentsOf: storageURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    private static func saveAll(_ dict: [String: String]) {
        guard let data = try? JSONEncoder().encode(dict) else { return }
        try? data.write(to: storageURL, options: [.atomic, .completeFileProtection])
        // Restrict file permissions to owner only
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: storageURL.path
        )
    }

    static func save(key: KeychainKey, value: String) throws {
        var dict = loadAll()
        dict[key.rawValue] = value
        saveAll(dict)
    }

    static func read(key: KeychainKey) -> String? {
        let dict = loadAll()
        return dict[key.rawValue]
    }

    static func delete(key: KeychainKey) throws {
        var dict = loadAll()
        dict.removeValue(forKey: key.rawValue)
        saveAll(dict)
    }
}
