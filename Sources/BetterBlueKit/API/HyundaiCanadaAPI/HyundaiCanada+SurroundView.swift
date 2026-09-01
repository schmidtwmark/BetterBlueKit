//
//  HyundaiCanada+SurroundView.swift
//  BetterBlueKit
//
//  Hyundai Canada Surround View Monitor (SVM)
//
//  Two endpoints, same "remote function call" family as `fndmcr`:
//
//    rfc/fndmcrsvm  — tells the vehicle to wake its cameras, shoot, and
//                     upload. Returns immediately; the images land on
//                     Hyundai's servers a few minutes later.
//    rfc/lastmcrsvm — returns the captures the server is holding
//                     (several, newest first), each with its imagery
//                     base64-encoded in `svmImage`.
//

import Foundation

extension HyundaiCanadaAPIClient {

    // MARK: - APIClientProtocol

    public func requestSurroundViewCapture(for vehicle: Vehicle, authToken: AuthToken) async throws {
        let authCode = try await fetchCommandAuthCode(authToken: authToken)

        _ = try await performSurroundViewRequest(
            path: "rfc/fndmcrsvm",
            vehicle: vehicle,
            authToken: authToken,
            authCode: authCode,
            requestType: .requestSurroundView
        )
    }

    public func fetchSurroundViewCaptures(
        for vehicle: Vehicle,
        authToken: AuthToken
    ) async throws -> [SurroundViewCapture] {
        let authCode = try await fetchCommandAuthCode(authToken: authToken)

        let data = try await performSurroundViewRequest(
            path: "rfc/lastmcrsvm",
            vehicle: vehicle,
            authToken: authToken,
            authCode: authCode,
            requestType: .fetchSurroundView
        )

        return try parseCanadaSurroundViewResponse(data, for: vehicle)
    }

    // MARK: - Request

    /// SVM shares `fndmcr`'s "remote function" family: it answers the
    /// `from: SPA` identity and rejects the browser identity with
    /// errorCode 6459, regardless of how the account logged in.
    /// Verified on a live account — a capture request that 6459'd on
    /// the web-portal headers succeeded first try on these.
    private func performSurroundViewRequest(
        path: String,
        vehicle: Vehicle,
        authToken: AuthToken,
        authCode: String,
        requestType: HTTPRequestType
    ) async throws -> Data {
        let (data, _, _) = try await performJSONRequest(
            url: "\(apiBaseURL)/\(path)",
            method: .POST,
            headers: remoteFunctionHeaders(authToken: authToken, vehicleId: vehicle.regId, pAuth: authCode),
            body: ["pin": pin],
            requestType: requestType,
            vin: vehicle.vin
        )

        // Validated here because this API signals refusal as HTTP 200
        // with `responseCode: 1` in the body.
        _ = try parseCanadaResponse(data, context: "surround view")
        return data
    }

    // MARK: - Parsing

    package func parseCanadaSurroundViewResponse(
        _ data: Data,
        for vehicle: Vehicle
    ) throws -> [SurroundViewCapture] {
        let json = try parseCanadaResponse(data, context: "surround view")

        guard let result = json["result"] as? [String: Any],
              let locations = result["svmLocations"] as? [[String: Any]] else {
            throw APIError.logError("Invalid Canada surround view response", apiName: apiName)
        }

        // Canada stamps the capture at the top level as `utcTime`; the
        // `gpsDetail.time` fallback is the parser's default. Coordinates
        // arrive flat as `coordLat`/`coordLon` rather than in the
        // `coord: { lat, lon }` object the status endpoints use, which
        // the default shape already covers.
        return SurroundViewCaptureParser.captures(
            from: locations,
            vin: vehicle.vin,
            shape: .init(timestamp: [["utcTime"], ["gpsDetail", "time"]]),
            apiName: apiName
        )
    }
}
