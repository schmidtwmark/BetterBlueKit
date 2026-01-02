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
        let charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let randomPart = String((0 ..< 22).map { _ in charset.randomElement()! })
        return "\(randomPart):\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
    }()

    // MARK: - Helper Methods

    func apiHeaders() -> [String: String] {
        let offset = TimeZone.current.secondsFromGMT() / 3600
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(abbreviation: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"

        // Extract host from baseURL (remove https:// prefix)
        let hostName = baseURL.replacingOccurrences(of: "https://", with: "")

        return [
            "content-type": "application/json;charset=UTF-8", "accept": "application/json, text/plain, */*",
            "accept-encoding": "gzip, deflate, br", "accept-language": "en-US,en;q=0.9",
            "apptype": "L", "appversion": "7.15.2", "clientid": "MWAMOBILE", "from": "SPA",
            "host": hostName, "language": "0", "offset": "\(offset)", "ostype": "Android",
            "osversion": "11", "secretkey": "98er-w34rf-ibf3-3f6h", "to": "APIGW",
            "tokentype": "G", "user-agent": "okhttp/4.10.0", "deviceid": deviceId,
            "date": formatter.string(from: Date())
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
    }
}

// MARK: - Type Alias for Convenience

public typealias KiaAPIClient = APIClient<KiaAPIEndpointProvider>
