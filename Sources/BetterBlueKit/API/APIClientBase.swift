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
    public var configuration: APIClientConfiguration
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

    // MARK: - default so set deviceId in configuration
    public func registerDevice() async throws -> String? {
        // Generate a stable device ID for Kia accounts so the rmToken stays valid
        // across API client re-initializations
        let deviceId = UUID().uuidString.uppercased()
        configuration = configuration.with(deviceId: deviceId)
        return deviceId
    }

    // MARK: - HTTP Request Execution

    /// Performs an HTTP request with logging and error handling
    public func performRequest(
        url: String,
        method: HTTPMethod = .GET,
        headers: [String: String] = [:],
        body: Data? = nil,
        requestType: HTTPRequestType,
        vin: String? = nil
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

        return try await performLoggedRequest(request, requestType: requestType, vin: vin)
    }

    /// Performs an HTTP request and returns parsed JSON
    public func performJSONRequest(
        url: String,
        method: HTTPMethod = .GET,
        headers: [String: String] = [:],
        body: [String: Any]? = nil,
        requestType: HTTPRequestType,
        vin: String? = nil
    ) async throws -> (Data, [String: Any], HTTPURLResponse) { // swiftlint:disable:this large_tuple
        let bodyData = body.flatMap { try? JSONSerialization.data(withJSONObject: $0) }

        let (data, response) = try await performRequest(
            url: url,
            method: method,
            headers: headers,
            body: bodyData,
            requestType: requestType,
            vin: vin
        )

        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return (data, json, response)
    }

    // MARK: - Internal Request Handling

    func performLoggedRequest(
        _ request: URLRequest,
        requestType: HTTPRequestType,
        vin: String? = nil
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
            startTime: startTime,
            vin: vin
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
            startTime: context.startTime,
            vin: context.vin
        ))

        try validateHTTPResponse(httpResponse, data: data, responseBody: responseBody)

        return (data, httpResponse)
    }

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

    // MARK: - Logging Helpers

    struct RequestContext {
        let requestType: HTTPRequestType
        let request: URLRequest
        let requestHeaders: [String: String]
        let requestBody: String?
        let startTime: Date
        let vin: String?
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
        let vin: String?
    }

    func logHTTPRequest(_ logData: HTTPRequestLogData) {
        let duration = Date().timeIntervalSince(logData.startTime)
        let method = logData.request.httpMethod ?? "GET"
        let url = logData.request.url?.absoluteString ?? "Unknown URL"
        let stackTrace = captureStackTrace()

        // Apply redaction unless disabled
        let requestHeaders: [String: String]
        let requestBody: String?
        let responseHeaders: [String: String]
        let responseBody: String?

        if configuration.redactPII {
            requestHeaders = redactSensitiveHeaders(logData.requestHeaders)
            requestBody = redactSensitiveData(in: logData.requestBody)
            responseHeaders = redactSensitiveHeaders(logData.responseHeaders)
            responseBody = redactSensitiveData(in: logData.responseBody)
        } else {
            requestHeaders = logData.requestHeaders
            requestBody = logData.requestBody
            responseHeaders = logData.responseHeaders
            responseBody = logData.responseBody
        }

        let httpLog = HTTPLog(
            timestamp: logData.startTime,
            accountId: accountId,
            requestType: logData.requestType,
            method: method,
            url: url,
            requestHeaders: requestHeaders,
            requestBody: requestBody,
            responseStatus: logData.responseStatus,
            responseHeaders: responseHeaders,
            responseBody: responseBody,
            error: logData.error,
            apiError: logData.apiError,
            duration: duration,
            stackTrace: stackTrace,
            vin: logData.vin
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
            startTime: context.startTime,
            vin: context.vin
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

// MARK: - Redaction Helpers

extension APIClientBase {
    func redactSensitiveHeaders(_ headers: [String: String]) -> [String: String] {
        SensitiveDataRedactor.redactHeaders(headers)
    }

    func redactSensitiveData(in body: String?) -> String? {
        SensitiveDataRedactor.redact(body)
    }

    func captureStackTrace() -> String {
        Thread.callStackSymbols.prefix(10).joined(separator: "\n")
    }
}
