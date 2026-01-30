//
//  HyundaiCanada.swift
//  BetterBlueKit
//
//  Hyundai Canada API Endpoint Provider
//

import Foundation

// MARK: - Hyundai Canada API Endpoint Provider

@MainActor
public final class HyundaiAPIEndpointProviderCanada: HyundaiAPIEndpointProviderBase {

    // MARK: - Canada-specific overrides

    public override var apiHost: String {
        "mybluelink.ca"  // TODO: Verify correct host for Canada
    }

    // MARK: - Endpoints (TODO: Implement Canada-specific endpoints)

    public override func loginEndpoint() -> APIEndpoint {
        // TODO: Implement Canada-specific login
        fatalError("HyundaiCanada: loginEndpoint not yet implemented")
    }

    public override func fetchVehiclesEndpoint(authToken: AuthToken) -> APIEndpoint {
        // TODO: Implement Canada-specific vehicles endpoint
        fatalError("HyundaiCanada: fetchVehiclesEndpoint not yet implemented")
    }

    public override func fetchVehicleStatusEndpoint(for vehicle: Vehicle, authToken: AuthToken) -> APIEndpoint {
        // TODO: Implement Canada-specific status endpoint
        fatalError("HyundaiCanada: fetchVehicleStatusEndpoint not yet implemented")
    }

    public override func sendCommandEndpoint(
        for vehicle: Vehicle,
        command: VehicleCommand,
        authToken: AuthToken
    ) -> APIEndpoint {
        // TODO: Implement Canada-specific command endpoint
        fatalError("HyundaiCanada: sendCommandEndpoint not yet implemented")
    }

    // MARK: - EV Trip Details (Canada does not support this yet)

    public override func supportsEVTripDetails() -> Bool {
        false
    }
}

// MARK: - Type Alias

public typealias HyundaiAPIClientCanada = APIClient<HyundaiAPIEndpointProviderCanada>
