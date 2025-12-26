//
//  HyundaiAPIEndpointProvider.swift
//  BetterBlueKit
//
//  Hyundai API Client Implementation
//

import Foundation

// MARK: - Hyundai API Endpoint Provider

@MainActor
public final class HyundaiAPIEndpointProvider {
    let region: Region
    let username: String
    let password: String
    let pin: String
    let accountId: UUID

    public init(configuration: APIClientConfiguration) {
        region = configuration.region
        username = configuration.username
        password = configuration.password
        pin = configuration.pin
        accountId = configuration.accountId
    }

    var clientId: String {
        switch region {
        case .usa:
            "m66129Bb-em93-SPAHYN-bZ91-am4540zp19920"
        default:
            "m0na2res08hlm125puuhqzpv"
        }
    }

    var clientSecret: String {
        switch region {
        case .usa:
            "v558o935-6nne-423i-baa8"
        default:
            "PPaX5NpW4Dqono3oNoz9K5mZbK9RG5u2"
        }
    }

    func getHeaders() -> [String: String] {
        [
            "client_id": clientId,
            "clientSecret": clientSecret,
            "Host": "api.telematics.hyundaiusa.com",
            "User-Agent": "okhttp/3.12.0",
            "Content-Type": "application/json",
            "Accept": "application/json, text/plain, */*",
            "Accept-Encoding": "gzip, deflate, br",
            "Accept-Language": "en-US,en;q=0.9",
            "Connection": "Keep-Alive"
        ]
    }

    func getAuthorizedHeaders(authToken: AuthToken, vehicle: Vehicle? = nil) -> [String: String] {
        var headers = getHeaders()
        headers["accessToken"] = authToken.accessToken
        headers["language"] = "0"
        headers["to"] = "ISS"
        headers["encryptFlag"] = "false"
        headers["from"] = "SPA"
        headers["offset"] = "-5"
        if let vehicle {
            headers["gen"] = String(vehicle.generation)
            headers["registrationId"] = vehicle.regId
            headers["vin"] = vehicle.vin
            headers["APPCLOUD-VIN"] = vehicle.vin
        }
        headers["brandIndicator"] = "H"
        headers["origin"] = "https://api.telematics.hyundaiusa.com"
        headers["referer"] = "https://api.telematics.hyundaiusa.com/login"
        headers["sec-fetch-dest"] = "empty"
        headers["sec-fetch-mode"] = "cors"
        headers["sec-fetch-site"] = "same-origin"
        headers["username"] = username
        headers["blueLinkServicePin"] = pin
        headers["refresh"] = "false"

        // Generate current timestamp in the required format
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMddHHmmss"
        let timestamp = dateFormatter.string(from: Date())
        headers["payloadGenerated"] = timestamp
        headers["includeNonConnectedVehicles"] = "Y"

        return headers
    }
}

// MARK: - Type Alias for Convenience

public typealias HyundaiAPIClient = APIClient<HyundaiAPIEndpointProvider>
