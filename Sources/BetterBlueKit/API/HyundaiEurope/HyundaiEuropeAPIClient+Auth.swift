//
//  HyundaiEuropeAPIClient+Auth.swift
//  BetterBlueKit
//
//  IDPConnect signin and token helpers for Hyundai Europe.
//

import Foundation

extension HyundaiEuropeAPIClient {

    /// IDPConnect headless signin: authorize -> certs -> encrypted-signin -> redirect with ?code=.
    func signin() async throws -> String {
        let state = UUID().uuidString
        try await fetchAuthorizeCookies(state: state)
        let jwk = try await fetchSigninJWK()
        let encryptedHex = try rsaEncryptPKCS1(password: password, jwkN: jwk.modulus, jwkE: jwk.exponent)
        let signinResp = try await submitSignin(encryptedHex: encryptedHex, kid: jwk.kid, state: state)
        return try parseSigninCode(from: signinResp, expectedState: state)
    }

    /// Step 1: GET authorize to establish the IDPConnect session cookies used by signin.
    private func fetchAuthorizeCookies(state: String) async throws {
        let query = Self.formEncode([
            ("response_type", "code"),
            ("client_id", Self.clientId),
            ("redirect_uri", oauthRedirectURI),
            ("lang", "en"),
            ("state", state),
            ("country", "de")
        ])
        var request = URLRequest(url: URL(string: "\(authBaseURL)/auth/api/v2/user/oauth2/authorize?\(query)")!)
        request.setValue(Self.mobileUserAgent, forHTTPHeaderField: "User-Agent")
        _ = try await urlSession.data(for: request)
    }

    /// RSA public key returned by `/auth/api/v1/accounts/certs`.
    private struct HyundaiEuropeJWK {
        let modulus: String
        let exponent: String
        let kid: String
    }

    /// Step 2: GET certs and pull the JWK fields needed for password encryption.
    private func fetchSigninJWK() async throws -> HyundaiEuropeJWK {
        var request = URLRequest(url: URL(string: "\(authBaseURL)/auth/api/v1/accounts/certs")!)
        request.setValue(Self.mobileUserAgent, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await urlSession.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let retValue = json["retValue"] as? [String: Any],
              let modulus = retValue["n"] as? String,
              let exponent = retValue["e"] as? String,
              let kid = retValue["kid"] as? String else {
            throw APIError(message: "Failed to parse JWK from /accounts/certs", apiName: apiName)
        }
        return HyundaiEuropeJWK(modulus: modulus, exponent: exponent, kid: kid)
    }

    /// Step 3: POST signin as form data. URLSession follows IDP redirects;
    /// the final response URL carries either `code` or an actionable error page.
    private func submitSignin(encryptedHex: String, kid: String, state: String) async throws -> URLResponse {
        let fields: [(String, String)] = [
            ("client_id", Self.clientId),
            ("encryptedPassword", "true"),
            ("password", encryptedHex),
            ("redirect_uri", oauthRedirectURI),
            ("scope", ""),
            ("nonce", ""),
            ("state", state),
            ("username", username),
            ("connector_session_key", ""),
            ("kid", kid),
            ("_csrf", "")
        ]
        var request = URLRequest(url: URL(string: "\(authBaseURL)/auth/account/signin")!)
        request.httpMethod = "POST"
        request.setValue(Self.mobileUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(fields).data(using: .utf8)
        let (_, response) = try await urlSession.data(for: request)
        return response
    }

    /// Parse the signin redirect for `code`, or translate browser-only
    /// account/captcha/login redirects into useful API errors.
    private func parseSigninCode(from response: URLResponse, expectedState: String) throws -> String {
        guard let http = response as? HTTPURLResponse,
              let finalURL = http.url,
              let comps = URLComponents(url: finalURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidCredentials("Signin returned no redirect", apiName: apiName)
        }

        if let code = comps.queryItems?.first(where: { $0.name == "code" })?.value,
           !code.isEmpty {
            let returnedState = comps.queryItems?.first(where: { $0.name == "state" })?.value
            guard returnedState == expectedState else {
                throw APIError.invalidCredentials("Signin state mismatch", apiName: apiName)
            }
            return code
        }

        if let error = actionableSigninRedirectError(from: finalURL, components: comps) {
            throw error
        }

        throw APIError(message: "Unexpected redirect after signin: \(finalURL.absoluteString)", apiName: apiName)
    }

    private func actionableSigninRedirectError(from finalURL: URL, components: URLComponents) -> APIError? {
        if let errorDesc = components.queryItems?.first(where: { $0.name == "error_description" })?.value {
            return APIError.invalidCredentials("Authentication rejected: \(errorDesc)", apiName: apiName)
        }
        if let error = components.queryItems?.first(where: { $0.name == "error" })?.value {
            return APIError.invalidCredentials("Authentication rejected: \(error)", apiName: apiName)
        }

        let path = components.path.lowercased()
        let absolute = finalURL.absoluteString.lowercased()
        if path.contains("captcha") || absolute.contains("captcha") {
            return APIError(
                message: "Hyundai account requires CAPTCHA verification. Sign in in a browser once, then try again.",
                apiName: apiName
            )
        }
        if path.contains("authorization") || path.contains("consent") || absolute.contains("terms") {
            return APIError(
                message: "Hyundai account consent is required. Sign in in a browser once to accept the terms.",
                apiName: apiName
            )
        }
        if path.contains("/auth/account/signin") || absolute.contains("login") {
            return APIError.invalidCredentials(
                "Authentication returned to the Hyundai login page. Check username and password.",
                apiName: apiName
            )
        }
        return nil
    }

    /// Exchange `code` from the signin redirect for access + refresh tokens.
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

    /// Shared POST /oauth2/token helper for authorization-code and refresh grants.
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
