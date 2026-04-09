import Foundation

struct Region: Identifiable, Codable, Hashable {
    let id: String
    let provider: Provider
    let city: String
    let country: String
    let continent: String

    var displayName: String {
        "\(city), \(country)"
    }
}
