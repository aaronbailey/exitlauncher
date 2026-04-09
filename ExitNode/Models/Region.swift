import Foundation

struct Region: Identifiable, Codable, Hashable {
    let id: String
    let city: String
    let country: String
    let continent: String

    var displayName: String {
        "\(city), \(country)"
    }
}
