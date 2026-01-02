//
//  APIErrors.swift
//  BetterBlueKit
//
//  API error types and handling
//

import Foundation

// MARK: - Error Types

public struct APIError: Error, Codable {
    public let message: String, code: Int?
    public let apiName: String?, errorType: ErrorType
    public let userInfo: [String: String]?

    public enum ErrorType: String, Codable, Sendable {
        case general, invalidVehicleSession, invalidCredentials
        case serverError, invalidPin, concurrentRequest, failedRetryLogin
        case requiresMFA
    }

    public init(
        message: String,
        code: Int? = nil,
        apiName: String? = nil,
        errorType: ErrorType = .general,
        userInfo: [String: String]? = nil
    ) {
        (self.message, self.code, self.apiName, self.errorType, self.userInfo) =
            (message, code, apiName, errorType, userInfo)
    }

    public static func logError(
        _ message: String,
        code: Int? = nil,
        apiName: String? = nil,
        errorType: ErrorType = .general,
        userInfo: [String: String]? = nil
    ) -> APIError {
        let error = APIError(
            message: message,
            code: code,
            apiName: apiName,
            errorType: errorType,
            userInfo: userInfo
        )
        print("❌ [APIError] \(apiName ?? "Unknown"): \(message)")
        if let code { print("   Status Code: \(code)") }
        if errorType != .general { print("   Error Type: \(errorType.rawValue)") }
        if let userInfo { print("   User Info: \(userInfo as NSDictionary)")}
        return error
    }

    public static func requiresMFA(
        xid: String,
        otpKey: String? = nil,
        apiName: String? = nil
    ) -> APIError {
        var info = ["xid": xid]
        if let otpKey {
            info["otpKey"] = otpKey
        }
        return logError(
            "Multi-Factor Authentication Required",
            apiName: apiName,
            errorType: .requiresMFA,
            userInfo: info
        )
    }

    public static func invalidVehicleSession(
        _ message: String = "Invalid vehicle for current session",
        apiName: String? = nil,
    ) -> APIError {
        logError(message, code: 1005, apiName: apiName, errorType: .invalidVehicleSession)
    }

    public static func invalidCredentials(
        _ message: String = "Invalid username or password",
        apiName: String? = nil,
    ) -> APIError {
        logError(message, code: 401, apiName: apiName, errorType: .invalidCredentials)
    }

    public static func serverError(
        _ message: String = "Server temporarily unavailable",
        apiName: String? = nil,
    ) -> APIError {
        logError(message, code: 502, apiName: apiName, errorType: .serverError)
    }

    public static func invalidPin(_ message: String, apiName: String? = nil) -> APIError {
        logError(message, apiName: apiName, errorType: .invalidPin)
    }

    public static func concurrentRequest(
        _ message: String = "Another request is already in progress. Please wait and try again.",
        apiName: String? = nil,
    ) -> APIError {
        logError(message, code: 502, apiName: apiName, errorType: .concurrentRequest)
    }

    public static func failedRetryLogin(
        _ message: String = "Failed to reauthenticate",
        apiName: String? = nil,
    ) -> APIError {
        logError(message, code: 502, apiName: apiName, errorType: .failedRetryLogin)
    }
}
