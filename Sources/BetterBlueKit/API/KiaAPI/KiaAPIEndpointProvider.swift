//
//  KiaAPIEndpointProvider.swift
//  BetterBlue
//
//  Created by Mark Schmidt on 7/23/25.
//

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

    let deviceId: String = {
        // Format: 22chars:9chars_10chars-5chars_22chars_8chars-18chars-_22chars_17chars
        func genRanHex(_ length: Int) -> String {
            let charset = "0123456789abcdef"
            return String((0 ..< length).map { _ in charset.randomElement()! })
        }
        return "\(genRanHex(22)):\(genRanHex(9))_\(genRanHex(10))" +
               "-\(genRanHex(5))_\(genRanHex(22))_\(genRanHex(8))" +
               "-\(genRanHex(18))-_\(genRanHex(22))_\(genRanHex(17))"
    }()

    let clientUUID: String = UUID().uuidString.lowercased()

    // MARK: - Helper Methods

    func apiHeaders() -> [String: String] {
        let offset = TimeZone.current.secondsFromGMT() / 3600
        let offsetString = offset >= 0 ? "+\(offset)" : "\(offset)"

        // Extract host from baseURL (remove https:// prefix)
        let hostName = baseURL.replacingOccurrences(of: "https://", with: "")

        // Format date like: "Fri, 23 Jan 2026 2:37:26 GMT"
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE, dd MMM yyyy H:mm:ss"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(identifier: "GMT")
        let dateString = dateFormatter.string(from: Date()) + " GMT"

        return [
            "content-type": "application/json;charset=UTF-8",
            "accept": "application/json, text/plain, */*",
            "accept-encoding": "gzip, deflate, br",
            "accept-language": "en-US,en;q=0.9",
            "from": "SPA",
            "language": "0",
            "offset": offsetString,
            "appType": "L",
            "appVersion": "7.22.0",
            "clientuuid": clientUUID,
            "clientId": "SPACL716-APL",
            "phonebrand": "iPhone",
            "osType": "iOS",
            "osVersion": "15.8.5",
            "secretKey": "sydnat-9kykci-Kuhtep-h5nK",
            "to": "APIGW",
            "tokentype": "A",
            "User-Agent": "KIAPrimo_iOS/37 CFNetwork/1335.0.3.4 Darwin/21.6.0",
            "deviceId": deviceId,
            "Host": hostName,
            "Date": dateString
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
