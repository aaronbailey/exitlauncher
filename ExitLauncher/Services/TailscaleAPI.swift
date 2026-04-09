import Foundation

/// Tailscale management API (api.tailscale.com) for operations like approving exit node routes.
/// This is separate from the local API used for setting exit nodes on this device.
enum TailscaleAPIError: LocalizedError {
    case noAPIKey
    case requestFailed(Int, String)
    case deviceNotFound(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "Tailscale API key not configured. Add it in Settings."
        case .requestFailed(let code, let msg): return "Tailscale API error (\(code)): \(msg)"
        case .deviceNotFound(let name): return "Device '\(name)' not found in tailnet"
        }
    }
}

actor TailscaleAPI {
    private let baseURL = URL(string: "https://api.tailscale.com/api/v2/")!
    private let session = URLSession.shared

    private var apiKey: String {
        get throws {
            guard let key = KeychainService.read(key: .tailscaleAPIKey), !key.isEmpty else {
                throw TailscaleAPIError.noAPIKey
            }
            return key
        }
    }

    private func request(_ method: String, path: String, body: Data? = nil) async throws -> Data {
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = method

        let credentials = "\(try apiKey):"
        let encoded = Data(credentials.utf8).base64EncodedString()
        req.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body {
            req.httpBody = body
        }

        let (data, response) = try await session.data(for: req)

        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TailscaleAPIError.requestFailed(http.statusCode, msg)
        }

        return data
    }

    /// Find a device in the tailnet by hostname, wait for it to advertise exit node routes, then approve them.
    func approveExitNode(hostname: String) async throws {
        let data = try await request("GET", path: "tailnet/-/devices")
        let response = try JSONDecoder().decode(DevicesResponse.self, from: data)

        guard let device = response.devices.first(where: {
            $0.hostname.lowercased() == hostname.lowercased()
        }) else {
            throw TailscaleAPIError.deviceNotFound(hostname)
        }

        // Check if the device has advertised exit node routes yet
        let routeData = try await request("GET", path: "device/\(device.id)/routes")
        let routes = try JSONDecoder().decode(RoutesResponse.self, from: routeData)

        // If no routes advertised yet, throw deviceNotFound to trigger retry in polling loop
        guard routes.advertisedRoutes.contains("0.0.0.0/0") else {
            throw TailscaleAPIError.deviceNotFound(hostname)
        }

        // Approve exit node routes
        let routeBody = try JSONSerialization.data(withJSONObject: [
            "routes": ["0.0.0.0/0", "::/0"]
        ])
        _ = try await request("POST", path: "device/\(device.id)/routes", body: routeBody)
    }

    /// Remove a device from the tailnet by hostname.
    func removeDevice(hostname: String) async throws {
        let data = try await request("GET", path: "tailnet/-/devices")
        let response = try JSONDecoder().decode(DevicesResponse.self, from: data)

        guard let device = response.devices.first(where: {
            $0.hostname.lowercased() == hostname.lowercased()
        }) else {
            return // Already gone — nothing to do
        }

        _ = try await request("DELETE", path: "device/\(device.id)")
    }
}

// MARK: - Response models

struct DevicesResponse: Codable {
    let devices: [TailscaleDevice]
}

struct TailscaleDevice: Codable {
    let id: String
    let hostname: String
}

struct RoutesResponse: Codable {
    let advertisedRoutes: [String]
    let enabledRoutes: [String]
}
