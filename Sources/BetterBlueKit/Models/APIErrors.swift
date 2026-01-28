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
        case requiresMFA, kiaInvalidRequest
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
        var logMessage = "\(apiName ?? "Unknown"): \(message)"
        if let code { logMessage += " | Status Code: \(code)" }
        if errorType != .general { logMessage += " | Error Type: \(errorType.rawValue)" }
        if let userInfo { logMessage += " | User Info: \(userInfo)" }
        BBLogger.error(.api, logMessage)
        return error
    }

    public static func requiresMFA(
        xid: String,
        otpKey: String? = nil,
        hasEmail: Bool = false,
        hasPhone: Bool = false,
        email: String? = nil,
        phone: String? = nil,
        rmTokenExpired: Bool = false,
        apiName: String? = nil
    ) -> APIError {
        var info = ["xid": xid]
        if let otpKey {
            info["otpKey"] = otpKey
        }
        info["hasEmail"] = hasEmail ? "true" : "false"
        info["hasPhone"] = hasPhone ? "true" : "false"
        if let email {
            info["email"] = email
        }
        if let phone {
            info["phone"] = phone
        }
        if rmTokenExpired {
            info["rmTokenExpired"] = "true"
        }

        let message = rmTokenExpired
            ? "Session expired - verification required"
            : "Multi-Factor Authentication Required"

        return logError(
            message,
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

    public static func kiaInvalidRequest(
        _ message: String = "Invalid request",
        apiName: String? = nil,
    ) -> APIError {
        logError(message, code: 502, apiName: apiName, errorType: .kiaInvalidRequest)
    }
}
