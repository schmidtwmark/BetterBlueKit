//
//  KiaEuropeAPIClient.swift
//  BetterBlueKit
//
//  Kia Europe API Client
//  Based on KiaUvoApiEU from hyundai_kia_connect_api (PR #1123, v4.12.0)
//  which integrates a headless IDPConnect login flow and drops curl_cffi
//  by appending `_CCS_APP_AOS` to the User-Agent.
//

import CryptoKit
import Foundation

// MARK: - Kia Europe API Client

@MainActor
public final class KiaEuropeAPIClient: APIClientBase, APIClientProtocol {

    // MARK: - Constants

    static let clientId = "fdc85c00-0a2f-4c64-bcb4-2cfb1500730a"
    static let clientSecret = "secret"
    static let appId = "a2b8469b-30a3-4361-8e13-6fceea8fbe74"
    static let basicAuthorization = "Basic ZmRjODVjMDAtMGEyZi00YzY0LWJjYjQtMmNmYjE1MDA3MzBhOnNlY3JldA=="
    static let authCfb = "wLTVxwidmH8CfJYBWSnHD6E0huk0ozdiuygB4hLkM5XCgzAL1Dk5sE36d/bx5PFMbZs="
    static let pushType = "APNS"

    /// The `_CCS_APP_AOS` suffix is what gets past Cloudflare on
    /// `idpconnect-eu.kia.com` — without it, the authorize endpoint
    /// returns 400. Discovered in hyundai_kia_connect_api PR #1123.
    static let mobileUserAgent =
        "Mozilla/5.0 (Linux; Android 4.1.1; Galaxy Nexus Build/JRO03C) " +
        "AppleWebKit/535.19 (KHTML, like Gecko) " +
        "Chrome/18.0.1025.166 Mobile Safari/535.19_CCS_APP_AOS"

    var commandToken: String = ""
    var commandTokenExpiration: Date = Date()

    var baseURL: String {
        region.apiBaseURL(for: .kia)
    }
    var authBaseURL: String { "https://idpconnect-eu.kia.com" }
    var apiHost = Brand.kiaBaseUrl(region: Region.europe).replacing(/https:\/\//, with: "")

    var oauthRedirectURI: String { "\(baseURL)/api/v1/user/oauth2/redirect" }

    public override var apiName: String { "KiaEurope" }

    // MARK: - Login

    public func login() async throws -> AuthToken {
        var token: AuthToken!

        if let refreshToken = configuration.refreshToken, !refreshToken.isEmpty {
            BBLogger.info(.auth, "KiaEurope: Starting login flow (refresh token)")
            do {
                token = try await getAccessTokenFromRefreshToken()
            } catch {
                if let apiError = error as? APIError,
                    apiError.errorType == .invalidCredentials,
                    !password.isEmpty {
                    configuration = configuration.with(refreshToken: "")
                    return try await self.login()
                } else {
                    throw error
                }
            }
        } else {
            BBLogger.info(.auth, "KiaEurope: refresh token is nil or empty, using username/password login")
            let code = try await signin()
            token = try await exchangeForToken(code: code)
            configuration = configuration.with(refreshToken: token.refreshToken)
        }

        BBLogger.info(.auth, "KiaEurope: Login completed successfully")
        return token
    }

    // Auth flow (signin / token exchange / refresh) lives in
    // KiaEuropeAPIClient+Auth.swift to keep this class file under
    // the type-body-length threshold and so the multi-step signin
    // can be split into focused helpers.

    // MARK: - Device registration

    public override func registerDevice() async throws -> String? {
        let stamp = generateStamp()
        let body = [
            "pushRegId": stamp,
            "pushType": Self.pushType,
            "uuid": UUID().uuidString
        ]

        let headers = [
            "ccsp-service-id": Self.clientId,
            "ccsp-application-id": Self.appId,
            "Stamp": stamp,
            "Content-Type": "application/json;charset=UTF-8",
            "Host": apiHost,
            "Connection": "Keep-Alive",
            "Accept-Encoding": "gzip",
            "User-Agent": "okhttp/3.14.9"
        ]

        let bodyData = try? JSONSerialization.data(withJSONObject: body, options: [])

        var request = URLRequest(url: URL(string: "\(baseURL)/api/v1/spa/notifications/register")!)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, _) = try await urlSession.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resMsg = json["resMsg"] as? [String: Any],
              let devId = resMsg["deviceId"] as? String else {
            throw APIError(message: "Failed to get device id", apiName: apiName)
        }
        configuration = configuration.with(deviceId: devId)
        return devId
    }

    // MARK: - Vehicles

    public func fetchVehicles(authToken: AuthToken) async throws -> [Vehicle] {
        let (data, _, _) = try await performJSONRequest(
            url: "\(baseURL)/api/v1/spa/vehicles",
            method: .GET,
            headers: authorizedHeaders(authToken: authToken),
            requestType: .fetchVehicles
        )
        return try parseVehiclesResponse(data)
    }

    public func fetchVehicleStatus(
        for vehicle: Vehicle,
        authToken: AuthToken,
        cached _: Bool
    ) async throws -> VehicleStatus {
        let ccs2 = vehicle.marketOptions?.ccs2Supported ?? false
        let endpoint: String = ccs2 ? "/ccs2/carstatus/latest" : "/status/latest"

        let (statusData, _, _) = try await performJSONRequest(
            url: "\(baseURL)/api/v1/spa/vehicles/\(vehicle.regId)\(endpoint)",
            method: .GET,
            headers: authorizedHeaders(authToken: authToken, ccs2: ccs2),
            requestType: .fetchVehicleStatus,
            vin: vehicle.vin
        )

        let (parkData, _, _) = try await performJSONRequest(
            url: "\(baseURL)/api/v1/spa/vehicles/\(vehicle.regId)/location/park",
            method: .GET,
            headers: authorizedHeaders(authToken: authToken, ccs2: ccs2),
            requestType: .fetchVehicleStatus,
            vin: vehicle.vin
        )

        return try parseVehicleStatusResponse(statusData, parkData, for: vehicle)
    }

    // MARK: - Command token (PIN exchange)

    private func setCommandToken(authToken: AuthToken) async throws {
        // controlTokens expire after `expiresTime` seconds; refresh ~5 min early.
        if Date() < commandTokenExpiration.addingTimeInterval(-300) && !commandToken.isEmpty {
            return
        }

        let body = ["deviceId": configuration.deviceId ?? "", "pin": pin]
        let headers = authorizedHeaders(authToken: authToken)
        let bodyData = try? JSONSerialization.data(withJSONObject: body, options: [])

        var request = URLRequest(url: URL(string: "\(baseURL)/api/v1/user/pin?token=")!)
        request.httpMethod = "PUT"
        request.httpBody = bodyData
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, _) = try await urlSession.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["controlToken"] as? String,
              let expires = json["expiresTime"] as? Int else {
            throw APIError(message: "Failed to get command token (check PIN)", apiName: apiName)
        }

        commandToken = token
        commandTokenExpiration = Date().addingTimeInterval(TimeInterval(expires))
    }

    // MARK: - Commands

    public func sendCommand(for vehicle: Vehicle, command: VehicleCommand, authToken: AuthToken) async throws {
        let (path, body) = commandPathAndBody(for: command)
        let ccs2 = vehicle.marketOptions?.ccs2Supported ?? false
        let url = "\(baseURL)/api/\(ccs2 ? "v2" : "v1")"
            + "/spa/vehicles/\(vehicle.regId)/\(path)"
        try await setCommandToken(authToken: authToken)
        let headers = commandHeaders(authToken: authToken, ccs2: ccs2)

        _ = try await performJSONRequest(
            url: url,
            method: .POST,
            headers: headers,
            body: body,
            requestType: .sendCommand,
            vin: vehicle.vin
        )
    }

    public func fetchEVTripDetails(for vehicle: Vehicle, authToken: AuthToken) async throws -> [EVTripDetail]? {
        nil
    }
}
