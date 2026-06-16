//
//  HyundaiEuropeAPIClient.swift
//  BetterBlueKit
//
//  Hyundai Europe API Client
//  Based on: https://github.com/andyfase/egmp-bluelink-scriptable
//

import Foundation

// MARK: - Hyundai Europe API Client

@MainActor
public final class HyundaiEuropeAPIClient: APIClientBase, APIClientProtocol {

    // MARK: - Constants

    static let clientId = "6d477c38-3ca4-4cf3-9557-2a1929a94654"
    static let clientSecret = "KUy49XxPzLpLuoK0xhBC77W6VXhmtQR9iQhmIFjjoY4IpxsV"
    static let appId = "014d2225-8495-4735-812d-2616334fd15d"
    static let authCfb = "RFtoRq/vDXJmRndoZaZQyfOot7OrIqGVFj96iY2WL3yyH5Z/pUvlUhqmCxD2t+D65SQ="
    static let mobileUserAgent =
        "Mozilla/5.0 (Linux; Android 4.1.1; Galaxy Nexus Build/JRO03C) " +
        "AppleWebKit/535.19 (KHTML, like Gecko) " +
        "Chrome/18.0.1025.166 Mobile Safari/535.19_CCS_APP_AOS"

    var commandToken: String = ""
    var commandTokenExpiration: Date = Date()

    var baseURL: String {
        region.apiBaseURL(for: .hyundai)
    }
    var authBaseURL: String { "https://idpconnect-eu.hyundai.com" }
    var apiHost =  Brand.hyundaiBaseUrl(region: Region.europe).replacing(/https:\/\//, with: "")

    var oauthRedirectURI: String { "\(baseURL)/api/v1/user/oauth2/redirect" }

    public override var apiName: String { "HyundaiEurope" }

    // Header builders + `generateStamp()` are in
    // `HyundaiEuropeAPIClient+Headers.swift` so this file stays under
    // SwiftLint's 250-line type-body cap.

    // MARK: - Login (password or refresh token Flow)

    public func login() async throws -> AuthToken {

        var token: AuthToken!

        if let refreshToken = configuration.refreshToken, !refreshToken.isEmpty {
            BBLogger.info(.auth, "HyundaiEurope: Starting login flow (refresh token)")
            do {
                token = try await getAccessTokenFromRefreshToken()
            } catch {
                if let error = error as? APIError,
                    error.errorType == .invalidCredentials,
                    !password.isEmpty {
                    // remove refresh token and try login with credentials
                    configuration = configuration.with(refreshToken: "")
                    return try await self.login()
                } else {
                    throw error
                }
            }
        } else {
            BBLogger.info(.auth, "HyundaiEurope: refresh token is nil or empty, using username/password login")
            let code = try await signin()
            token = try await exchangeForToken(code: code)
            configuration = configuration.with(refreshToken: token.refreshToken)
        }

        BBLogger.info(.auth, "HyundaiEurope: Login completed successfully")
        return token
    }

    public override func registerDevice() async throws -> String? {
        let stamp = generateStamp()
        let pushRegId = try randomHexString(byteCount: 32)
        let body = [
            "pushRegId": pushRegId,
            "pushType": "GCM",
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

        let bodyData = try? JSONSerialization.data(
            withJSONObject: body, options: []
        )

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

    // MARK: - Get command token
    private func setCommandToken(authToken: AuthToken) async throws {
        // if token is valid return it
        if Date() < commandTokenExpiration.addingTimeInterval(-300) && !commandToken.isEmpty {
            return
        }

        let body = [
            "deviceId": configuration.deviceId,
            "pin": pin
        ]

        let headers = authorizedHeaders(authToken: authToken)

        let bodyData = try? JSONSerialization.data(
            withJSONObject: body, options: []
        )

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
            throw APIError(message: "Failed to get command token", apiName: apiName)
        }

        commandToken = token
        commandTokenExpiration = Date().addingTimeInterval(TimeInterval(expires))
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

    // MARK: - Vehicle Status

    public func fetchVehicleStatus(
        for vehicle: Vehicle,
        authToken: AuthToken,
        cached _: Bool
    ) async throws -> VehicleStatus {

        // CCS2 or Gen5W endpoint?
        let ccs2 = vehicle.marketOptions?.ccs2Supported ?? false
        let endpoint: String = ccs2 ? "/ccs2/carstatus/latest" : "/status/latest"
        // Europe uses a single "latest" endpoint; no force-refresh knob is
        // currently wired up here, so the cached flag is a no-op.
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

    // MARK: - Commands

    public func sendCommand(for vehicle: Vehicle, command: VehicleCommand, authToken: AuthToken) async throws {
        let ccs2 = vehicle.marketOptions?.ccs2Supported ?? false
        let usesControlToken = ccs2 && !command.isChargeLimitCommand
        let (rawPath, body) = commandPathAndBody(for: command, ccs2: ccs2)
        let path = String(rawPath.drop { $0 == "/" })
        let url =
            "\(baseURL)/api/\(usesControlToken ? "v2" : "v1")"
            + "/spa/vehicles/\(vehicle.regId)/\(path)"
        let header: [String: String]
        if usesControlToken {
            try await setCommandToken(authToken: authToken)
            header = commandHeaders(authToken: authToken, ccs2: ccs2)
        } else {
            header = authorizedHeaders(authToken: authToken, ccs2: ccs2)
        }

        _ = try await performJSONRequest(
            url: url,
            method: .POST,
            headers: header,
            body: body,
            requestType: .sendCommand,
            vin: vehicle.vin
        )
    }

    override func validateHTTPResponse(_ httpResponse: HTTPURLResponse, data: Data, responseBody: String?) throws {
        if let error = hyundaiEuropeAPIError(from: data) {
            throw error
        }
        try super.validateHTTPResponse(httpResponse, data: data, responseBody: responseBody)
    }
}
