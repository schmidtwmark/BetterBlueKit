//
//  HyundaiCanadaAPIClient.swift
//  BetterBlueKit
//
//  Hyundai Canada wrapper client for custom auth and command flows
//

import Foundation

@MainActor
public final class HyundaiCanadaAPIClient: APIClientProtocol {
    private let client: APIClient<HyundaiAPIEndpointProviderCanada>
    private let endpointProvider: HyundaiAPIEndpointProviderCanada
    private let maxCommandPollAttempts = 10

    public init(configuration: APIClientConfiguration, endpointProvider: HyundaiAPIEndpointProviderCanada) {
        self.endpointProvider = endpointProvider
        self.client = APIClient(configuration: configuration, endpointProvider: endpointProvider)
    }

    public func login() async throws -> AuthToken {
        BBLogger.info(.auth, "HyundaiCanada: starting login")
        let cookie = try await endpointProvider.getCloudFlareCookie()
        endpointProvider.cloudFlareCookie = cookie

        let endpoint = endpointProvider.loginEndpoint()
        let request = try client.createRequest(from: endpoint)
        let (data, response) = try await client.performLoggedRequest(request, requestType: .login)

        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String {
                result[key] = value
            }
        }
        return try endpointProvider.parseCanadaLoginResponse(data, headers: headers)
    }

    public func fetchVehicles(authToken: AuthToken) async throws -> [Vehicle] {
        let endpoint = endpointProvider.fetchVehiclesEndpoint(authToken: authToken)
        let request = try client.createRequest(from: endpoint)
        let (data, _) = try await client.performLoggedRequest(request, requestType: .fetchVehicles)
        return try endpointProvider.parseCanadaVehiclesResponse(data)
    }

    public func fetchVehicleStatus(for vehicle: Vehicle, authToken: AuthToken) async throws -> VehicleStatus {
        let endpoint = endpointProvider.fetchVehicleStatusEndpoint(for: vehicle, authToken: authToken)
        let request = try client.createRequest(from: endpoint)
        let (data, _) = try await client.performLoggedRequest(request, requestType: .fetchVehicleStatus)
        return try endpointProvider.parseCanadaVehicleStatusResponse(data, for: vehicle)
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
        try await client.fetchEVTripDetails(for: vehicle, authToken: authToken)
    }

    private func fetchCommandAuthCode(authToken: AuthToken) async throws -> String {
        let endpoint = endpointProvider.commandAuthEndpoint(authToken: authToken)
        let request = try client.createRequest(from: endpoint)
        let (data, _) = try await client.performLoggedRequest(request, requestType: .sendCommand)
        return try endpointProvider.parseCommandAuthResponse(data)
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
        let endpoint = endpointProvider.commandEndpoint(
            for: vehicle,
            command: command,
            authToken: authToken,
            authCode: authCode,
            useRemoteControl: useRemoteControl
        )
        let request = try client.createRequest(from: endpoint)
        let (data, response) = try await client.performLoggedRequest(request, requestType: .sendCommand)
        try endpointProvider.validateCommandResponse(data, context: "command")

        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String {
                result[key] = value
            }
        }

        guard let transactionId = endpointProvider.extractTransactionId(from: headers) else {
            throw APIError.logError("Canada command missing TransactionId header", apiName: "HyundaiAPI")
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
            let endpoint = endpointProvider.commandStatusEndpoint(
                vehicle: vehicle,
                authToken: authToken,
                authCode: authCode,
                transactionId: transactionId
            )
            let request = try client.createRequest(from: endpoint)
            let (data, _) = try await client.performLoggedRequest(request, requestType: .sendCommand)

            if try endpointProvider.isCommandCompleted(data) {
                return
            }

            attempts += 1
            try await Task.sleep(nanoseconds: endpointProvider.commandPollSleepNanoseconds)
        }

        throw APIError.logError(
            "Canada command completion polling timed out",
            apiName: "HyundaiAPI"
        )
    }
}
