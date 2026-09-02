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

    /// `session` overrides the client's URLSession for this one request —
    /// the EU CCI signin uses a redirect-blocking session so the 302's
    /// Location (which carries the auth code) can be read instead of chased.
    func performLoggedRequest(
        _ request: URLRequest,
        requestType: HTTPRequestType,
        vin: String? = nil,
        session: URLSession? = nil
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
            let (data, response) = try await (session ?? urlSession).data(for: request)
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
        let rawURL = logData.request.url?.absoluteString ?? "Unknown URL"
        // Request URLs can carry credentials too (e.g. the EU CCI token
        // exchange's `?code=…`), so they go through the same redaction as
        // bodies.
        let url = configuration.redactPII
            ? (SensitiveDataRedactor.redact(rawURL) ?? rawURL)
            : rawURL
        let stackTrace = captureStackTrace()

        // Apply redaction unless disabled
        let requestHeaders: [String: String]
        let requestBody: String?
        let responseHeaders: [String: String]
        let responseBody: String?

        // Oversized values go first, and regardless of the redaction
        // setting: a surround-view response is megabytes of base64 JPEG,
        // which would bloat the persisted log (and every debug export)
        // and drag the redaction regexes across the whole payload.
        let sizedRequestBody = SensitiveDataRedactor.elideOversizedValues(logData.requestBody)
        let sizedResponseBody = SensitiveDataRedactor.elideOversizedValues(logData.responseBody)

        if configuration.redactPII {
            requestHeaders = redactSensitiveHeaders(logData.requestHeaders)
            requestBody = redactSensitiveData(in: sizedRequestBody)
            responseHeaders = redactSensitiveHeaders(logData.responseHeaders)
            responseBody = redactSensitiveData(in: sizedResponseBody)
        } else {
            requestHeaders = logData.requestHeaders
            requestBody = sizedRequestBody
            responseHeaders = logData.responseHeaders
            responseBody = sizedResponseBody
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

    func createErrorLogData(context: RequestContext, error: String) -> HTTPRequestLogData {
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
