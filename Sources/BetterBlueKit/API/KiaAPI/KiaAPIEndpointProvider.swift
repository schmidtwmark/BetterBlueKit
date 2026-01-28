//
//  KiaAPIEndpointProvider.swift
//  BetterBlue
//
//  Created by Mark Schmidt on 7/23/25.
//

import CryptoKit
import Foundation

@MainActor
public final class KiaAPIEndpointProvider {
    let region: Region
    let username: String
    let password: String
    let pin: String
    let accountId: UUID
    let rememberMeToken: String?

    public init(configuration: APIClientConfiguration) {
        region = configuration.region
        username = configuration.username
        password = configuration.password
        pin = configuration.pin
        accountId = configuration.accountId
        rememberMeToken = configuration.rememberMeToken
    }

    // Use region-specific base URL
    var baseURL: String {
        region.apiBaseURL(for: .kia)
    }

    var apiURL: String {
        "\(baseURL)/apigw/v1/"
    }

    // Device ID is a simple uppercase UUID (matches Python: str(uuid.uuid4()).upper())
    let deviceId: String = UUID().uuidString.uppercased()

    // Client UUID is a UUID5 hash of device_id using DNS namespace
    // (matches Python: str(uuid.uuid5(uuid.NAMESPACE_DNS, self.device_id)))
    var clientUUID: String {
        // UUID5 uses SHA-1 hash of namespace + name
        // DNS namespace UUID is 6ba7b810-9dad-11d1-80b4-00c04fd430c8
        let namespaceUUID = UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8")!
        return generateUUID5(namespace: namespaceUUID, name: deviceId).uuidString.lowercased()
    }

    /// Generate UUID5 (SHA-1 based) from namespace and name
    private func generateUUID5(namespace: UUID, name: String) -> UUID {
        // Get namespace bytes in big-endian order
        let nsUUID = namespace.uuid
        var data = Data([
            nsUUID.0, nsUUID.1, nsUUID.2, nsUUID.3,
            nsUUID.4, nsUUID.5, nsUUID.6, nsUUID.7,
            nsUUID.8, nsUUID.9, nsUUID.10, nsUUID.11,
            nsUUID.12, nsUUID.13, nsUUID.14, nsUUID.15
        ])

        // Append name bytes
        data.append(contentsOf: name.utf8)

        // Compute SHA-1 hash using CryptoKit
        let digest = Insecure.SHA1.hash(data: data)
        var hash = Array(digest)

        // Set version (5) and variant bits
        hash[6] = (hash[6] & 0x0F) | 0x50  // Version 5
        hash[8] = (hash[8] & 0x3F) | 0x80  // Variant

        // Create UUID from first 16 bytes
        return UUID(uuid: (
            hash[0], hash[1], hash[2], hash[3],
            hash[4], hash[5], hash[6], hash[7],
            hash[8], hash[9], hash[10], hash[11],
            hash[12], hash[13], hash[14], hash[15]
        ))
    }

    // MARK: - Helper Methods

    func apiHeaders() -> [String: String] {
        // Offset as integer (no + sign for positive), matches Python: str(int(offset))
        let offset = TimeZone.current.secondsFromGMT() / 3600

        // Extract host from baseURL (remove https:// prefix)
        let hostName = baseURL.replacingOccurrences(of: "https://", with: "")

        // Format date like: "Fri, 23 Jan 2026 2:37:26 GMT"
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(identifier: "GMT")
        let dateString = dateFormatter.string(from: Date())

        // Headers match Python implementation
        return [
            "content-type": "application/json;charset=utf-8",
            "accept": "application/json",
            "accept-encoding": "gzip, deflate, br",
            "accept-language": "en-US,en;q=0.9",
            "accept-charset": "utf-8",
            "apptype": "L",
            "appversion": "7.22.0",
            "clientid": "SPACL716-APL",
            "clientuuid": clientUUID,
            "from": "SPA",
            "host": hostName,
            "language": "0",
            "offset": String(offset),
            "ostype": "iOS",
            "osversion": "15.8.5",
            "phonebrand": "iPhone",
            "secretkey": "sydnat-9kykci-Kuhtep-h5nK",
            "to": "APIGW",
            "tokentype": "A",
            "user-agent": "KIAPrimo_iOS/37 CFNetwork/1335.0.3.4 Darwin/21.6.0",
            "date": dateString,
            "deviceid": deviceId
        ]
    }

    func authedApiHeaders(authToken: AuthToken, vehicleKey: String?) -> [String: String] {
        var headers = apiHeaders()
        headers["sid"] = authToken.accessToken
        if let key = vehicleKey {
            headers["vinkey"] = key
        }
        return headers
    }

    func checkForKiaSpecificErrors(data: Data) throws {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? [String: Any],
              let errorCode: Int = extractNumber(from: status["errorCode"]),
              errorCode != 0 else { return }

        let errorMessage = status["errorMessage"] as? String ?? "Unknown Kia API error"
        let statusCode: Int = extractNumber(from: status["statusCode"]) ?? -1
        let errorType: Int = extractNumber(from: status["errorType"]) ?? -1
        let messageLower = errorMessage.lowercased()

        // Check specific error patterns
        if statusCode == 1, errorType == 1, errorCode == 1,
           messageLower.contains("valid email") || messageLower.contains("invalid") ||
           messageLower.contains("credential") {
            throw APIError.invalidCredentials("Invalid username or password", apiName: "KiaAPI")
        }

        if errorCode == 1005 || errorCode == 1103 {
            throw APIError.invalidVehicleSession(errorMessage, apiName: "KiaAPI")
        }

        if errorCode == 1003,
           messageLower.contains("session key") || messageLower.contains("invalid") ||
           messageLower.contains("expired") {
            throw APIError.invalidCredentials("Session Key is either invalid or expired", apiName: "KiaAPI")
        }

        if errorCode == 9789 {
            throw APIError.kiaInvalidRequest(
                "Kia API is currently unsupported. " +
                "See https://github.com/schmidtwmark/BetterBlueKit/issues/7 for updates",
                apiName: "KiaAPI"
            )
        }

        if errorCode == 429 {
            throw APIError.serverError("Rate limited", apiName: "KiaAPI")
        }

        if errorCode == 503 {
            throw APIError.serverError("Service unavailable", apiName: "KiaAPI")
        }
    }
}

// MARK: - Type Alias for Convenience

public typealias KiaAPIClient = APIClient<KiaAPIEndpointProvider>
