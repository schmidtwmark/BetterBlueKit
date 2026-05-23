//
//  KiaEuropeAPIClient+Auth.swift
//  BetterBlueKit
//
//  Extracted from KiaEuropeAPIClient.swift so the main class file
//  stays under the type-body-length threshold and so the multi-step
//  IDPConnect signin flow can be split into focused helpers without
//  pushing a single method over the function-body-length threshold.
//

import Foundation

extension KiaEuropeAPIClient {

    /// IDPConnect headless signin: authorize → certs → encrypted-signin → 302 with ?code=
    func signin() async throws -> String {
        try await fetchAuthorizeCookies()
        let jwk = try await fetchSigninJWK()
        let encryptedHex = try rsaEncryptPKCS1(password: password, jwkN: jwk.modulus, jwkE: jwk.exponent)
        let signinResp = try await submitSignin(encryptedHex: encryptedHex, kid: jwk.kid)
        return try parseSigninCode(from: signinResp)
    }

    /// Step 1: GET authorize — sets session cookies on idpconnect-eu.kia.com.
    /// Response body discarded; we just need the cookies for the later POST.
    private func fetchAuthorizeCookies() async throws {
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
    }

    /// RSA public key returned by `/auth/api/v1/accounts/certs`. The
    /// IDP rotates `kid`, so we have to thread it back into the
    /// signin POST alongside the encrypted password.
    private struct KiaEuropeJWK {
        /// RSA modulus (JWK field `n`).
        let modulus: String
        /// RSA public exponent (JWK field `e`).
        let exponent: String
        /// Key id; threaded back into the signin POST.
        let kid: String
    }

    /// Step 2: GET certs — pull JWK (modulus, exponent, kid) for password encryption.
    private func fetchSigninJWK() async throws -> KiaEuropeJWK {
        var certsReq = URLRequest(url: URL(string: "\(authBaseURL)/auth/api/v1/accounts/certs")!)
        certsReq.setValue(Self.mobileUserAgent, forHTTPHeaderField: "User-Agent")
        let (certsData, _) = try await urlSession.data(for: certsReq)
        guard let certsJson = try JSONSerialization.jsonObject(with: certsData) as? [String: Any],
              let retValue = certsJson["retValue"] as? [String: Any],
              let modulus = retValue["n"] as? String,
              let exponent = retValue["e"] as? String,
              let kid = retValue["kid"] as? String else {
            throw APIError(message: "Failed to parse JWK from /accounts/certs", apiName: apiName)
        }
        return KiaEuropeJWK(modulus: modulus, exponent: exponent, kid: kid)
    }

    /// Step 4: POST signin (form-encoded). URLSession follows the 302 to the
    /// redirect_uri — the final URL carries `?code=…` (or an error) in its query.
    private func submitSignin(encryptedHex: String, kid: String) async throws -> URLResponse {
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
        return signinResp
    }

    /// Parse the final URL's query for `code` (success) or translate an
    /// error redirect into a typed `APIError`.
    private func parseSigninCode(from response: URLResponse) throws -> String {
        guard let http = response as? HTTPURLResponse,
              let finalURL = http.url,
              let comps = URLComponents(url: finalURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidCredentials("Signin returned no redirect", apiName: apiName)
        }
        if let code = comps.queryItems?.first(where: { $0.name == "code" })?.value,
           !code.isEmpty {
            return code
        }
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

    /// Exchange `?code=…` from the signin redirect for access + refresh tokens.
    func exchangeForToken(code: String) async throws -> AuthToken {
        let fields: [(String, String)] = [
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", oauthRedirectURI),
            ("client_id", Self.clientId),
            ("client_secret", Self.clientSecret)
        ]
        return try await postTokenRequest(fields: fields, isRefresh: true)
    }

    /// Refresh-grant: trade stored refresh_token for a fresh access_token.
    func getAccessTokenFromRefreshToken() async throws -> AuthToken {
        let fields: [(String, String)] = [
            ("grant_type", "refresh_token"),
            ("refresh_token", configuration.refreshToken ?? ""),
            ("redirect_uri", oauthRedirectURI),
            ("client_id", Self.clientId),
            ("client_secret", Self.clientSecret)
        ]
        return try await postTokenRequest(fields: fields, isRefresh: false)
    }

    /// Shared POST /oauth2/token helper for the two token grants above.
    private func postTokenRequest(fields: [(String, String)], isRefresh: Bool) async throws -> AuthToken {
        var request = URLRequest(url: URL(string: "\(authBaseURL)/auth/api/v2/user/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue(Self.mobileUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(fields).data(using: .utf8)
        let (data, _) = try await urlSession.data(for: request)
        return try parseAuthToken(from: data, isRefresh: isRefresh)
    }
}
