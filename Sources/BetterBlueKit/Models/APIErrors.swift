//
//  APIErrors.swift
//  BetterBlueKit
//
//  API error types and handling
//

import Foundation

// MARK: - Error Types

public struct HyundaiKiaAPIError: Error, Codable {
    public let message: String, code: Int?
    public let apiName: String?, errorType: ErrorType

    public enum ErrorType: String, Codable, Sendable {
        case general, invalidVehicleSession, invalidCredentials
        case serverError, invalidPin, concurrentRequest, failedRetryLogin
    }

    public init(message: String, code: Int? = nil, apiName: String? = nil, errorType: ErrorType = .general) {
        (self.message, self.code, self.apiName, self.errorType) = (message, code, apiName, errorType)
    }

    public static func logError(
        _ message: String,
        code: Int? = nil,
        apiName: String? = nil,
        errorType: ErrorType = .general,
    ) -> HyundaiKiaAPIError {
        let error = HyundaiKiaAPIError(message: message, code: code, apiName: apiName, errorType: errorType)
        print("❌ [HyundaiKiaAPIError] \(apiName ?? "Unknown"): \(message)")
        if let code { print("   Status Code: \(code)") }
        if errorType != .general { print("   Error Type: \(errorType.rawValue)") }
        return error
    }

    public static func invalidVehicleSession(
        _ message: String = "Invalid vehicle for current session",
        apiName: String? = nil,
    ) -> HyundaiKiaAPIError {
        logError(message, code: 1005, apiName: apiName, errorType: .invalidVehicleSession)
    }

    public static func invalidCredentials(
        _ message: String = "Invalid username or password",
        apiName: String? = nil,
    ) -> HyundaiKiaAPIError {
        logError(message, code: 401, apiName: apiName, errorType: .invalidCredentials)
    }

    public static func serverError(
        _ message: String = "Server temporarily unavailable",
        apiName: String? = nil,
    ) -> HyundaiKiaAPIError {
        logError(message, code: 502, apiName: apiName, errorType: .serverError)
    }

    public static func invalidPin(_ message: String, apiName: String? = nil) -> HyundaiKiaAPIError {
        logError(message, apiName: apiName, errorType: .invalidPin)
    }

    public static func concurrentRequest(
        _ message: String = "Another request is already in progress. Please wait and try again.",
        apiName: String? = nil,
    ) -> HyundaiKiaAPIError {
        logError(message, code: 502, apiName: apiName, errorType: .concurrentRequest)
    }

    public static func failedRetryLogin(
        _ message: String = "Failed to reauthenticate",
        apiName: String? = nil,
    ) -> HyundaiKiaAPIError {
        logError(message, code: 502, apiName: apiName, errorType: .failedRetryLogin)
    }
}
