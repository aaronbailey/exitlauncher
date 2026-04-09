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

    // Cache AMI lookups per region for the session
    private var amiCache: [String: String] = [:]

    /// Look up the latest Ubuntu 24.04 LTS AMI for a region using DescribeImages.
    /// Canonical's owner ID is 099720109477. Results are cached per session.
    private func lookupUbuntuAMI(region: String) async throws -> String {
        if let cached = amiCache[region] { return cached }

        let params: [String: String] = [
            "Action": "DescribeImages",
            "Owner.1": "099720109477",
            "Filter.1.Name": "name",
            "Filter.1.Value.1": "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*",
            "Filter.2.Name": "state",
            "Filter.2.Value.1": "available",
        ]

        let data = try await ec2Request(region: region, params: params)
        let xml = String(data: data, encoding: .utf8) ?? ""

        // Find the most recent AMI by picking the last imageId
        // (AWS returns them; we grab all and pick the newest by name sort)
        var amis: [(id: String, name: String)] = []
        var searchFrom = xml.startIndex
        while let idRange = xml.range(of: "<imageId>", range: searchFrom..<xml.endIndex),
              let idEnd = xml.range(of: "</imageId>", range: idRange.upperBound..<xml.endIndex) {
            let amiId = String(xml[idRange.upperBound..<idEnd.lowerBound])
            // Find the corresponding name
            var name = ""
            if let nameRange = xml.range(of: "<name>", range: idEnd.upperBound..<xml.endIndex),
               let nameEnd = xml.range(of: "</name>", range: nameRange.upperBound..<xml.endIndex) {
                name = String(xml[nameRange.upperBound..<nameEnd.lowerBound])
            }
            amis.append((amiId, name))
            searchFrom = idEnd.upperBound
        }

        // Sort by name descending (names contain dates like 20260321) to get newest
        guard let newest = amis.sorted(by: { $0.name > $1.name }).first else {
            throw AWSError.parseError("No Ubuntu 24.04 AMI found in \(region)")
        }

        amiCache[region] = newest.id
        return newest.id
    }

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

    // MARK: - VPC/Subnet helpers

    /// Find a usable subnet, or create a VPC + subnet + internet gateway if none exists.
    private func findOrCreateSubnet(region: String) async throws -> String {
        // Try existing subnets first
        let data = try await ec2Request(region: region, params: ["Action": "DescribeSubnets"])
        let xml = String(data: data, encoding: .utf8) ?? ""
        if let subnetId = extractXMLValue(from: xml, tag: "subnetId") {
            return subnetId
        }

        // No subnets — create a VPC, subnet, internet gateway, and route table
        // 1. Create VPC
        let vpcData = try await ec2Request(region: region, params: [
            "Action": "CreateVpc",
            "CidrBlock": "10.0.0.0/16",
            "TagSpecification.1.ResourceType": "vpc",
            "TagSpecification.1.Tag.1.Key": "Name",
            "TagSpecification.1.Tag.1.Value": "exitlauncher",
        ])
        let vpcXml = String(data: vpcData, encoding: .utf8) ?? ""
        guard let vpcId = extractXMLValue(from: vpcXml, tag: "vpcId") else {
            throw AWSError.parseError("Failed to create VPC")
        }

        // 2. Create subnet
        let subnetData = try await ec2Request(region: region, params: [
            "Action": "CreateSubnet",
            "VpcId": vpcId,
            "CidrBlock": "10.0.1.0/24",
            "TagSpecification.1.ResourceType": "subnet",
            "TagSpecification.1.Tag.1.Key": "Name",
            "TagSpecification.1.Tag.1.Value": "exitlauncher",
        ])
        let subnetXml = String(data: subnetData, encoding: .utf8) ?? ""
        guard let subnetId = extractXMLValue(from: subnetXml, tag: "subnetId") else {
            throw AWSError.parseError("Failed to create subnet")
        }

        // 3. Create internet gateway
        let igwData = try await ec2Request(region: region, params: [
            "Action": "CreateInternetGateway",
            "TagSpecification.1.ResourceType": "internet-gateway",
            "TagSpecification.1.Tag.1.Key": "Name",
            "TagSpecification.1.Tag.1.Value": "exitlauncher",
        ])
        let igwXml = String(data: igwData, encoding: .utf8) ?? ""
        guard let igwId = extractXMLValue(from: igwXml, tag: "internetGatewayId") else {
            throw AWSError.parseError("Failed to create internet gateway")
        }

        // 4. Attach internet gateway to VPC
        _ = try await ec2Request(region: region, params: [
            "Action": "AttachInternetGateway",
            "InternetGatewayId": igwId,
            "VpcId": vpcId,
        ])

        // 5. Find the route table for the VPC and add a default route
        let rtData = try await ec2Request(region: region, params: [
            "Action": "DescribeRouteTables",
            "Filter.1.Name": "vpc-id",
            "Filter.1.Value.1": vpcId,
        ])
        let rtXml = String(data: rtData, encoding: .utf8) ?? ""
        if let rtId = extractXMLValue(from: rtXml, tag: "routeTableId") {
            _ = try? await ec2Request(region: region, params: [
                "Action": "CreateRoute",
                "RouteTableId": rtId,
                "DestinationCidrBlock": "0.0.0.0/0",
                "GatewayId": igwId,
            ])
        }

        return subnetId
    }

    // MARK: - Instances

    func createInstance(region: String, userData: String, label: String) async throws -> VPSInstance {
        let amiId = try await lookupUbuntuAMI(region: region)
        let subnetId = try await findOrCreateSubnet(region: region)

        let params: [String: String] = [
            "Action": "RunInstances",
            "ImageId": amiId,
            "InstanceType": "t3.nano",
            "MinCount": "1",
            "MaxCount": "1",
            "UserData": userData,
            "NetworkInterface.1.DeviceIndex": "0",
            "NetworkInterface.1.SubnetId": subnetId,
            "NetworkInterface.1.AssociatePublicIpAddress": "true",
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
