//
//  APIClientBase.swift
//  BetterBlueKit
//
//  Base class providing shared HTTP request functionality for API clients
//

import Foundation

// MARK: - API Client Base

/// Base class for API clients providing shared HTTP request execution, logging, and error handling.
/// Subclasses implement `APIClientProtocol` methods directly for their specific region/brand.
@MainActor
open class APIClientBase {
    public let configuration: APIClientConfiguration
    public let urlSession: URLSession

    // Convenience accessors
    public var username: String { configuration.username }
    public var password: String { configuration.password }
    public var pin: String { configuration.pin }
    public var accountId: UUID { configuration.accountId }
    public var region: Region { configuration.region }
    public var brand: Brand { configuration.brand }
    public var logSink: HTTPLogSink? { configuration.logSink }

    public init(configuration: APIClientConfiguration, urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.urlSession = urlSession
    }

    // MARK: - HTTP Request Execution

    /// Performs an HTTP request with logging and error handling
    public func performRequest(
        url: String,
        method: HTTPMethod = .GET,
        headers: [String: String] = [:],
        body: Data? = nil,
        requestType: HTTPRequestType
    ) async throws -> (Data, HTTPURLResponse) {
        guard let requestUrl = URL(string: url) else {
            throw APIError(message: "Invalid URL: \(url)", apiName: apiName)
        }

        var request = URLRequest(url: requestUrl)
        request.httpMethod = method.rawValue
        request.httpBody = body

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if request.value(forHTTPHeaderField: "Content-Type") == nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return try await performLoggedRequest(request, requestType: requestType)
    }

    /// Performs an HTTP request and returns parsed JSON
    public func performJSONRequest(
        url: String,
        method: HTTPMethod = .GET,
        headers: [String: String] = [:],
        body: [String: Any]? = nil,
        requestType: HTTPRequestType
    ) async throws -> (Data, [String: Any], HTTPURLResponse) { // swiftlint:disable:this large_tuple
        let bodyData = body.flatMap { try? JSONSerialization.data(withJSONObject: $0) }

        let (data, response) = try await performRequest(
            url: url,
            method: method,
            headers: headers,
            body: bodyData,
            requestType: requestType
        )

        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return (data, json, response)
    }

    // MARK: - Internal Request Handling

    func performLoggedRequest(
        _ request: URLRequest,
        requestType: HTTPRequestType
    ) async throws -> (Data, HTTPURLResponse) {
        let startTime = Date()
        let requestHeaders = request.allHTTPHeaderFields ?? [:]
        let requestBody = request.httpBody.flatMap { String(data: $0, encoding: .utf8) }

        // Debug logging
        var requestLog = "[\(apiName)] Sending \(requestType.displayName) request"
        requestLog += " | URL: \(request.url?.absoluteString ?? "unknown")"
        requestLog += " | Method: \(request.httpMethod ?? "unknown")"
        BBLogger.debug(.api, requestLog)

        let context = RequestContext(
            requestType: requestType,
            request: request,
            requestHeaders: requestHeaders,
            requestBody: requestBody,
            startTime: startTime
        )

        do {
            let (data, response) = try await urlSession.data(for: request)
            return try handleSuccessfulRequest(data: data, response: response, context: context)
        } catch let error as APIError {
            throw error
        } catch {
            throw handleNetworkError(error, context: context)
        }
    }

    private func handleSuccessfulRequest(
        data: Data,
        response: URLResponse,
        context: RequestContext
    ) throws -> (Data, HTTPURLResponse) {
        guard let httpResponse = response as? HTTPURLResponse else {
            logHTTPRequest(createErrorLogData(context: context, error: "Invalid response type"))
            throw APIError(message: "Invalid response type", apiName: apiName)
        }

        let responseHeaders = extractResponseHeaders(from: httpResponse)
        let responseBody = String(data: data, encoding: .utf8)
        let apiError = extractAPIError(from: data)

        BBLogger.debug(.api, "[\(apiName)] Response \(httpResponse.statusCode) for \(context.requestType.displayName)")

        logHTTPRequest(HTTPRequestLogData(
            requestType: context.requestType,
            request: context.request,
            requestHeaders: context.requestHeaders,
            requestBody: context.requestBody,
            responseStatus: httpResponse.statusCode,
            responseHeaders: responseHeaders,
            responseBody: responseBody,
            error: nil,
            apiError: apiError,
            startTime: context.startTime
        ))

        try validateHTTPResponse(httpResponse, data: data, responseBody: responseBody)

        return (data, httpResponse)
    }

    // MARK: - Error Handling

    func validateHTTPResponse(_ httpResponse: HTTPURLResponse, data: Data, responseBody: String?) throws {
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

    func handleNetworkError(_ error: Error, context: RequestContext) -> APIError {
        logHTTPRequest(createErrorLogData(context: context, error: error.localizedDescription))
        return APIError(message: "Network error: \(error.localizedDescription)", apiName: apiName)
    }

    // MARK: - Logging Helpers

    struct RequestContext {
        let requestType: HTTPRequestType
        let request: URLRequest
        let requestHeaders: [String: String]
        let requestBody: String?
        let startTime: Date
    }

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
        let stackTrace = captureStackTrace()

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
            stackTrace: stackTrace
        )

        logSink?(httpLog)
    }

    private func createErrorLogData(context: RequestContext, error: String) -> HTTPRequestLogData {
        HTTPRequestLogData(
            requestType: context.requestType,
            request: context.request,
            requestHeaders: context.requestHeaders,
            requestBody: context.requestBody,
            responseStatus: nil,
            responseHeaders: [:],
            responseBody: nil,
            error: error,
            apiError: nil,
            startTime: context.startTime
        )
    }

    func extractResponseHeaders(from httpResponse: HTTPURLResponse) -> [String: String] {
        httpResponse.allHeaderFields.reduce(into: [:]) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String {
                result[key] = value
            }
        }
    }

    func extractAPIError(from data: Data?) -> String? {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let status = json["status"] as? [String: Any],
           let errorCode = status["errorCode"] as? Int,
           errorCode != 0,
           let errorMessage = status["errorMessage"] as? String {
            return "API Error \(errorCode): \(errorMessage)"
        }

        if let errorCode = json["errorCode"] as? Int, errorCode != 0 {
            let errorMessage = json["errorMessage"] as? String ?? "Unknown error"
            return "API Error \(errorCode): \(errorMessage)"
        }

        if let error = json["error"] as? String {
            return "API Error: \(error)"
        }

        return nil
    }

    // MARK: - API Name (Override in subclass)

    open var apiName: String { "APIClient" }
}

// MARK: - Redaction Helpers (moved from extension)

extension APIClientBase {
    func redactSensitiveHeaders(_ headers: [String: String]) -> [String: String] {
        let sensitiveKeys = [
            "authorization",
            "accesstoken",
            "access_token",
            "cookie",
            "set-cookie",
            "bluelinkservicepin",
            "password",
            "pin",
            "clientsecret",
            "client_secret",
            "pauth",
            "transactionid"
        ]
        return headers.reduce(into: [:]) { result, pair in
            let key = pair.key.lowercased()
            result[pair.key] = sensitiveKeys.contains(key) ? "[REDACTED]" : pair.value
        }
    }

    func redactSensitiveData(in body: String?) -> String? {
        guard let body else { return nil }
        var redacted = body
        let patterns = [
            (#""password"\s*:\s*"[^"]*""#, #""password":"[REDACTED]""#),
            (#""pin"\s*:\s*"[^"]*""#, #""pin":"[REDACTED]""#),
            (#""access_token"\s*:\s*"[^"]*""#, #""access_token":"[REDACTED]""#),
            (#""refresh_token"\s*:\s*"[^"]*""#, #""refresh_token":"[REDACTED]""#),
            (#""accessToken"\s*:\s*"[^"]*""#, #""accessToken":"[REDACTED]""#),
            (#""refreshToken"\s*:\s*"[^"]*""#, #""refreshToken":"[REDACTED]""#)
        ]
        for (pattern, replacement) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                redacted = regex.stringByReplacingMatches(
                    in: redacted, range: NSRange(redacted.startIndex..., in: redacted), withTemplate: replacement
                )
            }
        }
        return redacted
    }

    func captureStackTrace() -> String {
        Thread.callStackSymbols.prefix(10).joined(separator: "\n")
    }
}
