import Foundation

enum FlyioError: LocalizedError {
    case noAPIKey
    case noApp
    case requestFailed(Int, String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "Fly.io API key not configured"
        case .noApp: return "Fly.io app 'exitlauncher' not found. Create it with: fly apps create exitlauncher"
        case .requestFailed(let code, let msg): return "Fly.io API error (\(code)): \(msg)"
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        }
    }
}

actor FlyioAPI {
    private let baseURL = URL(string: "https://api.machines.dev/v1/")!
    private let appName = "exitlauncher"
    private let session = URLSession.shared

    private var apiKey: String {
        get throws {
            guard let key = KeychainService.read(key: .flyioAPIKey), !key.isEmpty else {
                throw FlyioError.noAPIKey
            }
            return key
        }
    }

    private func request(_ method: String, path: String, body: [String: Any]? = nil) async throws -> (Data, HTTPURLResponse) {
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(try apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw FlyioError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FlyioError.networkError(URLError(.badServerResponse))
        }

        if httpResponse.statusCode >= 400 {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw FlyioError.requestFailed(httpResponse.statusCode, message)
        }

        return (data, httpResponse)
    }

    // MARK: - Regions

    /// Fly.io regions are static — no API endpoint needed for the common ones
    func listRegions() -> [Region] {
        let regions: [(String, String, String, String)] = [
            ("ams", "Amsterdam", "NL", "Europe"),
            ("cdg", "Paris", "FR", "Europe"),
            ("fra", "Frankfurt", "DE", "Europe"),
            ("lhr", "London", "GB", "Europe"),
            ("arn", "Stockholm", "SE", "Europe"),
            ("waw", "Warsaw", "PL", "Europe"),
            ("mad", "Madrid", "ES", "Europe"),
            ("iad", "Ashburn", "US", "North America"),
            ("ord", "Chicago", "US", "North America"),
            ("dfw", "Dallas", "US", "North America"),
            ("den", "Denver", "US", "North America"),
            ("lax", "Los Angeles", "US", "North America"),
            ("sjc", "San Jose", "US", "North America"),
            ("sea", "Seattle", "US", "North America"),
            ("ewr", "Secaucus", "US", "North America"),
            ("atl", "Atlanta", "US", "North America"),
            ("mia", "Miami", "US", "North America"),
            ("yul", "Montreal", "CA", "North America"),
            ("yyz", "Toronto", "CA", "North America"),
            ("gru", "Sao Paulo", "BR", "South America"),
            ("scl", "Santiago", "CL", "South America"),
            ("bog", "Bogota", "CO", "South America"),
            ("gig", "Rio de Janeiro", "BR", "South America"),
            ("nrt", "Tokyo", "JP", "Asia"),
            ("hkg", "Hong Kong", "HK", "Asia"),
            ("sin", "Singapore", "SG", "Asia"),
            ("bom", "Mumbai", "IN", "Asia"),
            ("bkk", "Bangkok", "TH", "Asia"),
            ("syd", "Sydney", "AU", "Oceania"),
            ("jnb", "Johannesburg", "ZA", "Africa"),
        ]
        return regions.map { Region(id: $0.0, provider: .flyio, city: $0.1, country: $0.2, continent: $0.3) }
    }

    // MARK: - App Management

    /// Ensures the Fly app exists, creating it if needed.
    private func ensureAppExists() async throws {
        // Check if app exists — use raw URLSession to handle 404 without throwing
        let url = baseURL.appendingPathComponent("apps/\(appName)")
        var req = URLRequest(url: url)
        req.setValue("Bearer \(try apiKey)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode == 200 { return }

        // App doesn't exist — create it
        let body: [String: Any] = [
            "app_name": appName,
            "org_slug": "personal"
        ]
        _ = try await request("POST", path: "apps", body: body)
    }

    // MARK: - Machines

    func createMachine(region: String, authKey: String, hostname: String) async throws -> VPSInstance {
        try await ensureAppExists()

        // Use the official Tailscale image with proper exit node config.
        // Fly.io VMs run privileged, so kernel-mode networking works.
        // We need init commands to enable IP forwarding and NAT masquerade
        // since the official image doesn't set these up for exit node use.
        let config: [String: Any] = [
            "image": "tailscale/tailscale:latest",
            "guest": [
                "cpu_kind": "shared",
                "cpus": 1,
                "memory_mb": 256
            ],
            "env": [
                "TS_AUTHKEY": authKey,
                "TS_EXTRA_ARGS": "--advertise-exit-node --hostname=\(hostname)",
                "TS_STATE_DIR": "/var/lib/tailscale",
                "TS_USERSPACE": "false"
            ],
            "processes": [
                [
                    "name": "app",
                    "entrypoint": ["/bin/sh"],
                    "cmd": ["-c", """
                        sysctl -w net.ipv4.ip_forward=1 && \
                        sysctl -w net.ipv6.conf.all.forwarding=1 && \
                        iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE && \
                        ip6tables -t nat -A POSTROUTING -o eth0 -j MASQUERADE && \
                        /usr/local/bin/containerboot
                        """]
                ]
            ],
            "auto_destroy": false
        ]

        let body: [String: Any] = [
            "name": hostname,
            "region": region,
            "config": config
        ]

        let (data, _) = try await request("POST", path: "apps/\(appName)/machines", body: body)

        let machine = try JSONDecoder().decode(FlyMachine.self, from: data)

        return VPSInstance(
            id: machine.id,
            provider: .flyio,
            region: region,
            regionName: hostname,
            tailscaleHostname: hostname,
            ipAddress: "",
            createdAt: Date(),
            destroyAt: nil,
            status: .provisioning
        )
    }

    func getMachine(id: String) async throws -> FlyMachine {
        let (data, _) = try await request("GET", path: "apps/\(appName)/machines/\(id)")
        return try JSONDecoder().decode(FlyMachine.self, from: data)
    }

    func deleteMachine(id: String) async throws {
        // Stop first, then destroy
        _ = try? await request("POST", path: "apps/\(appName)/machines/\(id)/stop")
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        _ = try await request("DELETE", path: "apps/\(appName)/machines/\(id)")
    }
}

// MARK: - Response Models

struct FlyMachine: Codable {
    let id: String
    let name: String?
    let state: String
    let region: String?
}
