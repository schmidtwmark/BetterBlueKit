//
//  APIClientBase+ErrorHandling.swift
//  BetterBlueKit
//
//  HTTP + CCSP response validation, split out of APIClientBase to keep the
//  class body within the library's default lint thresholds.
//

import Foundation

extension APIClientBase {

    // MARK: - Error Handling

    func validateHTTPResponse(_ httpResponse: HTTPURLResponse, data: Data, responseBody: String?) throws {
        // CCSP (the EU/AU/IN "Connected Car Service Platform") reports
        // application-level failures inside the body — `retCode: "F"` plus a
        // numeric `resCode` — and usually pairs them with an unhelpful HTTP
        // 400. Decode those first so a duplicate/timeout/rate-limit surfaces
        // as a typed, user-facing error instead of "HTTP 400: bad request".
        try checkCCSPResponseForErrors(data: data)

        if httpResponse.statusCode == 401 {
            throw APIError.invalidCredentials(
                "Authentication expired: \(responseBody ?? "Unknown error")",
                apiName: apiName
            )
        }

        if httpResponse.statusCode == 502 {
            throw APIError.serverError(
                "Server error (502): \(responseBody ?? "Unknown error")",
                apiName: apiName
            )
        }

        if httpResponse.statusCode >= 400 {
            let statusText = HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw APIError(
                message: "HTTP \(httpResponse.statusCode): \(statusText)",
                code: httpResponse.statusCode,
                apiName: apiName
            )
        }
    }

    /// Translate a CCSP `retCode: "F"` error envelope into a typed `APIError`.
    ///
    /// A no-op for any response that isn't a CCSP envelope (no `retCode`/
    /// `resCode`), so the US/Canada/China clients are unaffected. The codes
    /// and their meanings track Home Assistant's `hyundai_kia_connect_api`
    /// `_check_response_for_errors`, which is the reference implementation for
    /// the European Hyundai/Kia API.
    func checkCCSPResponseForErrors(data: Data) throws {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["retCode"] as? String == "F",
              let resCode = json["resCode"] as? String else {
            return
        }
        let resMsg = (json["resMsg"] as? String) ?? "Unknown error"

        switch resCode {
        case "7501": // "Key not authorized" / token expired
            throw APIError.invalidCredentials(
                "Authentication expired — please sign in again.", apiName: apiName
            )
        case "4002": // Invalid deviceId — re-registering the device fixes it
            throw APIError.invalidVehicleSession(
                "Invalid device ID — please sign out and back in.", apiName: apiName
            )
        case "4004": // A previous command is still queued server-side
            throw APIError.concurrentRequest(
                "A previous command is still being processed. Please wait a moment and try again.",
                apiName: apiName
            )
        case "4005": // Control action not supported for this vehicle
            throw APIError(
                message: "This action isn't supported for this vehicle.",
                code: 400, apiName: apiName
            )
        case "4081", "9999": // Request/response timeout
            throw APIError.serverError(
                "The request timed out. Please try again.", apiName: apiName
            )
        case "5031": // Remote control temporarily unavailable
            throw APIError.serverError(
                "Remote control is temporarily unavailable. Please try again later.",
                apiName: apiName
            )
        case "5091": // Exceeds number of requests
            throw APIError.serverError(
                "Too many requests — please wait a while before trying again.",
                apiName: apiName
            )
        case "5921": // No data found yet
            throw APIError(
                message: "No data available from the vehicle yet. Try refreshing in a moment.",
                code: 400, apiName: apiName
            )
        default:
            throw APIError(
                message: "Server returned \(resCode): \(resMsg)",
                code: 400, apiName: apiName
            )
        }
    }

    func handleNetworkError(_ error: Error, context: RequestContext) -> APIError {
        logHTTPRequest(createErrorLogData(context: context, error: error.localizedDescription))
        return APIError(message: "Network error: \(error.localizedDescription)", apiName: apiName)
    }

    /// EU CCSP `resCode 4002` recovery: the server invalidates device
    /// ids routinely (e.g. whenever push delivery fails), and the only
    /// fix is registering a fresh one. Runs `operation`, and on an
    /// invalid-device-session error re-registers the device and retries
    /// once — porting upstream's `@_retry_on_device_id_error`.
    func withDeviceIdRecovery<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as APIError where error.errorType == .invalidVehicleSession {
            BBLogger.info(.api, "\(apiName): invalid device id — re-registering and retrying once")
            _ = try await registerDevice()
            return try await operation()
        }
    }

    /// Fresh 64-char random hex push handle for device registration,
    /// matching upstream's `pushRegId`.
    nonisolated static func randomPushRegId() -> String {
        (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }

    /// `ccuCCS2ProtocolSupport` from the EU vehicle list: any non-zero
    /// value means CCS2 (upstream tests `!= 0`; the field has been seen
    /// above 1, and a plain ==1 check misroutes those cars onto the
    /// legacy endpoints).
    nonisolated static func parseCCS2Flag(_ raw: Any?) -> Bool {
        switch raw {
        case let value as Bool: value
        case let value as Int: value != 0
        case let value as String: (Int(value) ?? 0) != 0 || value.lowercased() == "true"
        default: false
        }
    }
}
