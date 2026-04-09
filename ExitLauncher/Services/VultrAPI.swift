import Foundation

enum VultrError: LocalizedError {
    case noAPIKey
    case requestFailed(Int, String)
    case decodingFailed(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "Vultr API key not configured"
        case .requestFailed(let code, let msg): return "Vultr API error (\(code)): \(msg)"
        case .decodingFailed(let err): return "Failed to decode Vultr response: \(err.localizedDescription)"
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        }
    }
}

actor VultrAPI {
    private let baseURL = URL(string: "https://api.vultr.com/v2/")!
    private let session = URLSession.shared
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private var apiKey: String {
        get throws {
            guard let key = KeychainService.read(key: .vultrAPIKey), !key.isEmpty else {
                throw VultrError.noAPIKey
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
            throw VultrError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw VultrError.networkError(URLError(.badServerResponse))
        }

        if httpResponse.statusCode >= 400 {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw VultrError.requestFailed(httpResponse.statusCode, message)
        }

        return (data, httpResponse)
    }

    // MARK: - Regions

    func listRegions() async throws -> [Region] {
        let (data, _) = try await request("GET", path: "regions")
        let response = try decoder.decode(RegionsResponse.self, from: data)
        return response.regions.map { r in
            Region(slug: r.id, provider: .vultr, city: r.city, country: r.country, continent: r.continent)
        }
    }

    // MARK: - Plans

    func listPlans() async throws -> [Plan] {
        let (data, _) = try await request("GET", path: "plans")
        let response = try decoder.decode(PlansResponse.self, from: data)
        return response.plans.map { p in
            Plan(id: p.id, vcpus: p.vcpuCount, ram: p.ram, disk: p.disk, monthlyCost: p.monthlyCost, locations: p.locations)
        }
    }

    // MARK: - Instances

    func createInstance(region: String, plan: String, userData: String, label: String) async throws -> VPSInstance {
        let body: [String: Any] = [
            "region": region,
            "plan": plan,
            "os_id": 2284, // Ubuntu 24.04 LTS
            "label": label,
            "hostname": label,
            "user_data": userData,
            "backups": "disabled",
            "enable_ipv6": true
        ]

        let (data, _) = try await request("POST", path: "instances", body: body)
        let response = try decoder.decode(InstanceResponse.self, from: data)
        let inst = response.instance

        return VPSInstance(
            id: inst.id,
            provider: .vultr,
            region: region,
            regionName: label,
            tailscaleHostname: label,
            ipAddress: inst.mainIp,
            createdAt: Date(),
            destroyAt: nil,
            status: .provisioning
        )
    }

    func getInstance(id: String) async throws -> VultrInstanceDetail {
        let (data, _) = try await request("GET", path: "instances/\(id)")
        let response = try decoder.decode(InstanceResponse.self, from: data)
        return response.instance
    }

    func deleteInstance(id: String) async throws {
        let _ = try await request("DELETE", path: "instances/\(id)")
    }
}

// MARK: - Vultr API Response Models

struct RegionsResponse: Codable {
    let regions: [VultrRegion]
}

struct VultrRegion: Codable {
    let id: String
    let city: String
    let country: String
    let continent: String
}

struct PlansResponse: Codable {
    let plans: [VultrPlan]
}

struct VultrPlan: Codable {
    let id: String
    let vcpuCount: Int
    let ram: Int
    let disk: Int
    let monthlyCost: Double
    let locations: [String]
}

struct InstanceResponse: Codable {
    let instance: VultrInstanceDetail
}

struct VultrInstanceDetail: Codable {
    let id: String
    let mainIp: String
    let status: String
    let powerStatus: String
    let serverStatus: String
}
