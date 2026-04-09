import Foundation

struct Plan: Identifiable, Codable {
    let id: String
    let vcpus: Int
    let ram: Int
    let disk: Int
    let monthlyCost: Double
    let locations: [String]

    var displayName: String {
        "\(vcpus) vCPU, \(ram)MB RAM, \(disk)GB SSD — $\(String(format: "%.0f", monthlyCost))/mo"
    }
}
