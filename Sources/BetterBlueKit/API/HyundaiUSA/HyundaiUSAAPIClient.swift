//
//  HyundaiUSAAPIClient.swift
//  BetterBlueKit
//
//  Hyundai USA API Client
//

import Foundation

// MARK: - Hyundai USA API Client

@MainActor
public final class HyundaiUSAAPIClient: APIClientBase, APIClientProtocol {

    // MARK: - Constants

    private let clientId = "m66129Bb-em93-SPAHYN-bZ91-am4540zp19920"
    private let clientSecret = "v558o935-6nne-423i-baa8"

    var baseURL: String {
        region.apiBaseURL(for: .hyundai)
    }

    var apiHost: String {
        "api.telematics.hyundaiusa.com"
    }

    public override var apiName: String { "HyundaiUSA" }

    // MARK: - Headers

    func headers() -> [String: String] {
        [
            "client_id": clientId,
            "clientSecret": clientSecret,
            "Host": apiHost,
            "User-Agent": "okhttp/3.12.0",
            "Content-Type": "application/json",
            "Accept": "application/json, text/plain, */*",
            "Accept-Encoding": "gzip, deflate, br",
            "Accept-Language": "en-US,en;q=0.9",
            "Connection": "Keep-Alive"
        ]
    }

    func authorizedHeaders(authToken: AuthToken, vehicle: Vehicle? = nil, refresh: Bool = false) -> [String: String] {
        var result = headers()
        result["accessToken"] = authToken.accessToken
        result["language"] = "0"
        result["to"] = "ISS"
        result["encryptFlag"] = "false"
        result["from"] = "SPA"
        result["offset"] = "-5"
        result["brandIndicator"] = "H"
        result["origin"] = "https://\(apiHost)"
        result["referer"] = "https://\(apiHost)/login"
        result["username"] = username
        result["blueLinkServicePin"] = pin
        // "refresh: true" forces the backend to poll the vehicle's modem for
        // current state instead of returning the last cached snapshot. This
        // is what MyHyundai uses for pull-to-refresh.
        result["refresh"] = refresh ? "true" : "false"

        if let vehicle {
            result["gen"] = String(vehicle.generation)
            result["registrationId"] = vehicle.regId
            result["vin"] = vehicle.vin
            result["APPCLOUD-VIN"] = vehicle.vin
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMddHHmmss"
        result["payloadGenerated"] = dateFormatter.string(from: Date())
        result["includeNonConnectedVehicles"] = "Y"

        return result
    }

    // MARK: - APIClientProtocol Implementation

    public func login() async throws -> AuthToken {
        BBLogger.info(.auth, "HyundaiUSA: Attempting login for \(username)")

        let (data, _, _) = try await performJSONRequest(
            url: "\(baseURL)/v2/ac/oauth/token",
            method: .POST,
            headers: headers(),
            body: ["username": username, "password": password],
            requestType: .login
        )

        return try parseLoginResponse(data)
    }

    public func fetchVehicles(authToken: AuthToken) async throws -> [Vehicle] {
        let (data, _, _) = try await performJSONRequest(
            url: "\(baseURL)/ac/v2/enrollment/details/\(username)",
            method: .GET,
            headers: authorizedHeaders(authToken: authToken),
            requestType: .fetchVehicles
        )

        return try parseVehiclesResponse(data)
    }

    public func fetchVehicleStatus(
        for vehicle: Vehicle,
        authToken: AuthToken,
        cached: Bool
    ) async throws -> VehicleStatus {
        let statusHeaders = authorizedHeaders(authToken: authToken, vehicle: vehicle, refresh: !cached)

        let (data, _, _) = try await performJSONRequest(
            url: "\(baseURL)/ac/v2/rcs/rvs/vehicleStatus",
            method: .GET,
            headers: statusHeaders,
            requestType: .fetchVehicleStatus,
            vin: vehicle.vin
        )

        return try parseVehicleStatusResponse(data, for: vehicle)
    }

    public func sendCommand(for vehicle: Vehicle, command: VehicleCommand, authToken: AuthToken) async throws {
        let url = commandURL(for: command, vehicle: vehicle)
        let body = commandBody(for: command, vehicle: vehicle)

        let (data, _, _) = try await performJSONRequest(
            url: url,
            method: .POST,
            headers: authorizedHeaders(authToken: authToken, vehicle: vehicle),
            body: body,
            requestType: .sendCommand,
            vin: vehicle.vin
        )

        try parseCommandResponse(data)
    }

    public func fetchEVTripDetails(for vehicle: Vehicle, authToken: AuthToken) async throws -> [EVTripDetail]? {
        var tripHeaders = authorizedHeaders(authToken: authToken, vehicle: vehicle)
        tripHeaders["userId"] = username
        tripHeaders["access_token"] = authToken.accessToken

        let (data, _, _) = try await performJSONRequest(
            url: "\(baseURL)/ac/v2/ts/alerts/maintenance/evTripDetails",
            method: .GET,
            headers: tripHeaders,
            requestType: .fetchEVTripDetails,
            vin: vehicle.vin
        )

        return try parseEVTripDetailsResponse(data)
    }
}
