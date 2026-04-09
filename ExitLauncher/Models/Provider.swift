import Foundation
import SwiftUI

enum Provider: String, Codable, CaseIterable, Identifiable {
    case vultr
    case digitalOcean
    case flyio
    case aws

    var id: Self { self }

    var displayName: String {
        switch self {
        case .vultr: return "Vultr"
        case .digitalOcean: return "Digital Ocean"
        case .flyio: return "Fly.io"
        case .aws: return "AWS"
        }
    }

    var keychainKey: KeychainKey {
        switch self {
        case .vultr: return .vultrAPIKey
        case .digitalOcean: return .digitalOceanAPIKey
        case .flyio: return .flyioAPIKey
        case .aws: return .awsCredentials
        }
    }

    var shortName: String {
        switch self {
        case .vultr: return "VLT"
        case .digitalOcean: return "DO"
        case .flyio: return "FLY"
        case .aws: return "AWS"
        }
    }

    var badgeColor: Color {
        switch self {
        case .vultr: return .blue
        case .digitalOcean: return .cyan
        case .flyio: return .purple
        case .aws: return .orange
        }
    }
}
