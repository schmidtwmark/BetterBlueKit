//
//  HyundaiEuropeAPIClient+TripDetails.swift
//  BetterBlueKit
//
//  EV trip history for Hyundai Europe: day-level summaries from
//  /drvhistory and per-trip drill-down from /tripinfo. Split from the
//  class body to keep it under SwiftLint's 250-line type-body cap.
//

import Foundation

extension HyundaiEuropeAPIClient {

    public func optionalFeaturesSupported() -> [OptionalAPIFeature] {
        [.evTripSummary, .evTripInfo]
    }

    public func fetchEVTripSummary(for vehicle: Vehicle, authToken: AuthToken) async throws -> [EVTripSummary]? {
        let ccs2 = vehicle.marketOptions?.ccs2Supported ?? false
        let url = "\(baseURL)/api/v1/spa/vehicles/\(vehicle.regId)/drvhistory"

        let (data, _, _) = try await performJSONRequest(
            url: url,
            method: .POST,
            headers: authorizedHeaders(authToken: authToken, ccs2: ccs2),
            body: ["periodTarget": 0],
            requestType: .fetchEVTripSummary,
            vin: vehicle.vin
        )

        return try parseEVTripSummaryResponse(data, vehicle: vehicle)
    }

    public func fetchEVTripInfo(for vehicle: Vehicle, authToken: AuthToken, date: Date) async throws -> [EVTripInfo]? {
        let ccs2 = vehicle.marketOptions?.ccs2Supported ?? false
        let url = "\(baseURL)/api/v1/spa/vehicles/\(vehicle.regId)/tripinfo"

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyyMMdd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let dateString = dateFormatter.string(from: date)

        let (data, _, _) = try await performJSONRequest(
            url: url,
            method: .POST,
            headers: authorizedHeaders(authToken: authToken, ccs2: ccs2),
            body: [
                "tripPeriodType": 1,
                "setTripDay": dateString
            ],
            requestType: .fetchEVTripInfo,
            vin: vehicle.vin
        )

        return try parseIndividualTripsResponse(data)
    }
}
