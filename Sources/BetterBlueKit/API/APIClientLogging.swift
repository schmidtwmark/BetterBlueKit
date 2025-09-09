//
//  APIClientLogging.swift
//  BetterBlueKit
//
//  HTTP Logging extensions for APIClient
//

import Foundation

// MARK: - HTTP Logging Extensions

extension APIClient {
    struct HTTPRequestLogData {
        let requestType: HTTPRequestType
        let request: URLRequest
        let requestHeaders: [String: String]
        let requestBody: String?
        let responseStatus: Int?
        let responseHeaders: [String: String]
        let responseBody: String?
        let error: String?
        let apiError: String?
        let startTime: Date
    }

    func logHTTPRequest(_ logData: HTTPRequestLogData) {
        let duration = Date().timeIntervalSince(logData.startTime)
        let method = logData.request.httpMethod ?? "GET"
        let url = logData.request.url?.absoluteString ?? "Unknown URL"

        // Capture stack trace for debugging
        let stackTrace = captureStackTrace()

        // Redact sensitive data before logging
        let safeRequestHeaders = redactSensitiveHeaders(logData.requestHeaders)
        let safeRequestBody = redactSensitiveData(in: logData.requestBody)
        let safeResponseHeaders = redactSensitiveHeaders(logData.responseHeaders)
        let safeResponseBody = redactSensitiveData(in: logData.responseBody)

        let httpLog = HTTPLog(
            timestamp: logData.startTime,
            accountId: accountId,
            requestType: logData.requestType,
            method: method,
            url: url,
            requestHeaders: safeRequestHeaders,
            requestBody: safeRequestBody,
            responseStatus: logData.responseStatus,
            responseHeaders: safeResponseHeaders,
            responseBody: safeResponseBody,
            error: logData.error,
            apiError: logData.apiError,
            duration: duration,
            stackTrace: stackTrace,
        )

        logSink?(httpLog)
    }

    func extractAPIError(from data: Data?) -> String? {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        // Check for Kia/Hyundai API error patterns
        if let status = json["status"] as? [String: Any],
           let errorCode = status["errorCode"] as? Int,
           errorCode != 0,
           let errorMessage = status["errorMessage"] as? String {
            return "API Error \(errorCode): \(errorMessage)"
        }

        // Check for 401 error patterns that require re-initialization
        if let errorCode = json["errorCode"] as? Int {
            if errorCode == 401 {
                let errorMessage = json["errorMessage"] as? String ?? "Authentication error"
                return "API Error \(errorCode): \(errorMessage)"
            } else if errorCode == 502 {
                let errorMessage = json["errorMessage"] as? String ?? "Server error"
                return "API Error \(errorCode): \(errorMessage)"
            }
        }

        // Check for other common API error patterns
        if let error = json["error"] as? String {
            return "API Error: \(error)"
        }

        if let message = json["message"] as? String,
           json["success"] as? Bool == false {
            return "API Error: \(message)"
        }

        return nil
    }
}
