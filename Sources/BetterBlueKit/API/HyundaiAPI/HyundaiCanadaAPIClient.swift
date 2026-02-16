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
    private let maxCommandPollAttempts = 10

    let deviceId = UUID().uuidString.uppercased()
    let commandPollIntervalNanoseconds: UInt64 = 2_000_000_000

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

        let cookie = try await fetchCloudFlareCookie()
        cloudFlareCookie = cookie

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
        let (data, _, _) = try await performJSONRequest(
            url: "\(apiBaseURL)/vhcllst",
            method: .POST,
            headers: authorizedHeaders(authToken: authToken),
            requestType: .fetchVehicles
        )

        return try parseCanadaVehiclesResponse(data)
    }

    public func fetchVehicleStatus(for vehicle: Vehicle, authToken: AuthToken) async throws -> VehicleStatus {
        let (data, _, _) = try await performJSONRequest(
            url: "\(apiBaseURL)/sltvhcl",
            method: .POST,
            headers: authorizedHeaders(authToken: authToken, vehicleId: vehicle.regId),
            body: ["vehicleId": vehicle.regId],
            requestType: .fetchVehicleStatus
        )

        return try parseCanadaVehicleStatusResponse(data, for: vehicle)
    }

    public func sendCommand(for vehicle: Vehicle, command: VehicleCommand, authToken: AuthToken) async throws {
        let authCode = try await fetchCommandAuthCode(authToken: authToken)

        let transactionId = try await sendCommandRequest(
            for: vehicle,
            command: command,
            authToken: authToken,
            authCode: authCode
        )

        try await pollForCommandCompletion(
            vehicle: vehicle,
            authToken: authToken,
            authCode: authCode,
            transactionId: transactionId
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
    ) async throws -> String {
        if case .startClimate = command {
            do {
                return try await sendCommandRequest(
                    for: vehicle,
                    command: command,
                    authToken: authToken,
                    authCode: authCode,
                    useRemoteControl: false
                )
            } catch {
                return try await sendCommandRequest(
                    for: vehicle,
                    command: command,
                    authToken: authToken,
                    authCode: authCode,
                    useRemoteControl: true
                )
            }
        }

        return try await sendCommandRequest(
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
    ) async throws -> String {
        let (data, _, response) = try await performJSONRequest(
            url: "\(apiBaseURL)/\(commandPath(for: command))",
            method: .POST,
            headers: authorizedHeaders(authToken: authToken, vehicleId: vehicle.regId, pAuth: authCode),
            body: makeCommandBody(command: command, useRemoteControl: useRemoteControl),
            requestType: .sendCommand
        )

        try validateCommandResponse(data, context: "command")

        let responseHeaders = extractResponseHeaders(from: response)
        guard let transactionId = extractTransactionId(from: responseHeaders) else {
            throw APIError.logError("Canada command missing TransactionId header", apiName: apiName)
        }

        return transactionId
    }

    private func pollForCommandCompletion(
        vehicle: Vehicle,
        authToken: AuthToken,
        authCode: String,
        transactionId: String
    ) async throws {
        var attempts = 0

        while attempts <= maxCommandPollAttempts {
            let (data, _, _) = try await performJSONRequest(
                url: "\(apiBaseURL)/rmtsts",
                method: .POST,
                headers: commandStatusHeaders(
                    authToken: authToken,
                    vehicleId: vehicle.regId,
                    pAuth: authCode,
                    transactionId: transactionId
                ),
                requestType: .sendCommand
            )

            if try isCommandCompleted(data) {
                return
            }

            attempts += 1
            try await Task.sleep(nanoseconds: commandPollIntervalNanoseconds)
        }

        throw APIError.logError("Canada command completion polling timed out", apiName: apiName)
    }
}
