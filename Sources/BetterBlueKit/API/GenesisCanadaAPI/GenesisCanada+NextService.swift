//
//  GenesisCanada+NextService.swift
//  BetterBlueKit
//
//  The `nxtsvc` (next service) call — the Canada endpoint
//  that reports the odometer. Ports hyundai_kia_connect_api's
//  `_get_next_service` / `_update_vehicle_properties_service`.
//

import Foundation

extension GenesisCanadaAPIClient {
    /// Ports upstream's `_get_next_service`: POST `nxtsvc` (access token +
    /// vehicleId in the headers, no body) and read the odometer out of
    /// `result.maintenanceInfo`. This is the only Canada endpoint that
    /// reports the odometer — `vhcllst`, `lstvhclsts`, and `rltmvhclsts`
    /// all omit it. Best-effort: a failure here must not take down the
    /// status refresh, it just leaves the odometer as the host last knew it.
    func fetchNextServiceOdometer(vehicle: Vehicle, authToken: AuthToken) async -> Distance? {
        do {
            let (data, _, _) = try await performJSONRequest(
                url: "\(apiBaseURL)/nxtsvc",
                method: .POST,
                headers: authorizedHeaders(authToken: authToken, vehicleId: vehicle.regId),
                requestType: .fetchVehicleStatus,
                vin: vehicle.vin
            )
            return try parseCanadaNextServiceOdometer(data)
        } catch {
            BBLogger.debug(.api, "GenesisCanada: next-service odometer fetch failed: \(error)")
            return nil
        }
    }

    /// Ports upstream's `_update_vehicle_properties_service`: the odometer
    /// lives in `result.maintenanceInfo.currentOdometer` with its unit in
    /// `currentOdometerUnit`.
    package func parseCanadaNextServiceOdometer(_ data: Data) throws -> Distance? {
        let json = try parseCanadaResponse(data, context: "next service")
        guard let result = json["result"] as? [String: Any],
              let info = result["maintenanceInfo"] as? [String: Any] else {
            return nil
        }
        var block: [String: Any] = [:]
        if let value = info["currentOdometer"] { block["value"] = value }
        if let unit = info["currentOdometerUnit"] { block["unit"] = unit }
        return HyundaiCanadaAPIClient(configuration: configuration).parseCanadaOdometerBlock(block)
    }
}
