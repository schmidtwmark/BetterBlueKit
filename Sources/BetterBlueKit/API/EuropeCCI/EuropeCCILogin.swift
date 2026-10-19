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
//  Since 2026-10-13/14 the three cci-api-eu token calls (auth-code
//  exchange, CCS exchange, refresh) also sit behind a fingerprint gate:
//  unsigned calls answer 9035 (BetterBlue#122). Each now goes to the
//  OneApp's /auth/... route first, signed with X-Fingerprint (see
//  EuropeCCIFingerprint.swift), and falls back to the old /domain/api
//  route only when the gate itself rejects the signed call — porting
//  hyundai_kia_connect_api #1352.
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
    /// `client-name` on the signed auth calls — the Android OneApp's value,
    /// which the fingerprint covers (the legacy routes use `clientName`).
    let fingerprintClientName: String
    /// `X-Brand` on the signed auth calls.
    let brandLabel: String
    /// Secret pieces appended to the X-Fingerprint HMAC key, in order.
    /// Embedded in the Android OneApp 1.4.0 build; they rotate with app
    /// releases, together with `EuropeCCIFingerprint.clientVersion`.
    let fingerprintKey: [String]

    /// Values observed from the OneApp builds by hyundai_kia_connect_api.
    /// Legacy (unsigned) routes only — the signed routes carry the
    /// identity in `EuropeCCIFingerprint`.
    static let clientVersion = "1.3.3"

    static let hyundai = EuropeCCIConfig(
        idpHost: "https://idpconnect-eu.hyundai.com",
        oneAppClientId: "4f4953b5-02e1-4dbc-8599-87e983ee1be5",
        oneAppRedirectURI: "https://oneapp.hyundai.com/redirect",
        cciBaseURL: "https://cci-api-eu.hyundai.com",
        packageId: "com.hyundai.oneapp.eu",
        clientName: "hyundai",
        clientOSVersion: "18.7",
        notificationProvider: "APNS",
        fingerprintClientName: "HyundaiEU",
        brandLabel: "Hyundai",
        fingerprintKey: ["OsZDfDuCyVX", "yfqjCoA2JbX", "2MrLpGwNBC"]
    )

    static let kia = EuropeCCIConfig(
        idpHost: "https://idpconnect-eu.kia.com",
        oneAppClientId: "01b36c86-79e8-486c-8009-15f2ad88d670",
        oneAppRedirectURI: "https://oneapp.kia.com/redirect",
        cciBaseURL: "https://cci-api-eu.kia.com",
        packageId: "com.kia.oneapp.eu",
        clientName: "kia",
        clientOSVersion: "27",
        notificationProvider: "IOS_APPSTORE",
        fingerprintClientName: "KiaEU",
        brandLabel: "Kia",
        fingerprintKey: ["yb4Z1n2nlKe", "ukNilE7QEdb", "KB34nStPVa"]
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
        let signed = cciRequest(
            "\(config.cciBaseURL)/auth/v1/token?code=\(encodedCode)",
            headers: cciSignedHeaders(config: config)
        )
        let legacy = cciRequest(
            "\(config.cciBaseURL)/domain/api/v1/auth/token?code=\(encodedCode)",
            headers: cciHeaders(config: config)
        )
        let (data, _) = try await cciGatedRequest("CCI token exchange", signed: signed, legacy: legacy)
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
        // The signed route carries the CCI token headers on the OneApp
        // identity; they sit outside the signature.
        var signedHeaders = cciSignedHeaders(config: config)
        signedHeaders["authorization"] = "Bearer \(set.accessToken)"
        signedHeaders["Authentication"] = set.nonCcsToken
        if !set.exchangeableAccessToken.isEmpty {
            signedHeaders["exchangeable-token"] = set.exchangeableAccessToken
            signedHeaders["non-ccs-token"] = set.nonCcsToken
        }
        let signed = cciRequest(
            "\(config.cciBaseURL)/auth/v1/token-exchange?serviceType=CCS",
            headers: signedHeaders
        )
        let legacy = cciRequest(
            "\(config.cciBaseURL)/domain/api/v1/auth/token-exchange?serviceType=CCS",
            headers: cciHeaders(config: config, set: set)
        )
        let (data, _) = try await cciGatedRequest("CCS token exchange", signed: signed, legacy: legacy)
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
        let fields: [String: String] = [
            "accessToken": set.accessToken,
            "refreshToken": set.refreshToken,
            "exchangeableAccessToken": set.exchangeableAccessToken,
            "exchangeableRefreshToken": set.exchangeableRefreshToken,
            "nonCcsToken": set.nonCcsToken,
            "nonCcsRefreshToken": set.nonCcsRefreshToken,
            "idToken": set.idToken
        ]
        // The fingerprint covers the body, so sign exactly the bytes sent.
        let body = (try? JSONSerialization.data(
            withJSONObject: fields, options: [.sortedKeys, .withoutEscapingSlashes]
        )) ?? Data()
        var signedHeaders = cciSignedHeaders(config: config, body: String(bytes: body, encoding: .utf8) ?? "")
        signedHeaders["Content-Type"] = "application/json"
        var legacyHeaders = cciHeaders(config: config, set: set)
        legacyHeaders["Content-Type"] = "application/json"
        legacyHeaders["Content-Length"] = nil
        let signed = cciRequest(
            "\(config.cciBaseURL)/auth/v2/token-refresh", headers: signedHeaders, body: body
        )
        let legacy = cciRequest(
            "\(config.cciBaseURL)/domain/api/v2/auth/token-refresh", headers: legacyHeaders, body: body
        )
        let (data, response) = try await cciGatedRequest("CCI token refresh", signed: signed, legacy: legacy)
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

    // MARK: Fingerprint gate

    /// Run a CCI token call on its signed route, retrying on the legacy
    /// unsigned route only when the gate itself rejects the signed call —
    /// so a gate rollback, or a brand the gate hasn't reached, keeps
    /// working. Any other failure on the signed route (a 5xx, 9013 invalid
    /// code, 9030 token expired) is surfaced, never masked by a legacy 200.
    private func cciGatedRequest(
        _ step: String, signed: URLRequest, legacy: URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await performLoggedRequest(
            signed, requestType: .login, validateStatus: false
        )
        if (200 ..< 300).contains(response.statusCode) {
            return (data, response)
        }
        guard EuropeCCIFingerprint.isGateRejection(statusCode: response.statusCode, data: data) else {
            throw cciFailure(step, response: response, data: data)
        }
        BBLogger.warning(
            .auth,
            "\(apiName): fingerprint gate rejected the signed \(step) "
                + "(code \(EuropeCCIFingerprint.errorCode(in: data) ?? 0)); retrying on the legacy route"
        )
        let (legacyData, legacyResponse) = try await performLoggedRequest(
            legacy, requestType: .login, validateStatus: false
        )
        if (200 ..< 300).contains(legacyResponse.statusCode) {
            return (legacyData, legacyResponse)
        }
        // Both routes gated: the signed route's code is the telling one
        // (9036 means the signing constants went stale).
        if EuropeCCIFingerprint.isGateRejection(statusCode: legacyResponse.statusCode, data: legacyData) {
            throw cciFailure(step, response: response, data: data)
        }
        throw cciFailure(step, response: legacyResponse, data: legacyData)
    }

    /// A typed error for a failed CCI token call, carrying the server's
    /// `code` and `message` rather than a bare "HTTP 400: bad request".
    private func cciFailure(_ step: String, response: HTTPURLResponse, data: Data) -> APIError {
        let status = response.statusCode
        let code = EuropeCCIFingerprint.errorCode(in: data)
        if code == 9037, EuropeCCIFingerprint.isGateRejection(statusCode: status, data: data) {
            // The signature carries a timestamp the server only accepts
            // within ~2 minutes of its own clock.
            return APIError(
                message: "The sign-in service rejected the request time (\(step), code 9037). "
                    + "Make sure this device's date and time are set automatically, then try again.",
                code: status,
                apiName: apiName
            )
        }
        if EuropeCCIFingerprint.isGateRejection(statusCode: status, data: data) {
            return APIError(
                message: "The sign-in service rejected BetterBlue's app signature (\(step), code \(code ?? 0)). "
                    + "This is a server-side change, not a credentials problem — please report it.",
                code: status,
                apiName: apiName
            )
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        var message = "\(step) failed (HTTP \(status)" + (code.map { ", code \($0)" } ?? "") + ")"
        if let serverMessage = json?["message"] as? String, !serverMessage.isEmpty {
            message += ": \(serverMessage)"
        }
        switch status {
        case 401: return .invalidCredentials(message, apiName: apiName)
        case 500...: return .serverError(message, apiName: apiName)
        default: return APIError(message: message, code: status, apiName: apiName)
        }
    }

    /// A POST to a CCI token endpoint. Bodyless calls carry an explicit
    /// `Content-Length: 0` from their header set.
    private func cciRequest(_ url: String, headers: [String: String], body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = body
        return request
    }

    /// Headers for the fingerprint-gated routes: the Android OneApp
    /// identity the signature is computed over, plus `X-Timestamp` (ms
    /// epoch, message only) and `X-Fingerprint`. `body` must be the exact
    /// request body; a bodyless call also gets `Content-Length: 0`.
    func cciSignedHeaders(config: EuropeCCIConfig, body: String = "", now: Date = Date()) -> [String: String] {
        let deviceId = configuration.deviceId ?? ""
        let requestId = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(24)
        var headers: [String: String] = [
            "client-id": config.packageId,
            "client-name": config.fingerprintClientName,
            "client-version": EuropeCCIFingerprint.clientVersion,
            "client-os-code": EuropeCCIFingerprint.clientOSCode,
            "client-os-version": EuropeCCIFingerprint.clientOSVersion,
            "client-device-id": deviceId,
            "client-device-model": EuropeCCIFingerprint.clientDeviceModel,
            "client-notification-provider-type": EuropeCCIFingerprint.notificationProvider,
            "locale": "EN",
            "timezone": Self.currentUTCOffsetString(at: now),
            "App-Request-Id": "\(requestId)_\(deviceId.replacingOccurrences(of: "-", with: ""))_AOS",
            "X-Brand": config.brandLabel,
            "X-Region": EuropeCCIFingerprint.appRegion,
            "User-Agent": EuropeCCIFingerprint.userAgent,
            "Accept": "*/*",
            "Accept-Language": "en",
            "X-Timestamp": String(Int64(now.timeIntervalSince1970 * 1000))
        ]
        if body.isEmpty {
            headers["Content-Length"] = "0"
        }
        headers["X-Fingerprint"] = EuropeCCIFingerprint.signature(
            headers: headers, keyPieces: config.fingerprintKey, body: body
        )
        return headers
    }

    /// Headers for the legacy (unsigned) CCI routes. Distinctive shapes, per
    /// the OneApp builds: `Authentication` carries the raw nonCcsToken (no
    /// Bearer prefix) while `authorization` carries "Bearer " + the CCI
    /// accessToken.
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
