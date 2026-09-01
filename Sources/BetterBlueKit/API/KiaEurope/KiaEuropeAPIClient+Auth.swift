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

    // The password signin flow moved to EuropeCCILogin.swift: the legacy
    // IDPConnect signin (authorize → certs → encrypted-signin → token
    // exchange with the ccsp-service-id client) has been WAF-blocked since
    // 2026-08-11, so password logins now run the shared OneApp/CCI flow.
    // Only the legacy refresh grant remains here — pre-CCI refresh tokens
    // still work against it.

    /// Refresh-grant: trade stored refresh_token for a fresh access_token.
    /// No `redirect_uri` — upstream doesn't send one on the refresh grant.
    func getAccessTokenFromRefreshToken() async throws -> AuthToken {
        let fields: [(String, String)] = [
            ("grant_type", "refresh_token"),
            ("refresh_token", configuration.refreshToken ?? ""),
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
