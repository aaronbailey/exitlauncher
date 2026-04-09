import Foundation

enum DigitalOceanError: LocalizedError {
    case noAPIKey
    case requestFailed(Int, String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "Digital Ocean API key not configured"
        case .requestFailed(let code, let msg): return "DO API error (\(code)): \(msg)"
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        }
    }
}

actor DigitalOceanAPI {
    private let baseURL = URL(string: "https://api.digitalocean.com/v2/")!
    private let session = URLSession.shared
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private var apiKey: String {
        get throws {
            guard let key = KeychainService.read(key: .digitalOceanAPIKey), !key.isEmpty else {
                throw DigitalOceanError.noAPIKey
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
            throw DigitalOceanError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DigitalOceanError.networkError(URLError(.badServerResponse))
        }

        if httpResponse.statusCode >= 400 {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw DigitalOceanError.requestFailed(httpResponse.statusCode, message)
        }

        return (data, httpResponse)
    }

    // MARK: - Regions

    // DO's API only returns slug + name, no country/continent. Map them ourselves.
    // DO's API returns names like "New York 1" but no country/continent. Map by slug prefix.
    private static let regionMeta: [String: (country: String, continent: String)] = [
        "nyc": ("US", "North America"),
        "sfo": ("US", "North America"),
        "tor": ("CA", "North America"),
        "atl": ("US", "North America"),
        "ric": ("US", "North America"),
        "ams": ("NL", "Europe"),
        "lon": ("GB", "Europe"),
        "fra": ("DE", "Europe"),
        "blr": ("IN", "Asia"),
        "sgp": ("SG", "Asia"),
        "syd": ("AU", "Oceania"),
    ]

    func listRegions() async throws -> [Region] {
        let (data, _) = try await request("GET", path: "regions")
        let response = try decoder.decode(DORegionsResponse.self, from: data)
        return response.regions.filter { $0.available }.map { r in
            // Match prefix (e.g. "nyc1" -> "nyc")
            let prefix = String(r.slug.prefix(while: { $0.isLetter }))
            let meta = Self.regionMeta[prefix]
            return Region(
                slug: r.slug,
                provider: .digitalOcean,
                city: r.name, // Use API name directly: "New York 1", "Atlanta 1", etc.
                country: meta?.country ?? "",
                continent: meta?.continent ?? "North America"
            )
        }
    }

    // MARK: - Instances

    func createInstance(region: String, userData: String, label: String) async throws -> VPSInstance {
        let body: [String: Any] = [
            "name": label,
            "region": region,
            "size": "s-1vcpu-512mb-10gb",
            "image": "ubuntu-24-04-x64",
            "user_data": userData, // plain text, not base64
            "backups": false,
            "ipv6": true
        ]

        let (data, _) = try await request("POST", path: "droplets", body: body)
        let response = try decoder.decode(DODropletResponse.self, from: data)
        let droplet = response.droplet

        return VPSInstance(
            id: String(droplet.id),
            provider: .digitalOcean,
            region: region,
            regionName: label,
            tailscaleHostname: label,
            ipAddress: "",
            createdAt: Date(),
            destroyAt: nil,
            status: .provisioning
        )
    }

    func getInstance(id: String) async throws -> DODropletDetail {
        let (data, _) = try await request("GET", path: "droplets/\(id)")
        let response = try decoder.decode(DODropletResponse.self, from: data)
        return response.droplet
    }

    func deleteInstance(id: String) async throws {
        _ = try await request("DELETE", path: "droplets/\(id)")
    }
}

// MARK: - Response Models

struct DORegionsResponse: Codable {
    let regions: [DORegion]
}

struct DORegion: Codable {
    let slug: String
    let name: String
    let available: Bool
}

struct DODropletResponse: Codable {
    let droplet: DODropletDetail
}

struct DODropletDetail: Codable {
    let id: Int
    let status: String
    let networks: DONetworks?
}

struct DONetworks: Codable {
    let v4: [DONetwork]?
}

struct DONetwork: Codable {
    let ipAddress: String
    let type: String
}
