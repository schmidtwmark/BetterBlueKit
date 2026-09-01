//
//  HyundaiCanada.swift
//  BetterBlueKit
//
//  Hyundai Canada shared helpers
//

import Foundation

extension HyundaiCanadaAPIClient {

    // MARK: - Headers

    /// The one header identity this client uses — the browser-shaped
    /// set from hyundai_kia_connect_api's `KiaUvoApiCA.API_HEADERS`,
    /// plus the stable per-account `deviceid` (the backend recognizes
    /// the install by it and skips the OTP challenge — BetterBlue#95).
    /// Cookies are NOT set manually: URLSession's shared cookie storage
    /// carries whatever Cloudflare mints, like `requests.Session` does
    /// for the Python reference.
    func headers() -> [String: String] {
        [
            "client_id": clientId,
            "client_secret": clientSecret,
            "deviceid": deviceId,
            "from": "CWP",
            "language": "0",
            "offset": timezoneOffsetHeader,
            "User-Agent": Self.userAgent,
            "Content-Type": "application/json;charset=UTF-8",
            "Accept": "application/json, text/plain, */*",
            "Accept-Language": "en-CA,en-US;q=0.8,en;q=0.5,fr;q=0.3",
            "Origin": "https://\(apiHost)",
            "Referer": "https://\(apiHost)/login",
            "Sec-Fetch-Dest": "empty",
            "Sec-Fetch-Mode": "cors",
            "Sec-Fetch-Site": "same-origin",
            "Pragma": "no-cache",
            "Cache-Control": "no-cache"
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

        return result
    }

    /// Headers for the "remote function" family (`fndmcr`, the SVM
    /// endpoints): the standard set with `from: SPA` and the `/remote/`
    /// referer, exactly as the Python reference's `get_location` does.
    /// These endpoints reject the browser identity with errorCode 6459
    /// regardless of how the account logged in.
    func remoteFunctionHeaders(
        authToken: AuthToken,
        vehicleId: String,
        pAuth: String
    ) -> [String: String] {
        var result = authorizedHeaders(authToken: authToken, vehicleId: vehicleId, pAuth: pAuth)
        result["from"] = "SPA"
        result["Referer"] = "https://\(apiHost)/remote/"
        return result
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

    var timezoneOffsetHeader: String {
        let hours = TimeZone.current.secondsFromGMT() / 3600
        return String(format: "%+03d", hours)
    }
}
