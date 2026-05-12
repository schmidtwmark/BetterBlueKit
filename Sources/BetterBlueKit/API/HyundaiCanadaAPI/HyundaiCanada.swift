//
//  HyundaiCanada.swift
//  BetterBlueKit
//
//  Hyundai Canada shared helpers
//

import Foundation

extension HyundaiCanadaAPIClient {

    // MARK: - Headers

    func headers() -> [String: String] {
        [
            "client_id": clientId,
            "client_secret": clientSecret,
            "Host": apiHost,
            "deviceid": deviceId,
            "from": "SPA",
            "language": "0",
            "offset": timezoneOffsetHeader,
            "User-Agent": userAgent,
            "Content-Type": "application/json",
            "Accept": "application/json",
            "origin": "https://\(apiHost)",
            "referer": "https://\(apiHost)/login"
        ]
    }

    func authorizedHeaders(
        authToken: AuthToken,
        vehicleId: String? = nil,
        pAuth: String? = nil
    ) -> [String: String] {
        var result = headers()
        result["Accesstoken"] = authToken.accessToken

        if let vehicleId {
            result["Vehicleid"] = vehicleId
        }
        if let pAuth {
            result["Pauth"] = pAuth
        }
        if let cookie = cloudFlareCookie {
            result["Cookie"] = cookie
        }

        return result
    }

    // MARK: - Cloudflare Cookie

    func fetchCloudFlareCookie() async throws -> String {
        let (data, response) = try await performRequest(
            url: "https://\(apiHost)/login",
            method: .GET,
            headers: headers(),
            requestType: .login
        )

        _ = data

        let responseHeaders = extractResponseHeaders(from: response)
        let cookies = HTTPCookie.cookies(
            withResponseHeaderFields: responseHeaders,
            for: URL(string: "https://\(apiHost)/login")!
        )

        guard let cookie = cookies.first(where: { $0.name.lowercased() == "__cf_bm" }) else {
            throw APIError.logError("CloudFlare cookie missing from login response", apiName: apiName)
        }

        return "__cf_bm=\(cookie.value)"
    }

    // MARK: - Shared Response Parser

    func parseCanadaResponse(_ data: Data, context: String) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.logError(
                "Invalid JSON in Canada \(context) response",
                apiName: apiName
            )
        }

        guard let responseHeader = json["responseHeader"] as? [String: Any] else {
            throw APIError.logError(
                "Missing responseHeader in Canada \(context) response",
                apiName: apiName
            )
        }

        if isCanadaResponseSuccess(responseHeader["responseCode"]) {
            return json
        }

        let error = json["error"] as? [String: Any]
        let errorDesc = (error?["errorDesc"] as? String) ?? "Unknown Canada API error: \(json)"
        let lower = errorDesc.lowercased()

        if lower.contains("expired") || lower.contains("deleted") || lower.contains("ip validation") {
            throw APIError.invalidCredentials(errorDesc, apiName: apiName)
        }

        throw APIError.logError("Canada \(context) failed: \(errorDesc)", apiName: apiName)
    }

    /// Hyundai Canada's `responseCode` field has been observed in three
    /// shapes: integer (`0`/`1`), string (`"0"`/`"1"`), and most
    /// recently — as of mid-2026 — JSON boolean (`false`/`true`).
    /// Boolean values are inverted: `false` means success, `true` means
    /// failure (matching the `responseDesc: "Success"` / `"Failure"`
    /// strings the same field carries).
    func isCanadaResponseSuccess(_ value: Any?) -> Bool {
        if let bool = value as? Bool { return bool == false }
        if let int = value as? Int { return int == 0 }
        if let string = value as? String { return string == "0" || string.lowercased() == "false" }
        return false
    }

    private var timezoneOffsetHeader: String {
        let hours = TimeZone.current.secondsFromGMT() / 3600
        return String(format: "%+03d", hours)
    }
}
