import Foundation

enum TailscaleError: LocalizedError {
    case notRunning
    case apiError(String)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .notRunning: return "Tailscale doesn't appear to be running"
        case .apiError(let msg): return "Tailscale error: \(msg)"
        case .decodingFailed: return "Failed to parse Tailscale response"
        }
    }
}

// MARK: - Status models

struct TailscalePeer: Codable {
    let id: String
    let hostName: String
    let dnsName: String
    let tailscaleIPs: [String]
    let exitNode: Bool
    let exitNodeOption: Bool
    let online: Bool

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case hostName = "HostName"
        case dnsName = "DNSName"
        case tailscaleIPs = "TailscaleIPs"
        case exitNode = "ExitNode"
        case exitNodeOption = "ExitNodeOption"
        case online = "Online"
    }
}

struct TailscaleStatus: Codable {
    let peer: [String: TailscalePeer]?
    let selfNode: TailscalePeer?

    enum CodingKeys: String, CodingKey {
        case peer = "Peer"
        case selfNode = "Self"
    }

    var currentExitNode: TailscalePeer? {
        peer?.values.first(where: { $0.exitNode })
    }

    var availableExitNodes: [TailscalePeer] {
        (peer?.values.filter { $0.exitNodeOption && $0.online } ?? [])
            .sorted { $0.hostName < $1.hostName }
    }
}

// MARK: - Local API client

struct TailscaleService {
    /// The Mac App Store Tailscale uses a local HTTP API on 127.0.0.1.
    /// Port and password are discovered from the IPNExtension process's open files
    /// via lsof, avoiding direct access to the group container (which triggers
    /// a macOS privacy prompt).
    private static var cachedAPI: (port: Int, password: String)?

    private static func findLocalAPI() throws -> (port: Int, password: String) {
        if let cached = cachedAPI { return cached }

        // Use lsof to read the sameuserproof filename from IPNExtension's open files
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-c", "IPNExtension"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        // Parse: sameuserproof-PORT-PASSWORD
        for line in output.components(separatedBy: "\n") {
            guard let range = line.range(of: "sameuserproof-") else { continue }
            let tail = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            let parts = tail.split(separator: "-", maxSplits: 1)
            if parts.count == 2, let port = Int(parts[0]) {
                let result = (port, String(parts[1]))
                cachedAPI = result
                return result
            }
        }

        throw TailscaleError.notRunning
    }

    private static func apiRequest(_ method: String, path: String, body: Data? = nil) async throws -> Data {
        let (port, password) = try findLocalAPI()
        let url = URL(string: "http://127.0.0.1:\(port)/localapi/v0/\(path)")!

        var request = URLRequest(url: url)
        request.httpMethod = method

        // Basic auth with empty username and password from sameuserproof
        let credentials = ":\(password)"
        let encoded = Data(credentials.utf8).base64EncodedString()
        request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")

        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TailscaleError.apiError(msg)
        }

        return data
    }

    // MARK: - Public API

    static func status() async throws -> TailscaleStatus {
        let data = try await apiRequest("GET", path: "status")
        return try JSONDecoder().decode(TailscaleStatus.self, from: data)
    }

    static func setExitNode(hostname: String) async throws {
        // Find the peer's stable ID by hostname
        let status = try await status()
        guard let peer = status.peer?.values.first(where: {
            $0.hostName.lowercased() == hostname.lowercased()
        }) else {
            throw TailscaleError.apiError("Exit node '\(hostname)' not found in tailnet")
        }

        // Use masked prefs — must include the "Set" flag for the field to take effect
        let prefs: [String: Any] = [
            "ExitNodeIDSet": true,
            "ExitNodeID": peer.id
        ]
        let body = try JSONSerialization.data(withJSONObject: prefs)
        _ = try await apiRequest("PATCH", path: "prefs", body: body)
    }

    static func clearExitNode() async throws {
        let prefs: [String: Any] = [
            "ExitNodeIDSet": true,
            "ExitNodeID": ""
        ]
        let body = try JSONSerialization.data(withJSONObject: prefs)
        _ = try await apiRequest("PATCH", path: "prefs", body: body)
    }
}
