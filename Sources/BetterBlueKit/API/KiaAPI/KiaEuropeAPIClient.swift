//
//  KiaEuropeAPIClient.swift
//  BetterBlueKit
//
//  Kia Europe API Client (Stub)
//

import Foundation

// MARK: - Kia Europe API Client

@MainActor
public final class KiaEuropeAPIClient: APIClientBase, APIClientProtocol {

    public override var apiName: String { "KiaEurope" }

    // MARK: - APIClientProtocol Implementation (Stubs)

    public func login() async throws -> AuthToken {
        throw APIError.regionNotSupported(
            "Kia Europe is not yet implemented. " +
            "See https://github.com/schmidtwmark/BetterBlueKit for updates.",
            apiName: apiName
        )
    }

    public func fetchVehicles(authToken: AuthToken) async throws -> [Vehicle] {
        throw APIError.regionNotSupported("Kia Europe is not yet implemented.", apiName: apiName)
    }

    public func fetchVehicleStatus(for vehicle: Vehicle, authToken: AuthToken) async throws -> VehicleStatus {
        throw APIError.regionNotSupported("Kia Europe is not yet implemented.", apiName: apiName)
    }

    public func sendCommand(for vehicle: Vehicle, command: VehicleCommand, authToken: AuthToken) async throws {
        throw APIError.regionNotSupported("Kia Europe is not yet implemented.", apiName: apiName)
    }

    public func fetchEVTripDetails(for vehicle: Vehicle, authToken: AuthToken) async throws -> [EVTripDetail]? {
        nil
    }
}
