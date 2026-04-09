import Foundation

struct Region: Identifiable, Codable, Hashable {
    /// The provider's region slug (e.g. "syd", "nyc3")
    let slug: String
    let provider: Provider
    let city: String
    let country: String
    let continent: String

    /// Unique ID across providers — avoids SwiftUI list collisions
    var id: String { "\(provider.rawValue):\(slug)" }

    var displayName: String {
        "\(city), \(country)"
    }

    /// Normalize continent names across providers (Vultr uses "Australia", others use "Oceania")
    var normalizedContinent: String {
        switch continent {
        case "Australia": return "Oceania"
        default: return continent
        }
    }
}
