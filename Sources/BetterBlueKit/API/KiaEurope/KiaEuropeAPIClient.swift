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

    var stamp = ""
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

    /// IDPConnect headless signin: authorize → certs → encrypted-signin → 302 with ?code=
    private func signin() async throws -> String {
        // Step 1: GET authorize — sets session cookies on idpconnect-eu.kia.com
        let encodedRedirect = oauthRedirectURI.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) ?? oauthRedirectURI
        let authorizeURL =
            "\(authBaseURL)/auth/api/v2/user/oauth2/authorize"
            + "?response_type=code&client_id=\(Self.clientId)"
            + "&redirect_uri=\(encodedRedirect)&lang=en&state=ccsp&country=de"
        var authorizeReq = URLRequest(url: URL(string: authorizeURL)!)
        authorizeReq.setValue(Self.mobileUserAgent, forHTTPHeaderField: "User-Agent")
        _ = try await urlSession.data(for: authorizeReq)

        // Step 2: GET certs — pull JWK (n, e, kid) for password encryption
        var certsReq = URLRequest(url: URL(string: "\(authBaseURL)/auth/api/v1/accounts/certs")!)
        certsReq.setValue(Self.mobileUserAgent, forHTTPHeaderField: "User-Agent")
        let (certsData, _) = try await urlSession.data(for: certsReq)
        guard let certsJson = try JSONSerialization.jsonObject(with: certsData) as? [String: Any],
              let retValue = certsJson["retValue"] as? [String: Any],
              let nStr = retValue["n"] as? String,
              let eStr = retValue["e"] as? String,
              let kid = retValue["kid"] as? String else {
            throw APIError(message: "Failed to parse JWK from /accounts/certs", apiName: apiName)
        }

        // Step 3: RSA-PKCS1v1.5-encrypt password, hex-encode
        let encryptedHex = try rsaEncryptPKCS1(password: password, jwkN: nStr, jwkE: eStr)

        // Step 4: POST signin (form-encoded). URLSession follows the 302 to
        // the redirect_uri — the final URL carries `?code=…` in its query.
        let signinFields: [(String, String)] = [
            ("client_id", Self.clientId),
            ("encryptedPassword", "true"),
            ("password", encryptedHex),
            ("redirect_uri", oauthRedirectURI),
            ("scope", ""),
            ("nonce", ""),
            ("state", "ccsp"),
            ("username", username),
            ("connector_session_key", ""),
            ("kid", kid),
            ("_csrf", "")
        ]
        var signinReq = URLRequest(url: URL(string: "\(authBaseURL)/auth/account/signin")!)
        signinReq.httpMethod = "POST"
        signinReq.setValue(Self.mobileUserAgent, forHTTPHeaderField: "User-Agent")
        signinReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        signinReq.httpBody = Self.formEncode(signinFields).data(using: .utf8)

        let (_, signinResp) = try await urlSession.data(for: signinReq)
        guard let http = signinResp as? HTTPURLResponse,
              let finalURL = http.url,
              let comps = URLComponents(url: finalURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidCredentials("Signin returned no redirect", apiName: apiName)
        }

        if let code = comps.queryItems?.first(where: { $0.name == "code" })?.value,
           !code.isEmpty {
            return code
        }

        // Translate IDPConnect error redirects into BetterBlueKit errors
        if let errorDesc = comps.queryItems?.first(where: { $0.name == "error_description" })?.value {
            throw APIError.invalidCredentials(
                "Authentication rejected: \(errorDesc)", apiName: apiName
            )
        }
        if comps.path.contains("/web/v1/user/authorization") {
            throw APIError(
                message: "Kia account consent required — log in via a browser once to accept the terms",
                apiName: apiName
            )
        }
        if comps.path.contains("authorize") {
            throw APIError.invalidCredentials(
                "Authentication failed — returned to login page. Check username and password.",
                apiName: apiName
            )
        }
        throw APIError(message: "Unexpected redirect after signin: \(finalURL.absoluteString)", apiName: apiName)
    }

    /// Exchange `?code=…` from the signin redirect for access + refresh tokens
    private func exchangeForToken(code: String) async throws -> AuthToken {
        let fields: [(String, String)] = [
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", oauthRedirectURI),
            ("client_id", Self.clientId),
            ("client_secret", Self.clientSecret)
        ]
        var request = URLRequest(url: URL(string: "\(authBaseURL)/auth/api/v2/user/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue(Self.mobileUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(fields).data(using: .utf8)

        let (data, _) = try await urlSession.data(for: request)
        return try parseAuthToken(from: data, isRefresh: true)
    }

    /// Refresh-grant: trade stored refresh_token for a fresh access_token
    private func getAccessTokenFromRefreshToken() async throws -> AuthToken {
        let fields: [(String, String)] = [
            ("grant_type", "refresh_token"),
            ("refresh_token", configuration.refreshToken ?? ""),
            ("redirect_uri", oauthRedirectURI),
            ("client_id", Self.clientId),
            ("client_secret", Self.clientSecret)
        ]
        var request = URLRequest(url: URL(string: "\(authBaseURL)/auth/api/v2/user/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue(Self.mobileUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(fields).data(using: .utf8)

        let (data, _) = try await urlSession.data(for: request)
        return try parseAuthToken(from: data, isRefresh: false)
    }

    // MARK: - Device registration

    public override func registerDevice() async throws -> String? {
        stamp = generateStamp()
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

    // MARK: - Commands (stub — implemented in Fase 4)

    public func sendCommand(for vehicle: Vehicle, command: VehicleCommand, authToken: AuthToken) async throws {
        throw APIError.regionNotSupported("Kia Europe commands not yet implemented.", apiName: apiName)
    }

    public func fetchEVTripDetails(for vehicle: Vehicle, authToken: AuthToken) async throws -> [EVTripDetail]? {
        nil
    }
}
