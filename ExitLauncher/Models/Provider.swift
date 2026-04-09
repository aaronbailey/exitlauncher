import Foundation

enum Provider: String, Codable, CaseIterable, Identifiable {
    case vultr
    case digitalOcean
    case flyio

    var id: Self { self }

    var displayName: String {
        switch self {
        case .vultr: return "Vultr"
        case .digitalOcean: return "Digital Ocean"
        case .flyio: return "Fly.io"
        }
    }

    var keychainKey: KeychainKey {
        switch self {
        case .vultr: return .vultrAPIKey
        case .digitalOcean: return .digitalOceanAPIKey
        case .flyio: return .flyioAPIKey
        }
    }
}
