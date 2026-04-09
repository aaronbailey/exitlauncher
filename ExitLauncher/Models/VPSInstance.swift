import Foundation

enum InstanceStatus: String, Codable {
    case provisioning
    case ready
    case destroying
    case error
}

struct VPSInstance: Identifiable, Codable {
    let id: String
    let region: String
    let regionName: String
    let tailscaleHostname: String
    var ipAddress: String
    let createdAt: Date
    var destroyAt: Date?
    var status: InstanceStatus

    var timeRemaining: TimeInterval? {
        guard let destroyAt else { return nil }
        return max(0, destroyAt.timeIntervalSince(Date()))
    }

    var timeRemainingFormatted: String? {
        guard let remaining = timeRemaining else { return nil }
        if remaining <= 0 { return "Expiring..." }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m left"
        }
        return "\(minutes)m left"
    }
}
