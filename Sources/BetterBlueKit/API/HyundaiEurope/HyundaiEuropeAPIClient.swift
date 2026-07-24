//
//  HyundaiEuropeAPIClient.swift
//  BetterBlueKit
//
//  Hyundai Europe API Client
//  Based on: https://github.com/andyfase/egmp-bluelink-scriptable
//

import CryptoKit
import Foundation

// MARK: - Hyundai Europe API Client

@MainActor
public final class HyundaiEuropeAPIClient: APIClientBase, APIClientProtocol {

    // MARK: - Constants

    static let clientId = "6d477c38-3ca4-4cf3-9557-2a1929a94654"
    static let clientSecret = "KUy49XxPzLpLuoK0xhBC77W6VXhmtQR9iQhmIFjjoY4IpxsV"
    static let appId = "014d2225-8495-4735-812d-2616334fd15d"
    static let authCfb = "RFtoRq/vDXJmRndoZaZQyfOot7OrIqGVFj96iY2WL3yyH5Z/pUvlUhqmCxD2t+D65SQ="
    var commandToken: String = ""
    var commandTokenExpiration: Date = Date()

    var baseURL: String {
        region.apiBaseURL(for: .hyundai)
    }
    var authBaseURL: String { "https://idpconnect-eu.hyundai.com" }
    var apiHost =  Brand.hyundaiBaseUrl(region: Region.europe).replacing(/https:\/\//, with: "")

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

    /// use code to exchange it for access token
    private func exchangeForToken(code: String) async throws -> AuthToken {

        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": "\(baseURL)/api/v1/user/oauth2/token",
            "client_id": Self.clientId,
            "client_secret": Self.clientSecret
        ]

        let (data, _, _) = try await performJSONRequest(
            url: "\(authBaseURL)/auth/api/v2/user/oauth2/token",
            method: .POST,
            headers: loginHeaders(),
            body: body,
            requestType: .login
        )

        return try parseAuthToken(from: data, isRefresh: true)
    }

    /// use username and password to get code for token exchange
    private func signin() async throws -> String {
        let state = UUID().uuidString
        let body = ["client_id": Self.clientId,
                    "encryptedPassword": "false",
                    "username": username,
                    "password": password,
                    "redirect_uri": "\(baseURL)/api/v1/user/oauth2/token",
                    "state": state,
                    "remember_me": "false"
        ]

        let bodyData = try? JSONSerialization.data(
            withJSONObject: body, options: []
        )

        var request = URLRequest(url: URL(string: "\(authBaseURL)/auth/account/signin")!)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.allHTTPHeaderFields = loginHeaders()
        let (_, response) = try await urlSession.data(for: request)

        guard let http = response as? HTTPURLResponse,
              let finalURL = http.url,
              let comps = URLComponents(url: finalURL, resolvingAgainstBaseURL: false) else {
            return ""
        }
        // State validate ← no possible anymore CSRF
        guard comps.queryItems?.first(where: { $0.name == "state" })?.value == state else {
                return ""
        }
        guard let code = comps.queryItems?.first(where: { $0.name == "code" })?.value,
                  !code.isEmpty else {
                return ""
        }

        return code
    }

    /// use refresh token to get a fresh acces token
    private func getAccessTokenFromRefreshToken() async throws -> AuthToken {

        let body = [
            "grant_type": "refresh_token",
            "refresh_token": configuration.refreshToken,
            "client_id": Self.clientId,
            "client_secret": Self.clientSecret
        ]

        let bodyData = try? JSONSerialization.data(
            withJSONObject: body, options: []
        )

        var request = URLRequest(url: URL(string: "\(authBaseURL)/auth/api/v2/user/oauth2/token")!)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await urlSession.data(for: request)
        return try parseAuthToken(from: data, isRefresh: false)
    }

    public override func registerDevice() async throws -> String? {
        let stamp = generateStamp()
        let body = [
            "pushRegId": stamp,
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

        let body: [String: Any] = [
            "deviceId": configuration.deviceId ?? "",
            "pin": pin
        ]

        // Route through performJSONRequest so the PIN/control-token
        // request is captured in the HTTP logs and its status is
        // validated. Previously this used a raw URLSession call, so a
        // failure here was invisible to diagnostics and surfaced only
        // as a generic "Failed to get command token".
        let (_, json, _) = try await performJSONRequest(
            url: "\(baseURL)/api/v1/user/pin?token=",
            method: .PUT,
            headers: authorizedHeaders(authToken: authToken),
            body: body,
            requestType: .sendCommand
        )

        guard let token = json["controlToken"] as? String,
              let expires = json["expiresTime"] as? Int else {
            throw APIError(
                message: "PIN verification failed — check that the account PIN is correct.",
                apiName: apiName
            )
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
        // Pass the vehicle's actual protocol into the body builder.
        // Previously this used the default (ccs2: true), so a legacy
        // Hyundai EU vehicle got a v1 URL with CCS2-shaped bodies.
        let (path, body) = commandPathAndBody(for: command, ccs2: ccs2)
        let url =
            "\(baseURL)/api/\(ccs2 ? "v2" : "v1")"
            + "/spa/vehicles/\(vehicle.regId)/\(path)"

        // CCS2 (Gen5W) cars authenticate commands with a PIN-derived
        // control token; legacy cars use the normal access token and
        // have no PIN step at all. Fetching a control token for a
        // legacy car is what produced the "Failed to get command token"
        // error — the PIN endpoint isn't part of the legacy flow.
        let header: [String: String]
        if ccs2 {
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

    public func supportsEVTripDetails() -> Bool {
        true
    }

    public func fetchEVTripDetails(for vehicle: Vehicle, authToken: AuthToken) async throws -> [EVTripDetail]? {
        let ccs2 = vehicle.marketOptions?.ccs2Supported ?? false
        let url = "\(baseURL)/api/v1/spa/vehicles/\(vehicle.regId)/drvhistory"

        let (data, _, _) = try await performJSONRequest(
            url: url,
            method: .POST,
            headers: authorizedHeaders(authToken: authToken, ccs2: ccs2),
            body: ["periodTarget": 0],
            requestType: .fetchEVTripDetails,
            vin: vehicle.vin
        )

        return try parseEVTripDetailsResponse(data, vehicle: vehicle)
    }

    public func fetchEVTripInfo(for vehicle: Vehicle, authToken: AuthToken, dateString: String) async throws -> [EVTripInfo]? {
        let ccs2 = vehicle.marketOptions?.ccs2Supported ?? false
        let url = "\(baseURL)/api/v1/spa/vehicles/\(vehicle.regId)/tripinfo"

        let (data, _, _) = try await performJSONRequest(
            url: url,
            method: .POST,
            headers: authorizedHeaders(authToken: authToken, ccs2: ccs2),
            body: [
                "tripPeriodType": 1,
                "setTripDay": dateString
            ],
            requestType: .fetchEVTripDetails,
            vin: vehicle.vin
        )

        return try parseIndividualTripsResponse(data)
    }
}
