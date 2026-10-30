//
//  GenesisCanada+Location.swift
//  BetterBlueKit
//
//  Genesis Canada location fallback, based on Hyundai Canada's `fndmcr`.
//  Status responses normally supply the location. This fallback remains
//  unverified for Genesis.
//

import Foundation

extension GenesisCanadaAPIClient {

    func fetchLocationData(vehicle: Vehicle, authToken: AuthToken, pAuth: String) async throws -> Data {
        let (data, _, _) = try await performJSONRequest(
            url: "\(apiBaseURL)/fndmcr",
            method: .POST,
            headers: remoteFunctionHeaders(authToken: authToken, vehicleId: vehicle.regId, pAuth: pAuth),
            body: ["pin": pin],
            requestType: .fetchVehicleStatus,
            vin: vehicle.vin
        )

        // Validated here so an API-level refusal (HTTP 200 with
        // `responseCode: 1`) surfaces as a thrown error the status
        // fetch can swallow, rather than parsing as empty coordinates.
        _ = try parseCanadaResponse(data, context: "location")
        return data
    }
}
