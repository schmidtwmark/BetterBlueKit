//
//  EuropeCCILogin.swift
//  BetterBlueKit
//
//  OneApp/CCI password login for the European Hyundai and Kia clients.
//
//  Since 2026-08-11 the IDPConnect WAF rejects the legacy authorize/signin
//  flow by client_id ("abusing request", HTTP 400) — see
//  hyundai_kia_connect_api #1273 / #1277, which this ports. The OneApp
//  client_id is not on the block list; its signin code is exchanged at
//  cci-api-eu.{brand}.com for a CCI token set, and the CCI token is then
//  exchanged for a CCS token that the legacy ccapi:8080 vehicle endpoints
//  accept as a normal Bearer access token.
//
//  Legacy 48-character refresh tokens still work against the old
//  oauth2/token refresh grant, so accounts that signed in before the WAF
//  change keep working without this flow. Only fresh password logins (and
//  CCI-token refreshes) come through here.
//

import Foundation

// MARK: - Brand parameters

/// Brand-specific constants for the EU OneApp/CCI login flow.
struct EuropeCCIConfig {
    /// IDP host the signin steps run against (idpconnect-eu.{brand}.com).
    let idpHost: String
    /// OneApp OAuth client — NOT the legacy ccsp-service-id.
    let oneAppClientId: String
    /// OneApp redirect; never actually fetched (the signin 302 is not followed).
    let oneAppRedirectURI: String
    /// CCI API base (cci-api-eu.{brand}.com).
    let cciBaseURL: String
    /// `client-id` header on CCI requests (the OneApp bundle id).
    let packageId: String
    let clientName: String
    let clientOSVersion: String
    let notificationProvider: String

    /// Values observed from the OneApp builds by hyundai_kia_connect_api.
    static let clientVersion = "1.3.3"

    static let hyundai = EuropeCCIConfig(
        idpHost: "https://idpconnect-eu.hyundai.com",
        oneAppClientId: "4f4953b5-02e1-4dbc-8599-87e983ee1be5",
        oneAppRedirectURI: "https://oneapp.hyundai.com/redirect",
        cciBaseURL: "https://cci-api-eu.hyundai.com",
        packageId: "com.hyundai.oneapp.eu",
        clientName: "hyundai",
        clientOSVersion: "18.7",
        notificationProvider: "APNS"
    )

    static let kia = EuropeCCIConfig(
        idpHost: "https://idpconnect-eu.kia.com",
        oneAppClientId: "01b36c86-79e8-486c-8009-15f2ad88d670",
        oneAppRedirectURI: "https://oneapp.kia.com/redirect",
        cciBaseURL: "https://cci-api-eu.kia.com",
        packageId: "com.kia.oneapp.eu",
        clientName: "kia",
        clientOSVersion: "27",
        notificationProvider: "IOS_APPSTORE"
    )
}

// MARK: - CCI token set

/// The full CCI token set. Refreshing requires every field, so the whole set
/// is persisted — serialized into the account's existing `refreshToken` slot
/// (`"cci1:" + base64(JSON)`) to avoid a storage-schema change on either
/// platform. Legacy 48-character refresh tokens never match the prefix, so
/// the two shapes coexist in the same field.
struct CCITokenSet: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var exchangeableAccessToken: String
    var exchangeableRefreshToken: String
    var nonCcsToken: String
    var nonCcsRefreshToken: String
    var idToken: String

    static let storagePrefix = "cci1:"

    func encodeForStorage() -> String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return Self.storagePrefix + data.base64EncodedString()
    }

    static func decodeFromStorage(_ stored: String) -> CCITokenSet? {
        guard stored.hasPrefix(storagePrefix),
              let data = Data(base64Encoded: String(stored.dropFirst(storagePrefix.count))),
              let set = try? JSONDecoder().decode(CCITokenSet.self, from: data) else {
            return nil
        }
        return set
    }
}

// MARK: - Redirect-capturing session

/// The signin POST answers with a 302 whose `Location` carries the auth code.
/// The redirect target (oneapp.{brand}.com) is not a real web endpoint, so
/// the redirect must be captured, never followed.
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// Shares `HTTPCookieStorage.shared` with the default session, so the
/// cookies set by the authorize step are presented on the signin POST.
private let noRedirectSession = URLSession(
    configuration: .default,
    delegate: NoRedirectDelegate(),
    delegateQueue: nil
)

// MARK: - Flow

extension APIClientBase {

    /// Full password login via the OneApp/CCI flow. Returns an `AuthToken`
    /// whose `accessToken` is the CCS token (valid on the legacy ccapi:8080
    /// endpoints) and whose `refreshToken` is the encoded CCI token set.
    func cciPasswordLogin(config: EuropeCCIConfig) async throws -> AuthToken {
        try await cciAuthorize(config: config)
        let jwk = try await cciFetchJWK(config: config)
        let encryptedHex = try rsaEncryptPKCS1(password: password, jwkN: jwk.modulus, jwkE: jwk.exponent)
        let code = try await cciSignin(config: config, encryptedHex: encryptedHex, kid: jwk.kid)
        let set = try await cciTokenExchange(config: config, code: code)
        let (ccsToken, expiresAt) = try await cciExchangeCCSToken(config: config, set: set)
        return AuthToken(
            accessToken: ccsToken,
            refreshToken: set.encodeForStorage(),
            expiresAt: expiresAt,
            deviceId: configuration.deviceId ?? ""
        )
    }

    /// Refresh the CCI token set and re-exchange the CCS token.
    func cciRefreshLogin(config: EuropeCCIConfig, set: CCITokenSet) async throws -> AuthToken {
        let refreshed = try await cciTokenRefresh(config: config, set: set)
        let (ccsToken, expiresAt) = try await cciExchangeCCSToken(config: config, set: refreshed)
        return AuthToken(
            accessToken: ccsToken,
            refreshToken: refreshed.encodeForStorage(),
            expiresAt: expiresAt,
            deviceId: configuration.deviceId ?? ""
        )
    }

    // MARK: Signin steps (idpconnect-eu)

    /// Step 1: GET authorize with the OneApp client_id — passes the WAF and
    /// sets the session cookies the signin POST needs.
    private func cciAuthorize(config: EuropeCCIConfig) async throws {
        let encodedRedirect = config.oneAppRedirectURI.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) ?? config.oneAppRedirectURI
        let url = "\(config.idpHost)/auth/api/v2/user/oauth2/authorize"
            + "?response_type=code&client_id=\(config.oneAppClientId)"
            + "&redirect_uri=\(encodedRedirect)&lang=en&state=ccsp&country=de"
        var request = URLRequest(url: URL(string: url)!)
        request.setValue(Self.euMobileUserAgent, forHTTPHeaderField: "User-Agent")
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await performLoggedRequest(request, requestType: .login)
        } catch let error as APIError where error.code == 400 {
            // A 400 here is the WAF, not the user — the request carries no
            // credentials yet.
            throw APIError(message: Self.wafBlockMessage, apiName: apiName)
        }
        let body = String(data: data, encoding: .utf8) ?? ""
        if body.lowercased().contains("abusing")
            || (response.url?.absoluteString.contains("/error?status=400") ?? false) {
            throw APIError(message: Self.wafBlockMessage, apiName: apiName)
        }
    }

    private static let wafBlockMessage =
        "The sign-in service blocked the request ('abusing request'). "
        + "This is a server-side block, not a credentials problem — please report it."

    /// RSA public key from `/auth/api/v1/accounts/certs`. The IDP rotates
    /// `kid`, so it is threaded back into the signin POST.
    private struct SigninJWK {
        let modulus: String
        let exponent: String
        let kid: String
    }

    /// Step 2: GET certs — JWK (modulus, exponent, kid) for password encryption.
    private func cciFetchJWK(config: EuropeCCIConfig) async throws -> SigninJWK {
        var request = URLRequest(url: URL(string: "\(config.idpHost)/auth/api/v1/accounts/certs")!)
        request.setValue(Self.euMobileUserAgent, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await performLoggedRequest(request, requestType: .login)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let retValue = json["retValue"] as? [String: Any],
              let modulus = retValue["n"] as? String,
              let exponent = retValue["e"] as? String,
              let kid = retValue["kid"] as? String else {
            throw APIError(message: "Failed to parse JWK from /accounts/certs", apiName: apiName)
        }
        return SigninJWK(modulus: modulus, exponent: exponent, kid: kid)
    }

    /// Step 3: POST signin (form-encoded, RSA-encrypted password). The 302's
    /// `Location` carries `?code=…`; the redirect itself is never followed.
    private func cciSignin(config: EuropeCCIConfig, encryptedHex: String, kid: String) async throws -> String {
        let fields: [(String, String)] = [
            ("client_id", config.oneAppClientId),
            ("encryptedPassword", "true"),
            ("password", encryptedHex),
            ("redirect_uri", config.oneAppRedirectURI),
            ("scope", ""),
            ("nonce", ""),
            ("state", "ccsp"),
            ("username", username),
            ("connector_session_key", ""),
            ("kid", kid),
            ("_csrf", "")
        ]
        var request = URLRequest(url: URL(string: "\(config.idpHost)/auth/account/signin")!)
        request.httpMethod = "POST"
        request.setValue(Self.euMobileUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(fields).data(using: .utf8)
        let (_, response) = try await performLoggedRequest(
            request, requestType: .login, session: noRedirectSession
        )
        guard response.statusCode == 302,
              let location = response.value(forHTTPHeaderField: "Location") else {
            throw APIError.invalidCredentials(
                "Signin failed (HTTP \(response.statusCode)). Check username and password.",
                apiName: apiName
            )
        }
        return try parseCCISigninCode(fromLocation: location)
    }

    /// Parse the signin redirect's query for `code`, translating the known
    /// error shapes into typed errors.
    private func parseCCISigninCode(fromLocation location: String) throws -> String {
        guard let comps = URLComponents(string: location) else {
            throw APIError(message: "Unparseable redirect after signin", apiName: apiName)
        }
        if let code = comps.queryItems?.first(where: { $0.name == "code" })?.value, !code.isEmpty {
            return code
        }
        if let errorDesc = comps.queryItems?.first(where: { $0.name == "error_description" })?.value {
            throw APIError.invalidCredentials(
                "Authentication rejected: \(errorDesc)", apiName: apiName
            )
        }
        if comps.path.contains("/web/v1/user/authorization") {
            throw APIError(
                message: "Account consent required — log in via a browser once to accept the terms, then retry.",
                apiName: apiName
            )
        }
        if comps.path.contains("authorize") {
            throw APIError.invalidCredentials(
                "Authentication failed — returned to login page. Check username and password.",
                apiName: apiName
            )
        }
        throw APIError(message: "Unexpected redirect after signin: \(location)", apiName: apiName)
    }

    // MARK: CCI token endpoints (cci-api-eu)

    /// Step 4: exchange the signin code for the CCI token set. The code goes
    /// in the URL query; the POST has no body.
    private func cciTokenExchange(config: EuropeCCIConfig, code: String) async throws -> CCITokenSet {
        let encodedCode = code.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? code
        var request = URLRequest(
            url: URL(string: "\(config.cciBaseURL)/domain/api/v1/auth/token?code=\(encodedCode)")!
        )
        request.httpMethod = "POST"
        for (key, value) in cciHeaders(config: config) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, _) = try await performLoggedRequest(request, requestType: .login)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["accessToken"] as? String, !accessToken.isEmpty else {
            throw APIError(
                message: "CCI token exchange returned no accessToken — the API may have changed.",
                apiName: apiName
            )
        }
        return CCITokenSet(
            accessToken: accessToken,
            refreshToken: json["refreshToken"] as? String ?? "",
            exchangeableAccessToken: json["exchangeableAccessToken"] as? String ?? "",
            exchangeableRefreshToken: json["exchangeableRefreshToken"] as? String ?? "",
            nonCcsToken: json["nonCcsToken"] as? String ?? "",
            nonCcsRefreshToken: json["nonCcsRefreshToken"] as? String ?? "",
            idToken: json["idToken"] as? String ?? ""
        )
    }

    /// Step 5: exchange the CCI access token for a CCS token, which the
    /// legacy ccapi:8080 endpoints accept as a Bearer access token.
    /// `expiresTime` is a TTL in seconds (86400 = 24h), not an epoch.
    private func cciExchangeCCSToken(
        config: EuropeCCIConfig, set: CCITokenSet
    ) async throws -> (token: String, expiresAt: Date) {
        var request = URLRequest(
            url: URL(string: "\(config.cciBaseURL)/domain/api/v1/auth/token-exchange?serviceType=CCS")!
        )
        request.httpMethod = "POST"
        for (key, value) in cciHeaders(config: config, set: set) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, _) = try await performLoggedRequest(request, requestType: .login)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard let ccsToken = (json["accessToken"] as? String) ?? (json["ccsAccessToken"] as? String),
              !ccsToken.isEmpty else {
            throw APIError(
                message: "CCS token exchange returned no accessToken — the API may have changed.",
                apiName: apiName
            )
        }
        let ttl = (json["expiresTime"] as? Int) ?? 3600
        return (ccsToken, Date().addingTimeInterval(TimeInterval(ttl)))
    }

    /// Refresh the CCI token set — every field is required in the body.
    /// A `set-cookie: t=…` on the response carries an updated exchangeable
    /// token when present.
    private func cciTokenRefresh(config: EuropeCCIConfig, set: CCITokenSet) async throws -> CCITokenSet {
        var request = URLRequest(
            url: URL(string: "\(config.cciBaseURL)/domain/api/v2/auth/token-refresh")!
        )
        request.httpMethod = "POST"
        var headers = cciHeaders(config: config, set: set)
        headers["Content-Type"] = "application/json"
        headers["Content-Length"] = nil
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let body: [String: String] = [
            "accessToken": set.accessToken,
            "refreshToken": set.refreshToken,
            "exchangeableAccessToken": set.exchangeableAccessToken,
            "exchangeableRefreshToken": set.exchangeableRefreshToken,
            "nonCcsToken": set.nonCcsToken,
            "nonCcsRefreshToken": set.nonCcsRefreshToken,
            "idToken": set.idToken
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await performLoggedRequest(request, requestType: .login)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["accessToken"] as? String, !accessToken.isEmpty else {
            throw APIError.invalidCredentials(
                "CCI token refresh failed — please sign in again.", apiName: apiName
            )
        }
        var exchangeable = json["exchangeableAccessToken"] as? String ?? set.exchangeableAccessToken
        // HTTPURLResponse coalesces multiple Set-Cookie headers into one
        // comma-joined string, so anchor on a `t=` at an entry boundary and
        // only accept a token-shaped value (≥20 chars of token alphabet).
        // Without the shape check, a clearing cookie (`t=deleted; Expires=…`)
        // or an unrelated cookie named `t` would overwrite — and persist —
        // a garbage exchangeable token.
        if let setCookie = response.value(forHTTPHeaderField: "Set-Cookie"),
           let match = setCookie.firstMatch(of: #/(?:^|[;,]\s*)t=([A-Za-z0-9._~%+/=-]{20,})/#) {
            exchangeable = String(match.1)
        }
        return CCITokenSet(
            accessToken: accessToken,
            refreshToken: json["refreshToken"] as? String ?? set.refreshToken,
            exchangeableAccessToken: exchangeable,
            exchangeableRefreshToken: json["exchangeableRefreshToken"] as? String ?? set.exchangeableRefreshToken,
            nonCcsToken: json["nonCcsToken"] as? String ?? set.nonCcsToken,
            nonCcsRefreshToken: json["nonCcsRefreshToken"] as? String ?? set.nonCcsRefreshToken,
            idToken: json["idToken"] as? String ?? set.idToken
        )
    }

    /// Headers for the CCI API. Distinctive shapes, per the OneApp builds:
    /// `Authentication` carries the raw nonCcsToken (no Bearer prefix) while
    /// `authorization` carries "Bearer " + the CCI accessToken.
    private func cciHeaders(config: EuropeCCIConfig, set: CCITokenSet? = nil) -> [String: String] {
        var headers: [String: String] = [
            "client-id": config.packageId,
            "client-name": config.clientName,
            "client-version": EuropeCCIConfig.clientVersion,
            "client-os-code": "ios",
            "client-os-version": config.clientOSVersion,
            "client-device-id": configuration.deviceId ?? "",
            "client-device-model": "iPhone",
            "client-notification-provider-type": config.notificationProvider,
            "locale": "EN",
            "timezone": Self.currentUTCOffsetString(),
            "Accept": "application/json",
            "Accept-Language": "en",
            "User-Agent": "okhttp/3.14.9",
            "Content-Length": "0"
        ]
        if let set {
            headers["Authentication"] = set.nonCcsToken
            headers["authorization"] = "Bearer \(set.accessToken)"
            headers["exchangeable-token"] = set.exchangeableAccessToken
            headers["non-ccs-token"] = set.nonCcsToken
        }
        return headers
    }

    /// Current device UTC offset as "+HH:MM".
    nonisolated static func currentUTCOffsetString(timeZone: TimeZone = .current, at date: Date = Date()) -> String {
        let seconds = timeZone.secondsFromGMT(for: date)
        let sign = seconds < 0 ? "-" : "+"
        let absSeconds = abs(seconds)
        return String(format: "%@%02d:%02d", sign, absSeconds / 3600, (absSeconds % 3600) / 60)
    }
}
