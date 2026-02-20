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

    static let apiDomain = "prd.eu-ccapi.hyundai.com"
    static let apiPort = 8080
    private static let authHost = "eu-account.hyundai.com"
    static let clientId = "6d477c38-3ca4-4cf3-9557-2a1929a94654"
    private static let authClientId = "64621b96-0f0d-11ec-82a8-0242ac130003"
    static let appId = "014d2225-8495-4735-812d-2616334fd15d"
    static let authCfb = "RFtoRq/vDXJmRndoZaZQyfOot7OrIqGVFj96iY2WL3yyH5Z/pUvlUhqmCxD2t+D65SQ="
    // swiftlint:disable:next line_length
    private static let authBasicCredentials = "6d477c38-3ca4-4cf3-9557-2a1929a94654:KUy49XxPzLpLuoK0xhBC77W6VXhmtQR9iQhmIFjjoY4IpxsV"

    let deviceId = UUID().uuidString

    var baseURL: String { "https://\(Self.apiDomain):\(Self.apiPort)" }
    private var authBaseURL: String { "https://\(Self.authHost)" }
    var apiHost: String { "\(Self.apiDomain):\(Self.apiPort)" }

    public override var apiName: String { "HyundaiEurope" }

    // MARK: - Headers

    func authorizedHeaders(authToken: AuthToken) -> [String: String] {
        [
            "Authorization": "Bearer \(authToken.accessToken)",
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "okhttp/3.14.9",
            "ccsp-service-id": Self.clientId,
            "ccsp-application-id": Self.appId,
            "ccsp-device-id": deviceId,
            "Host": apiHost,
            "Connection": "Keep-Alive",
            "Accept-Encoding": "gzip",
            "Stamp": generateStamp()
        ]
    }

    func generateStamp() -> String {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let message = "\(Self.appId):\(timestamp)"
        guard let cfbData = Data(base64Encoded: Self.authCfb) else { return message }
        let key = SymmetricKey(data: cfbData.prefix(32))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return Data(signature).base64EncodedString()
    }

    // MARK: - Login (OAuth2 Flow)

    public func login() async throws -> AuthToken {
        BBLogger.info(.auth, "HyundaiEurope: Starting OAuth2 login flow")

        // Step 1: Get integration info
        let (intUserId, serviceId) = try await getIntegrationInfo()

        // Step 2: Initialize login and get session cookies
        let (cookies, actionUrl) = try await initializeLogin(intUserId: intUserId, serviceId: serviceId)

        // Step 3: Submit credentials
        let authCode = try await submitCredentials(actionUrl: actionUrl, cookies: cookies)

        // Step 4: Exchange auth code for tokens
        let token = try await exchangeCodeForToken(authCode: authCode)

        BBLogger.info(.auth, "HyundaiEurope: Login completed successfully")
        return token
    }

    private func getIntegrationInfo() async throws -> (String, String) {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/v1/user/integrationinfo")!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("okhttp/3.14.9", forHTTPHeaderField: "User-Agent")
        request.setValue(Self.clientId, forHTTPHeaderField: "ccsp-service-id")
        request.setValue(Self.appId, forHTTPHeaderField: "ccsp-application-id")
        request.setValue(deviceId, forHTTPHeaderField: "ccsp-device-id")
        request.setValue(apiHost, forHTTPHeaderField: "Host")
        request.setValue(generateStamp(), forHTTPHeaderField: "Stamp")

        let (data, _) = try await urlSession.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let intUserId = json["userId"] as? String,
              let serviceId = json["serviceId"] as? String else {
            throw APIError(message: "Failed to parse integration info", apiName: apiName)
        }

        return (intUserId, serviceId)
    }

    private func initializeLogin(intUserId: String, serviceId: String) async throws -> ([HTTPCookie], String) {
        var components = URLComponents(string: "\(authBaseURL)/auth/realms/euhyundaiidm/protocol/openid-connect/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.authClientId),
            URLQueryItem(name: "scope", value: "openid profile email phone"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "hkid_session_reset", value: "true"),
            URLQueryItem(name: "redirect_uri", value: "\(baseURL)/api/v1/user/integration/redirect/login"),
            URLQueryItem(name: "ui_locales", value: "en"),
            URLQueryItem(name: "state", value: serviceId),
            URLQueryItem(name: "intUserId", value: intUserId)
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        let session = URLSession(configuration: config)

        var currentRequest = request
        var cookies: [HTTPCookie] = []
        var actionUrl: String?

        for _ in 0..<10 {
            let (data, response) = try await session.data(for: currentRequest)

            if let httpResponse = response as? HTTPURLResponse {
                if let url = httpResponse.url,
                   let headerFields = httpResponse.allHeaderFields as? [String: String] {
                    cookies.append(contentsOf: HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url))
                }

                if (300..<400).contains(httpResponse.statusCode),
                   let location = httpResponse.value(forHTTPHeaderField: "Location"),
                   let redirectUrl = URL(string: location, relativeTo: currentRequest.url) {
                    currentRequest = URLRequest(url: redirectUrl)
                    currentRequest.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                    continue
                }

                if let html = String(data: data, encoding: .utf8) {
                    actionUrl = extractFormActionURL(from: html, baseURL: currentRequest.url)
                }
            }
            break
        }

        guard let formActionUrl = actionUrl else {
            throw APIError(message: "Failed to find login form action URL", apiName: apiName)
        }

        return (cookies, formActionUrl)
    }

    private func extractFormActionURL(from html: String, baseURL: URL?) -> String? {
        let pattern = #"<form[^>]*action=["\']([^"\']+)["\']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }

        let actionPath = String(html[range]).replacingOccurrences(of: "&amp;", with: "&")

        if actionPath.hasPrefix("http") { return actionPath }
        if let base = baseURL { return URL(string: actionPath, relativeTo: base)?.absoluteString }
        return nil
    }

    private func submitCredentials(actionUrl: String, cookies: [HTTPCookie]) async throws -> String {
        guard let url = URL(string: actionUrl) else {
            throw APIError(message: "Invalid login form URL", apiName: apiName)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue(cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")

        let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? username
        let encodedPassword = password.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? password
        let bodyString = "username=\(encodedUsername)&password=\(encodedPassword)&credentialId="
        request.httpBody = Data(bodyString.utf8)

        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        let session = URLSession(configuration: config)

        var currentRequest = request

        for _ in 0..<10 {
            let (_, response) = try await session.data(for: currentRequest)

            if let httpResponse = response as? HTTPURLResponse {
                if let location = httpResponse.value(forHTTPHeaderField: "Location") {
                    if let redirectUrl = URL(string: location),
                       let components = URLComponents(url: redirectUrl, resolvingAgainstBaseURL: false),
                       let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
                        return code
                    }

                    if let redirectUrl = URL(string: location, relativeTo: currentRequest.url) {
                        currentRequest = URLRequest(url: redirectUrl)
                        currentRequest.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                        continue
                    }
                }

                if httpResponse.statusCode == 200 {
                    throw APIError.invalidCredentials("Login failed - check username and password", apiName: apiName)
                }
            }
            break
        }

        throw APIError(message: "Failed to get authorization code", apiName: apiName)
    }

    private func exchangeCodeForToken(authCode: String) async throws -> AuthToken {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/v1/user/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let authHeader = "Basic \(Data(Self.authBasicCredentials.utf8).base64EncodedString())"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")

        let redirectUri = "\(baseURL)/api/v1/user/integration/redirect/login"
        let bodyString = "grant_type=authorization_code&code=\(authCode)&redirect_uri=\(redirectUri)"
        request.httpBody = Data(bodyString.utf8)

        let (data, _) = try await urlSession.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String,
              let expiresIn = json["expires_in"] as? Int else {
            throw APIError(message: "Failed to parse token response", apiName: apiName)
        }

        return AuthToken(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn))
        )
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

    public func fetchVehicleStatus(for vehicle: Vehicle, authToken: AuthToken) async throws -> VehicleStatus {
        let (data, _, _) = try await performJSONRequest(
            url: "\(baseURL)/api/v1/spa/vehicles/\(vehicle.regId)/ccs2/carstatus/latest",
            method: .GET,
            headers: authorizedHeaders(authToken: authToken),
            requestType: .fetchVehicleStatus
        )

        return try parseVehicleStatusResponse(data, for: vehicle)
    }

    // MARK: - Commands

    public func sendCommand(for vehicle: Vehicle, command: VehicleCommand, authToken: AuthToken) async throws {
        let (path, body) = commandPathAndBody(for: command)
        let url = "\(baseURL)/api/v2/spa/vehicles/\(vehicle.regId)/\(path)"

        _ = try await performJSONRequest(
            url: url,
            method: .POST,
            headers: authorizedHeaders(authToken: authToken),
            body: body,
            requestType: .sendCommand
        )
    }
}
