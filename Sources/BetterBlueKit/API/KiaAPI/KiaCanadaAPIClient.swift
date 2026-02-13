//
//  KiaCanadaAPIClient.swift
//  BetterBlueKit
//
//  Kia Canada API Client (Stub)
//

import Foundation

// MARK: - Kia Canada API Client

@MainActor
public final class KiaCanadaAPIClient: APIClientBase, APIClientProtocol {

    public override var apiName: String { "KiaCanada" }

    // MARK: - APIClientProtocol Implementation (Stubs)

    public func login() async throws -> AuthToken {
        throw APIError.regionNotSupported(
            "Kia Canada is not yet implemented. " +
            "See https://github.com/schmidtwmark/BetterBlueKit for updates.",
            apiName: apiName
        )
    }

    public func fetchVehicles(authToken: AuthToken) async throws -> [Vehicle] {
        throw APIError.regionNotSupported("Kia Canada is not yet implemented.", apiName: apiName)
    }

    public func fetchVehicleStatus(for vehicle: Vehicle, authToken: AuthToken) async throws -> VehicleStatus {
        throw APIError.regionNotSupported("Kia Canada is not yet implemented.", apiName: apiName)
    }

    public func sendCommand(for vehicle: Vehicle, command: VehicleCommand, authToken: AuthToken) async throws {
        throw APIError.regionNotSupported("Kia Canada is not yet implemented.", apiName: apiName)
    }

    public func fetchEVTripDetails(for vehicle: Vehicle, authToken: AuthToken) async throws -> [EVTripDetail]? {
        nil
    }
}
