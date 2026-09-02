//
//  HyundaiUSAAPIClient+SurroundView.swift
//  BetterBlueKit
//
//  Hyundai USA "Find My Car SVM" — the 360° camera stills.
//
//  Two endpoints under the same `/ac/v2/` base as the rest of this client:
//
//    svm/findMyCarSVM  (POST) — wakes the cameras, shoots, and uploads.
//                               Returns quickly; the image lands minutes
//                               later. Answers 502 + errorSubCode HT_533
//                               when a previous request is still pending.
//    svm/getSVMDetails (GET)  — returns the captures the server is holding
//                               (newest kept, a few retained), each with
//                               its imagery base64-encoded in `svmImage`.
//
//  The response shape and geometry were confirmed two ways: the app's own
//  bundled sample response (`assets/hma/SVMDetails.json`) and the
//  community capture in hyundai_kia_connect_api#1203. The composite is a
//  4472×720 strip described by `imageSize` — the exact format the Canada
//  client already handles — so `SurroundViewDecoder` is reused verbatim.
//
//  This differs from Hyundai Canada in the envelope, not the imagery:
//  the array is `svmDetails[].svmDetail` (Canada: `result.svmLocations[]`),
//  coordinates are nested under `gpsDetail.coord` (Canada: flat
//  `coordLat`/`coordLon`), and the trigger posts the vehicle identity in
//  the body rather than relying on a stored PIN token.
//

import Foundation

extension HyundaiUSAAPIClient {

    // MARK: - APIClientProtocol

    public func requestSurroundViewCapture(for vehicle: Vehicle, authToken: AuthToken) async throws {
        do {
            _ = try await performJSONRequest(
                url: "\(baseURL)/ac/v2/svm/findMyCarSVM",
                method: .POST,
                headers: authorizedHeaders(authToken: authToken, vehicle: vehicle),
                body: [
                    "vin": vehicle.vin,
                    "username": username,
                    "gen": String(vehicle.generation),
                    "blueLinkServicePin": pin
                ],
                requestType: .requestSurroundView,
                vin: vehicle.vin
            )
        } catch let error as APIError where error.errorType == .serverError {
            // "A capture is already pending" arrives as HTTP 502 with
            // errorSubCode HT_533; `validateHTTPResponse` folds the body
            // into the error message. Remap it so the UI shows a
            // "request in progress" state rather than a generic failure —
            // the same distinction the lock/climate commands draw.
            if error.message.contains("HT_533") {
                throw APIError.concurrentRequest(
                    "A surround view capture is already in progress. Please wait and try again.",
                    apiName: apiName
                )
            }
            throw mapUnsupportedSurroundViewError(error)
        }
    }

    /// Remaps the BLODS refusal for vehicles without the feature —
    /// HTTP 502 with "Your vehicle does not support this feature."
    /// (errorSubMessage "Feature Status is OFF") — into a typed
    /// `.featureNotSupported` error. Hyundai USA offers no per-vehicle
    /// capability flag up front, so this refusal is the only way to learn
    /// a vehicle lacks the cameras; the UI uses the type to explain that
    /// instead of showing a generic server error (BetterBlue#105).
    package func mapUnsupportedSurroundViewError(_ error: APIError) -> APIError {
        guard error.message.contains("does not support this feature") else {
            return error
        }
        return APIError.featureNotSupported(
            "Your vehicle doesn't support surround view — it doesn't have the surround-view camera system.",
            apiName: apiName
        )
    }

    public func fetchSurroundViewCaptures(
        for vehicle: Vehicle,
        authToken: AuthToken
    ) async throws -> [SurroundViewCapture] {
        do {
            let (data, _, _) = try await performJSONRequest(
                url: "\(baseURL)/ac/v2/svm/getSVMDetails",
                method: .GET,
                headers: authorizedHeaders(authToken: authToken, vehicle: vehicle),
                requestType: .fetchSurroundView,
                vin: vehicle.vin
            )

            return try parseUSASurroundViewResponse(data, for: vehicle)
        } catch let error as APIError where error.errorType == .serverError {
            // The gallery endpoint refuses camera-less vehicles the same
            // way the trigger does; give it the same typed remap.
            throw mapUnsupportedSurroundViewError(error)
        }
    }

    // MARK: - Parsing

    package func parseUSASurroundViewResponse(
        _ data: Data,
        for vehicle: Vehicle
    ) throws -> [SurroundViewCapture] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let details = json["svmDetails"] as? [[String: Any]] else {
            throw APIError.logError("Invalid Hyundai USA surround view response", apiName: apiName)
        }

        // Each element wraps its capture in `svmDetail`; Canada's array
        // holds the captures directly. Everything inside matches the
        // parser's defaults: a top-level `time` read ahead of
        // `gpsDetail.time` (a capture taken without a GPS fix may drop
        // `gpsDetail` entirely, and without that fallback every such
        // capture would land on the same "unknown" id and lose its
        // order), and coordinates nested under `gpsDetail.coord`.
        return SurroundViewCaptureParser.captures(
            from: details.compactMap { $0["svmDetail"] as? [String: Any] },
            vin: vehicle.vin,
            apiName: apiName
        )
    }
}
