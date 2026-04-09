import Foundation
import CommonCrypto

/// Lightweight AWS Signature V4 signer using CommonCrypto. No external dependencies.
struct AWSSigner {
    let accessKeyId: String
    let secretAccessKey: String
    let region: String
    let service: String

    func sign(request: inout URLRequest, body: Data = Data()) {
        let date = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amzDate = dateFormatter.string(from: date)

        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStamp = dateFormatter.string(from: date)

        let host = request.url!.host!

        request.setValue(amzDate, forHTTPHeaderField: "X-Amz-Date")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(host, forHTTPHeaderField: "Host")

        let method = request.httpMethod ?? "POST"
        let bodyHash = sha256Hex(body)

        // Sign only: content-type, host, x-amz-date (matching botocore's behavior)
        let signedHeaders = "content-type;host;x-amz-date"
        let canonicalHeaders =
            "content-type:application/x-www-form-urlencoded; charset=utf-8\n" +
            "host:\(host)\n" +
            "x-amz-date:\(amzDate)\n"

        let canonicalRequest =
            "\(method)\n" +
            "/\n" +
            "\n" +
            "\(canonicalHeaders)\n" +
            "\(signedHeaders)\n" +
            "\(bodyHash)"

        let scope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign =
            "AWS4-HMAC-SHA256\n" +
            "\(amzDate)\n" +
            "\(scope)\n" +
            "\(sha256Hex(Data(canonicalRequest.utf8)))"

        let kDate = hmacSHA256(key: Data("AWS4\(secretAccessKey)".utf8), data: Data(dateStamp.utf8))
        let kRegion = hmacSHA256(key: kDate, data: Data(region.utf8))
        let kService = hmacSHA256(key: kRegion, data: Data(service.utf8))
        let kSigning = hmacSHA256(key: kService, data: Data("aws4_request".utf8))

        let signature = hmacSHA256(key: kSigning, data: Data(stringToSign.utf8))
            .map { String(format: "%02x", $0) }.joined()

        let authorization = "AWS4-HMAC-SHA256 Credential=\(accessKeyId)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
    }

    private func sha256Hex(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash) }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func hmacSHA256(key: Data, data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        key.withUnsafeBytes { keyPtr in
            data.withUnsafeBytes { dataPtr in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), keyPtr.baseAddress, key.count, dataPtr.baseAddress, data.count, &hash)
            }
        }
        return Data(hash)
    }
}
