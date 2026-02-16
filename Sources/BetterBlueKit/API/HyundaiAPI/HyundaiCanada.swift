//
//  HyundaiCanada.swift
//  BetterBlueKit
//
//  Hyundai Canada API Endpoint Provider
//

import Foundation

@MainActor
public final class HyundaiAPIEndpointProviderCanada: HyundaiAPIEndpointProviderBase {
    private let canadaClientId = "HATAHSPACA0232141ED9722C67715A0B"
    private let canadaClientSecret = "CLISCR01AHSPA"
    private let canadaUserAgent = "MyHyundai/2.0.25 (iPhone; iOS 18.3; Scale/3.00)"
    let commandPollIntervalNanoseconds: UInt64 = 2_000_000_000
    private let deviceId = UUID().uuidString.uppercased()

    let hvacFahrenheitValues: [Double] = Array(62...82).map { Double($0) }
    let hvacCelsiusValues: [Double] = [
        17, 17.5, 18, 18.5, 19, 19.5, 20, 20.5, 21, 21.5, 22, 22.5,
        23, 23.5, 24, 24.5, 25, 25.5, 26, 26.5, 27
    ]
    let hvacEncodedValues: [String] = [
        "06H", "07H", "08H", "09H", "0AH", "0BH", "0CH", "0DH", "0EH", "0FH",
        "10H", "11H", "12H", "13H", "14H", "15H", "16H", "17H", "18H", "19H", "1AH"
    ]

    var cloudFlareCookie: String?

    var apiBaseURL: String { "https://\(apiHost)/tods/api" }

    public override var apiHost: String {
        "mybluelink.ca"
    }

    public override func getHeaders() -> [String: String] {
        [
            "client_id": canadaClientId,
            "client_secret": canadaClientSecret,
            "Host": apiHost,
            "deviceid": deviceId,
            "from": "SPA",
            "language": "0",
            "offset": timezoneOffsetHeader,
            "User-Agent": canadaUserAgent,
            "Content-Type": "application/json",
            "Accept": "application/json",
            "origin": "https://\(apiHost)",
            "referer": "https://\(apiHost)/login"
        ]
    }

    func getAuthorizedHeaders(
        authToken: AuthToken,
        vehicleId: String? = nil,
        pAuth: String? = nil
    ) -> [String: String] {
        hydrateCloudFlareCookie(from: authToken)

        var headers = getHeaders()
        headers["Accesstoken"] = authToken.accessToken
        if let vehicleId {
            headers["Vehicleid"] = vehicleId
        }
        if let pAuth {
            headers["Pauth"] = pAuth
        }
        if let cookie = cloudFlareCookie {
            headers["Cookie"] = cookie
        }
        return headers
    }

    public override func loginEndpoint() -> APIEndpoint {
        var headers = getHeaders()
        if let cookie = cloudFlareCookie {
            headers["Cookie"] = cookie
        }

        let loginBody = [
            "loginId": username,
            "password": password
        ]

        return APIEndpoint(
            url: "\(apiBaseURL)/v2/login",
            method: .POST,
            headers: headers,
            body: try? JSONSerialization.data(withJSONObject: loginBody)
        )
    }

    public override func fetchVehiclesEndpoint(authToken: AuthToken) -> APIEndpoint {
        APIEndpoint(
            url: "\(apiBaseURL)/vhcllst",
            method: .POST,
            headers: getAuthorizedHeaders(authToken: authToken)
        )
    }

    public override func fetchVehicleStatusEndpoint(
        for vehicle: Vehicle,
        authToken: AuthToken
    ) -> APIEndpoint {
        let statusBody = ["vehicleId": vehicle.regId]
        return APIEndpoint(
            url: "\(apiBaseURL)/sltvhcl",
            method: .POST,
            headers: getAuthorizedHeaders(authToken: authToken, vehicleId: vehicle.regId),
            body: try? JSONSerialization.data(withJSONObject: statusBody)
        )
    }

    public override func sendCommandEndpoint(
        for vehicle: Vehicle,
        command: VehicleCommand,
        authToken: AuthToken
    ) -> APIEndpoint {
        APIEndpoint(
            url: "\(apiBaseURL)/\(commandPath(for: command))",
            method: .POST,
            headers: getAuthorizedHeaders(authToken: authToken, vehicleId: vehicle.regId),
            body: try? JSONSerialization.data(
                withJSONObject: makeCommandBody(command: command, useRemoteControl: false)
            )
        )
    }

    public override func supportsEVTripDetails() -> Bool {
        false
    }

    func getCloudFlareCookie() async throws -> String {
        guard let url = URL(string: "https://\(apiHost)/login") else {
            throw APIError.logError("Invalid CloudFlare login URL", apiName: "HyundaiAPI")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in getHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.logError(
                "Invalid response fetching CloudFlare cookie",
                apiName: "HyundaiAPI"
            )
        }

        let headerFields = httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String,
               let value = pair.value as? String {
                result[key] = value
            }
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
        guard let cookie = cookies.first(where: { $0.name.lowercased() == "__cf_bm" }) else {
            throw APIError.logError(
                "CloudFlare cookie missing from login response",
                apiName: "HyundaiAPI"
            )
        }

        return "__cf_bm=\(cookie.value)"
    }

    func parseCanadaResponse(_ data: Data, context: String) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.logError(
                "Invalid JSON in Canada \(context) response",
                apiName: "HyundaiAPI"
            )
        }

        guard let responseHeader = json["responseHeader"] as? [String: Any] else {
            throw APIError.logError(
                "Missing responseHeader in Canada \(context) response",
                apiName: "HyundaiAPI"
            )
        }

        let responseCode: Int = extractNumber(from: responseHeader["responseCode"]) ?? -1
        if responseCode == 0 {
            return json
        }

        let error = json["error"] as? [String: Any]
        let errorDesc = (error?["errorDesc"] as? String) ?? "Unknown Canada API error"
        let errorDescLower = errorDesc.lowercased()

        if responseCode == 1,
           errorDescLower.contains("expired") ||
            errorDescLower.contains("deleted") ||
            errorDescLower.contains("ip validation") {
            throw APIError.invalidCredentials(errorDesc, apiName: "HyundaiAPI")
        }

        throw APIError.logError(
            "Canada \(context) failed: \(errorDesc)",
            apiName: "HyundaiAPI"
        )
    }

    func hydrateCloudFlareCookie(from authToken: AuthToken) {
        if cloudFlareCookie == nil,
           let tokenCookie = authToken.authCookie,
           !tokenCookie.isEmpty {
            cloudFlareCookie = tokenCookie
        }
    }

    private var timezoneOffsetHeader: String {
        let hours = TimeZone.current.secondsFromGMT() / 3600
        return String(format: "%+03d", hours)
    }
}

public typealias HyundaiAPIClientCanada = APIClient<HyundaiAPIEndpointProviderCanada>
