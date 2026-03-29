//
//  HyundaiCanadaAPIClient.swift
//  BetterBlueKit
//
//  Hyundai Canada API Client
//

import Foundation

// MARK: - Hyundai Canada API Client

@MainActor
public final class HyundaiCanadaAPIClient: APIClientBase, APIClientProtocol {

    // MARK: - Constants

    let clientId = "HATAHSPACA0232141ED9722C67715A0B"
    let clientSecret = "CLISCR01AHSPA"
    let userAgent = "MyHyundai/2.0.25 (iPhone; iOS 18.3; Scale/3.00)"

    let deviceId = UUID().uuidString.uppercased()

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

    var baseURL: String { region.apiBaseURL(for: .hyundai) }
    var apiBaseURL: String { "\(baseURL)/tods/api" }
    var apiHost: String { "mybluelink.ca" }

    public override var apiName: String { "HyundaiCanada" }

    // MARK: - APIClientProtocol Implementation

    public func login() async throws -> AuthToken {
        BBLogger.info(.auth, "HyundaiCanada: starting login")

        let cookie = try await ensureCloudFlareCookie()

        var loginHeaders = headers()
        loginHeaders["Cookie"] = cookie

        let (data, _, _) = try await performJSONRequest(
            url: "\(apiBaseURL)/v2/login",
            method: .POST,
            headers: loginHeaders,
            body: [
                "loginId": username,
                "password": password
            ],
            requestType: .login
        )

        return try parseCanadaLoginResponse(data)
    }

    public func fetchVehicles(authToken: AuthToken) async throws -> [Vehicle] {
        _ = try await ensureCloudFlareCookie()

        let (data, _, _) = try await performJSONRequest(
            url: "\(apiBaseURL)/vhcllst",
            method: .POST,
            headers: authorizedHeaders(authToken: authToken),
            requestType: .fetchVehicles
        )

        return try parseCanadaVehiclesResponse(data)
    }

    // Backwards-compatible implementation - forward to the new cached-aware API
    public func fetchVehicleStatus(for vehicle: Vehicle, authToken: AuthToken) async throws -> VehicleStatus {
        return try await fetchVehicleStatus(for: vehicle, authToken: authToken, cached: true)
    }

    // New API: allow callers to request cached (sltvhcl) or real-time (rltmvhclsts) status
    public func fetchVehicleStatus(
        for vehicle: Vehicle,
        authToken: AuthToken,
        cached: Bool
    ) async throws -> VehicleStatus {
        _ = try await ensureCloudFlareCookie()

        let statusEndpoint = cached ? "sltvhcl" : "rltmvhclsts"
        let (primaryData, _, _) = try await performJSONRequest(
            url: "\(apiBaseURL)/\(statusEndpoint)",
            method: .POST,
            headers: authorizedHeaders(authToken: authToken, vehicleId: vehicle.regId),
            body: ["vehicleId": vehicle.regId],
            requestType: .fetchVehicleStatus
        )

        let statusData = cached ? primaryData : try await fetchRealtimeStatusData(
            primaryData: primaryData,
            vehicle: vehicle,
            authToken: authToken
        )
        let finalData = await injectLocationCoordinates(into: statusData, vehicle: vehicle, authToken: authToken)

        do {
            return try parseCanadaVehicleStatusResponse(finalData, for: vehicle)
        } catch {
            BBLogger.debug(.api, "HyundaiCanada: parsing final status payload failed: \(error)")
            return try parseCanadaVehicleStatusResponse(primaryData, for: vehicle)
        }
    }

    private func fetchRealtimeStatusData(
        primaryData: Data,
        vehicle: Vehicle,
        authToken: AuthToken
    ) async throws -> Data {
        // Fetch cached sltvhcl payload for complete vehicle metadata
        var finalData = primaryData
        do {
            let (cachedData, _, _) = try await performJSONRequest(
                url: "\(apiBaseURL)/sltvhcl",
                method: .POST,
                headers: authorizedHeaders(authToken: authToken, vehicleId: vehicle.regId),
                body: ["vehicleId": vehicle.regId],
                requestType: .fetchVehicleStatus
            )
            finalData = cachedData
        } catch {
            BBLogger.debug(.api, "HyundaiCanada: failed fetching sltvhcl: \(error)")
        }

        return finalData
    }

    private func injectLocationCoordinates(into data: Data, vehicle: Vehicle, authToken: AuthToken) async -> Data {
        do {
            let pAuth = try await fetchCommandAuthCode(authToken: authToken)
            let (locationData, _, _) = try await performJSONRequest(
                url: "\(apiBaseURL)/fndmcr",
                method: .POST,
                headers: authorizedHeaders(authToken: authToken, vehicleId: vehicle.regId, pAuth: pAuth),
                body: ["pin": pin],
                requestType: .fetchVehicleStatus
            )
            let location = try parseCanadaLocationResponse(locationData)

            guard var finalJson = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return data
            }

            let coord: [String: Any] = [
                "lat": location.latitude,
                "lon": location.longitude
            ]
            var result = finalJson["result"] as? [String: Any] ?? [:]
            var status = result["status"] as? [String: Any]
                ?? result["vehicleStatus"] as? [String: Any] ?? [:]
            status["coord"] = coord
            status["vehicleLocation"] = ["coord": coord]
            result["status"] = status
            finalJson["result"] = result
            return try JSONSerialization.data(withJSONObject: finalJson)
        } catch {
            BBLogger.debug(.api, "HyundaiCanada: failed injecting location: \(error)")
            return data
        }
    }

    public func sendCommand(for vehicle: Vehicle, command: VehicleCommand, authToken: AuthToken) async throws {
        _ = try await ensureCloudFlareCookie()

        let authCode = try await fetchCommandAuthCode(authToken: authToken)

        try await sendCommandRequest(
            for: vehicle,
            command: command,
            authToken: authToken,
            authCode: authCode
        )
    }

    public func fetchEVTripDetails(for vehicle: Vehicle, authToken: AuthToken) async throws -> [EVTripDetail]? {
        nil
    }

    // MARK: - Command Flow

    private func fetchCommandAuthCode(authToken: AuthToken) async throws -> String {
        let (data, _, _) = try await performJSONRequest(
            url: "\(apiBaseURL)/vrfypin",
            method: .POST,
            headers: authorizedHeaders(authToken: authToken),
            body: ["pin": pin],
            requestType: .sendCommand
        )

        return try parseCommandAuthResponse(data)
    }

    private func sendCommandRequest(
        for vehicle: Vehicle,
        command: VehicleCommand,
        authToken: AuthToken,
        authCode: String
    ) async throws {
        if case .startClimate = command {
            do {
                try await sendCommandRequest(
                    for: vehicle,
                    command: command,
                    authToken: authToken,
                    authCode: authCode,
                    useRemoteControl: false
                )
                return
            } catch {
                try await sendCommandRequest(
                    for: vehicle,
                    command: command,
                    authToken: authToken,
                    authCode: authCode,
                    useRemoteControl: true
                )
                return
            }
        }

        try await sendCommandRequest(
            for: vehicle,
            command: command,
            authToken: authToken,
            authCode: authCode,
            useRemoteControl: false
        )
    }

    private func sendCommandRequest(
        for vehicle: Vehicle,
        command: VehicleCommand,
        authToken: AuthToken,
        authCode: String,
        useRemoteControl: Bool
    ) async throws {
        let (data, _, _) = try await performJSONRequest(
            url: "\(apiBaseURL)/\(commandPath(for: command))",
            method: .POST,
            headers: authorizedHeaders(authToken: authToken, vehicleId: vehicle.regId, pAuth: authCode),
            body: makeCommandBody(command: command, useRemoteControl: useRemoteControl),
            requestType: .sendCommand
        )

        try validateCommandResponse(data, context: "command")
    }

    private func ensureCloudFlareCookie() async throws -> String {
        if let cloudFlareCookie, !cloudFlareCookie.isEmpty {
            return cloudFlareCookie
        }

        let cookie = try await fetchCloudFlareCookie()
        cloudFlareCookie = cookie
        return cookie
    }
}
