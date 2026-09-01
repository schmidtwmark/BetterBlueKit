//
//  HyundaiCanada+Location.swift
//  BetterBlueKit
//
//  Hyundai Canada vehicle location — `fndmcr` with the remote-function
//  identity (`from: SPA`), exactly matching hyundai_kia_connect_api's
//  `get_location`. The endpoint rejects the browser identity
//  (`from: CWP`) with errorCode 6459 regardless of login identity.
//
//  History: this used to be a ladder of endpoint/header strategies
//  (`evc/fme` per BetterBlueKit#36, per-account identity fallbacks)
//  discovered at runtime. It was collapsed to the single upstream
//  pairing when the client was aligned with the Python reference —
//  `evc/fme` had already been observed timing out on every request.
//

import Foundation

extension HyundaiCanadaAPIClient {

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
