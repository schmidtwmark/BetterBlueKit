//
//  APIClientErrorHandling.swift
//  BetterBlueKit
//
//  Error handling utilities for APIClient
//

import Foundation

// MARK: - Error Handling Extensions

extension APIClient {
    func shouldRetryWithReinitialization(
        data: Data?,
        httpStatusCode: Int,
    ) -> Bool {
        // Only retry for 401 (authentication) errors, not 502 (server) errors
        if httpStatusCode == 401 {
            return true
        }

        // Check for API-level 401 error codes in response body
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return false
        }

        if let errorCode = json["errorCode"] as? Int {
            return errorCode == 401
        }

        return false
    }

    func handleInvalidResponse(
        requestType: HTTPRequestType,
        request: URLRequest,
        requestHeaders: [String: String],
        requestBody: String?,
        startTime: Date,
    ) throws {
        let logData = createInvalidResponseLogData(
            requestType: requestType,
            request: request,
            requestHeaders: requestHeaders,
            requestBody: requestBody,
            startTime: startTime,
        )

        logHTTPRequest(logData)

        throw HyundaiKiaAPIError(
            message: "Invalid response type",
            apiName: "APIClient",
        )
    }

    private func createInvalidResponseLogData(
        requestType: HTTPRequestType,
        request: URLRequest,
        requestHeaders: [String: String],
        requestBody: String?,
        startTime: Date,
    ) -> HTTPRequestLogData {
        HTTPRequestLogData(
            requestType: requestType,
            request: request,
            requestHeaders: requestHeaders,
            requestBody: requestBody,
            responseStatus: nil,
            responseHeaders: [:],
            responseBody: nil,
            error: "Invalid response type",
            apiError: nil,
            startTime: startTime,
        )
    }

    func validateHTTPResponse(
        _ httpResponse: HTTPURLResponse,
        data: Data,
        responseBody: String?,
    ) throws {
        // Check if this is a 401 error that requires re-initialization
        if shouldRetryWithReinitialization(
            data: data,
            httpStatusCode: httpResponse.statusCode,
        ) {
            let errorMessage = "Authentication expired (\(httpResponse.statusCode)): " +
                "\(responseBody ?? "Unknown error")"
            throw HyundaiKiaAPIError(
                message: errorMessage,
                code: httpResponse.statusCode,
                apiName: "APIClient",
                errorType: .invalidCredentials,
            )
        }

        // Handle 502 errors as server errors (don't retry)
        if httpResponse.statusCode == 502 {
            let errorMessage = "Server error (502): " +
                "\(responseBody ?? "Unknown error")"
            throw HyundaiKiaAPIError(
                message: errorMessage,
                code: httpResponse.statusCode,
                apiName: "APIClient",
                errorType: .serverError,
            )
        }

        // Check for HTTP errors
        if httpResponse.statusCode >= 400 {
            let errorMessage = "HTTP \(httpResponse.statusCode): " +
                "\(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))"
            throw HyundaiKiaAPIError(
                message: errorMessage,
                apiName: "APIClient",
            )
        }
    }

    func handleNetworkError(
        _ error: Error,
        context: RequestContext,
    ) throws {
        let logData = HTTPRequestLogData(
            requestType: context.requestType,
            request: context.request,
            requestHeaders: context.requestHeaders,
            requestBody: context.requestBody,
            responseStatus: nil,
            responseHeaders: [:],
            responseBody: nil,
            error: error.localizedDescription,
            apiError: nil,
            startTime: context.startTime,
        )

        logHTTPRequest(logData)

        throw HyundaiKiaAPIError(
            message: "Network error: \(error.localizedDescription)",
            apiName: "APIClient",
        )
    }
}
