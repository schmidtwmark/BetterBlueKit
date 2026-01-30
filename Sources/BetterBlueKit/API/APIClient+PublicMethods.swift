//
//  APIClient+PublicMethods.swift
//  BetterBlueKit
//
//  Created by Mark Schmidt on 1/30/26.
//

extension APIClient {

    public func login() async throws -> AuthToken {
        let endpoint = endpointProvider.loginEndpoint()
        let request = try createRequest(from: endpoint)

        BBLogger.info(.auth, "Attempting login")
        let (data, response) = try await performLoggedRequest(request, requestType: .login)

        // Extract headers for parsing
        let headers: [String: String] = response.allHeaderFields.reduce(into: [:]) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String {
                result[key] = value
            }
        }

        return try endpointProvider.parseLoginResponse(data, headers: headers)
    }

    public func fetchVehicles(authToken: AuthToken) async throws -> [Vehicle] {
        let endpoint = endpointProvider.fetchVehiclesEndpoint(authToken: authToken)
        let request = try createRequest(from: endpoint)
        let (data, _) = try await performLoggedRequest(request, requestType: .fetchVehicles)
        return try endpointProvider.parseVehiclesResponse(data)
    }

    public func fetchVehicleStatus(
        for vehicle: Vehicle,
        authToken: AuthToken,
    ) async throws -> VehicleStatus {
        let endpoint = endpointProvider.fetchVehicleStatusEndpoint(
            for: vehicle,
            authToken: authToken,
        )
        let request = try createRequest(from: endpoint)
        let (data, _) = try await performLoggedRequest(request, requestType: .fetchVehicleStatus)
        return try endpointProvider.parseVehicleStatusResponse(data, for: vehicle)
    }

    public func sendCommand(
        for vehicle: Vehicle,
        command: VehicleCommand,
        authToken: AuthToken,
    ) async throws {
        let endpoint = endpointProvider.sendCommandEndpoint(
            for: vehicle,
            command: command,
            authToken: authToken,
        )
        let request = try createRequest(from: endpoint)
        let (data, _) = try await performLoggedRequest(request, requestType: .sendCommand)
        try endpointProvider.parseCommandResponse(data)
    }

    public func fetchEVTripDetails(
        for vehicle: Vehicle,
        authToken: AuthToken
    ) async throws -> [EVTripDetail]? {
        guard endpointProvider.supportsEVTripDetails() else {
            return nil
        }

        let endpoint = endpointProvider.evTripDetailsEndpoint(for: vehicle, authToken: authToken)
        let request = try createRequest(from: endpoint)
        let (data, _) = try await performLoggedRequest(request, requestType: .fetchEVTripDetails)
        return try endpointProvider.parseEVTripDetailsResponse(data)
    }
}
