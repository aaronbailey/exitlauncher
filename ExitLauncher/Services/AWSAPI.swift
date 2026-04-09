import Foundation

enum AWSError: LocalizedError {
    case noCredentials
    case requestFailed(Int, String)
    case parseError(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .noCredentials: return "AWS credentials not configured"
        case .requestFailed(let code, let msg): return "AWS error (\(code)): \(msg)"
        case .parseError(let msg): return "AWS parse error: \(msg)"
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        }
    }
}

actor AWSAPI {
    private let session = URLSession.shared

    // Ubuntu 24.04 LTS AMIs per region (arm64 for Graviton, cheaper)
    // These are official Canonical AMIs — updated periodically
    private static let ubuntuAMIs: [String: String] = [
        "us-east-1": "ami-0a7a4e87939439934",
        "us-east-2": "ami-0d1f52ff90954b297",
        "us-west-1": "ami-014d544cfb2009aeb",
        "us-west-2": "ami-09040d770ffe2224f",
        "eu-west-1": "ami-0a89610b2f8f24e6d",
        "eu-west-2": "ami-0b2287cff5d6be10f",
        "eu-west-3": "ami-0dafa01a84941fb58",
        "eu-central-1": "ami-0084a47cc718c111a",
        "eu-north-1": "ami-0699841e73398bc4d",
        "ap-southeast-1": "ami-01938df366ac2d954",
        "ap-southeast-2": "ami-0e0a09e4e0a5fc266",
        "ap-northeast-1": "ami-0a0b7b240264a48d7",
        "ap-northeast-2": "ami-01ed8ade75d4eee2f",
        "ap-south-1": "ami-053b12d3152c0cc71",
        "sa-east-1": "ami-078e0c0dab95b0e2d",
        "ca-central-1": "ami-05f1e29dc87b0e84f",
    ]

    private func getCredentials() throws -> (accessKeyId: String, secretAccessKey: String) {
        guard let creds = KeychainService.read(key: .awsCredentials), !creds.isEmpty else {
            throw AWSError.noCredentials
        }
        // Stored as "ACCESS_KEY_ID:SECRET_ACCESS_KEY"
        let parts = creds.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else {
            throw AWSError.noCredentials
        }
        return (String(parts[0]), String(parts[1]))
    }

    private func ec2Request(region: String, params: [String: String]) async throws -> Data {
        let creds = try getCredentials()
        let url = URL(string: "https://ec2.\(region).amazonaws.com/")!

        var allParams = params
        allParams["Version"] = "2016-11-15"

        let body = allParams.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .sorted()
            .joined(separator: "&")
        let bodyData = Data(body.utf8)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData

        let signer = AWSSigner(accessKeyId: creds.accessKeyId, secretAccessKey: creds.secretAccessKey, region: region, service: "ec2")
        signer.sign(request: &request, body: bodyData)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AWSError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AWSError.networkError(URLError(.badServerResponse))
        }

        if http.statusCode >= 400 {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            // Extract AWS error message from XML
            if let errorMsg = extractXMLValue(from: msg, tag: "Message") {
                throw AWSError.requestFailed(http.statusCode, errorMsg)
            }
            throw AWSError.requestFailed(http.statusCode, msg)
        }

        return data
    }

    // MARK: - Regions

    func listRegions() -> [Region] {
        // Only default-enabled AWS regions (opt-in regions like af-south-1,
        // me-south-1, ap-east-1 etc. require manual activation in AWS console)
        let regions: [(String, String, String, String)] = [
            ("us-east-1", "N. Virginia", "US", "North America"),
            ("us-east-2", "Ohio", "US", "North America"),
            ("us-west-1", "N. California", "US", "North America"),
            ("us-west-2", "Oregon", "US", "North America"),
            ("ca-central-1", "Montreal", "CA", "North America"),
            ("eu-west-1", "Ireland", "IE", "Europe"),
            ("eu-west-2", "London", "GB", "Europe"),
            ("eu-west-3", "Paris", "FR", "Europe"),
            ("eu-central-1", "Frankfurt", "DE", "Europe"),
            ("eu-north-1", "Stockholm", "SE", "Europe"),
            ("ap-southeast-1", "Singapore", "SG", "Asia"),
            ("ap-southeast-2", "Sydney", "AU", "Oceania"),
            ("ap-northeast-1", "Tokyo", "JP", "Asia"),
            ("ap-northeast-2", "Seoul", "KR", "Asia"),
            ("ap-south-1", "Mumbai", "IN", "Asia"),
            ("sa-east-1", "Sao Paulo", "BR", "South America"),
        ]
        return regions.map { Region(slug: $0.0, provider: .aws, city: $0.1, country: $0.2, continent: $0.3) }
    }

    // MARK: - Instances

    func createInstance(region: String, userData: String, label: String) async throws -> VPSInstance {
        guard let amiId = Self.ubuntuAMIs[region] else {
            throw AWSError.parseError("No AMI configured for region \(region)")
        }

        let params: [String: String] = [
            "Action": "RunInstances",
            "ImageId": amiId,
            "InstanceType": "t3.nano",
            "MinCount": "1",
            "MaxCount": "1",
            "UserData": userData, // already base64
            "TagSpecification.1.ResourceType": "instance",
            "TagSpecification.1.Tag.1.Key": "Name",
            "TagSpecification.1.Tag.1.Value": label,
            "TagSpecification.1.Tag.2.Key": "exitlauncher",
            "TagSpecification.1.Tag.2.Value": "true",
        ]

        let data = try await ec2Request(region: region, params: params)
        let xml = String(data: data, encoding: .utf8) ?? ""

        guard let instanceId = extractXMLValue(from: xml, tag: "instanceId") else {
            throw AWSError.parseError("No instanceId in response")
        }

        return VPSInstance(
            id: instanceId,
            provider: .aws,
            region: region,
            regionName: label,
            tailscaleHostname: label,
            ipAddress: "",
            createdAt: Date(),
            destroyAt: nil,
            status: .provisioning
        )
    }

    func getInstance(region: String, id: String) async throws -> (status: String, ip: String) {
        let params: [String: String] = [
            "Action": "DescribeInstances",
            "InstanceId.1": id,
        ]

        let data = try await ec2Request(region: region, params: params)
        let xml = String(data: data, encoding: .utf8) ?? ""

        let status = extractXMLValue(from: xml, tag: "name", after: "<instanceState>") ?? "unknown"
        let ip = extractXMLValue(from: xml, tag: "publicIpAddress") ?? ""
        return (status, ip)
    }

    func deleteInstance(region: String, id: String) async throws {
        let params: [String: String] = [
            "Action": "TerminateInstances",
            "InstanceId.1": id,
        ]
        _ = try await ec2Request(region: region, params: params)
    }

    // MARK: - XML Helpers

    private func extractXMLValue(from xml: String, tag: String, after: String? = nil) -> String? {
        var searchIn = xml
        if let after, let range = xml.range(of: after) {
            searchIn = String(xml[range.upperBound...])
        }
        guard let startRange = searchIn.range(of: "<\(tag)>"),
              let endRange = searchIn.range(of: "</\(tag)>") else {
            return nil
        }
        return String(searchIn[startRange.upperBound..<endRange.lowerBound])
    }
}
