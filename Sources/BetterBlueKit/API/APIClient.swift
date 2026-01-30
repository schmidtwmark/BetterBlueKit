//
//  APIClient.swift
//  BetterBlueKit
//
//  Base API Client for Hyundai/Kia Integration
//

import Foundation
import Observation
import SwiftData

// MARK: - API Client Configuration

public struct APIClientConfiguration {
    public let region: Region
    public let brand: Brand
    public let username: String
    public let password: String
    public let pin: String
    public let accountId: UUID
    public let logSink: HTTPLogSink?
    public let rememberMeToken: String?

    public init(
        region: Region,
        brand: Brand,
        username: String,
        password: String,
        pin: String,
        accountId: UUID,
        logSink: HTTPLogSink? = nil,
        rememberMeToken: String? = nil
    ) {
        self.region = region
        self.brand = brand
        self.username = username
        self.password = password
        self.pin = pin
        self.accountId = accountId
        self.logSink = logSink
        self.rememberMeToken = rememberMeToken
    }
}

// Protocol for communicating with Kia/Hyundai API
@MainActor
public protocol APIClientProtocol {
    func login() async throws -> AuthToken
    func fetchVehicles(authToken: AuthToken) async throws -> [Vehicle]
    func fetchVehicleStatus(for vehicle: Vehicle, authToken: AuthToken) async throws -> VehicleStatus
    func sendCommand(for vehicle: Vehicle, command: VehicleCommand, authToken: AuthToken) async throws

    /// Optional: Fetch EV trip details for a vehicle (not all brands/APIs support this)
    func fetchEVTripDetails(for vehicle: Vehicle, authToken: AuthToken) async throws -> [EVTripDetail]?

    // MARK: - MFA Support (Optional)

    /// Returns true if this API client supports MFA (Multi-Factor Authentication)
    func supportsMFA() -> Bool

    /// Send OTP code via the specified method (SMS or email)
    func sendMFACode(otpKey: String, xid: String, notifyType: String) async throws

    /// Verify the OTP code and get tokens for completing login
    func verifyMFACode(otpKey: String, xid: String, otp: String) async throws -> (rememberMeToken: String, sid: String)

    /// Complete login after MFA verification
    func completeMFALogin(sid: String, rmToken: String) async throws -> AuthToken
}

// Default implementation for optional methods
extension APIClientProtocol {
    public func fetchEVTripDetails(for vehicle: Vehicle, authToken: AuthToken) async throws -> [EVTripDetail]? {
        // Default implementation returns nil (not supported)
        return nil
    }

    public func supportsMFA() -> Bool {
        false
    }

    public func sendMFACode(otpKey: String, xid: String, notifyType: String) async throws {
        throw APIError(message: "MFA not supported for this API", apiName: "APIClient")
    }

    public func verifyMFACode(otpKey: String, xid: String, otp: String) async throws ->
       (rememberMeToken: String, sid: String) {
        throw APIError(message: "MFA not supported for this API", apiName: "APIClient")
    }

    public func completeMFALogin(sid: String, rmToken: String) async throws -> AuthToken {
        throw APIError(message: "MFA not supported for this API", apiName: "APIClient")
    }
}

// MARK: - API Endpoint Protocol

public enum HTTPMethod: String, Sendable {
    case GET
    case POST
    case PUT
    case DELETE
}

public struct APIEndpoint: Sendable {
    public let url: String
    public let method: HTTPMethod
    public let headers: [String: String]
    public let body: Data?

    public init(url: String, method: HTTPMethod, headers: [String: String] = [:], body: Data? = nil) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

@MainActor
public protocol APIEndpointProvider: Sendable {
    func loginEndpoint() -> APIEndpoint
    func fetchVehiclesEndpoint(authToken: AuthToken) -> APIEndpoint
    func fetchVehicleStatusEndpoint(
        for vehicle: Vehicle,
        authToken: AuthToken,
    ) -> APIEndpoint
    func sendCommandEndpoint(
        for vehicle: Vehicle,
        command: VehicleCommand,
        authToken: AuthToken,
    ) -> APIEndpoint

    // Command body generation
    func getBodyForCommand(command: VehicleCommand, vehicle: Vehicle) -> [String: Any]

    // Response parsing methods
    func parseLoginResponse(_ data: Data, headers: [String: String]) throws -> AuthToken
    func parseVehiclesResponse(_ data: Data) throws -> [Vehicle]
    func parseVehicleStatusResponse(
        _ data: Data,
        for vehicle: Vehicle,
    ) throws -> VehicleStatus
    func parseCommandResponse(_ data: Data) throws // Commands typically don't return data

    // Optional: EV Trip Details (not all providers support this)
    func supportsEVTripDetails() -> Bool
    func evTripDetailsEndpoint(for vehicle: Vehicle, authToken: AuthToken) -> APIEndpoint
    func parseEVTripDetailsResponse(_ data: Data) throws -> [EVTripDetail]

    // Optional: MFA Support (not all providers support this)
    func supportsMFA() -> Bool
    func loginEndpoint(sid: String?, rmToken: String?) -> APIEndpoint
    func sendOTPEndpoint(otpKey: String, xid: String, notifyType: String) -> APIEndpoint
    func verifyOTPEndpoint(otpKey: String, xid: String, otp: String) -> APIEndpoint
    func parseVerifyOTPResponse(_ data: Data, headers: [String: String]) throws ->
        (rememberMeToken: String, sid: String)
}

// Default implementations for optional APIEndpointProvider methods
extension APIEndpointProvider {
    public func supportsEVTripDetails() -> Bool { false }
    public func evTripDetailsEndpoint(for vehicle: Vehicle, authToken: AuthToken) -> APIEndpoint {
        fatalError("evTripDetailsEndpoint not implemented")
    }
    public func parseEVTripDetailsResponse(_ data: Data) throws -> [EVTripDetail] {
        fatalError("parseEVTripDetailsResponse not implemented")
    }

    public func supportsMFA() -> Bool { false }
    public func loginEndpoint(sid: String?, rmToken: String?) -> APIEndpoint {
        fatalError("MFA login endpoint not implemented")
    }
    public func sendOTPEndpoint(otpKey: String, xid: String, notifyType: String) -> APIEndpoint {
        fatalError("sendOTPEndpoint not implemented")
    }
    public func verifyOTPEndpoint(otpKey: String, xid: String, otp: String) -> APIEndpoint {
        fatalError("verifyOTPEndpoint not implemented")
    }
    public func parseVerifyOTPResponse(_ data: Data, headers: [String: String]) throws ->
        (rememberMeToken: String, sid: String) {
        fatalError("parseVerifyOTPResponse not implemented")
    }
}

// MARK: - Generic API Client

@MainActor
public class APIClient<Provider: APIEndpointProvider> {
    let brand: Brand
    let username: String
    let password: String
    let pin: String
    let accountId: UUID

    let endpointProvider: Provider
    let logSink: HTTPLogSink?
    let urlSession: URLSession

    public init(
        configuration: APIClientConfiguration,
        endpointProvider: Provider,
        urlSession: URLSession = .shared
    ) {
        brand = configuration.brand
        username = configuration.username
        password = configuration.password
        pin = configuration.pin
        accountId = configuration.accountId
        self.endpointProvider = endpointProvider
        logSink = configuration.logSink
        self.urlSession = urlSession
    }

    // MARK: - Private Helper Methods

    func createRequest(from endpoint: APIEndpoint) throws -> URLRequest {
        guard let url = URL(string: endpoint.url) else {
            throw APIError(
                message: "Invalid URL: \(endpoint.url)",
                apiName: "APIClient",
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body

        // Set headers
        for (key, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Set default headers if not already set
        if request.value(forHTTPHeaderField: "Content-Type") == nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    func performLoggedRequest(
        _ request: URLRequest,
        requestType: HTTPRequestType,
    ) async throws -> (Data, HTTPURLResponse) {
        let startTime = Date()
        let requestHeaders = request.allHTTPHeaderFields ?? [:]
        let requestBody = request.httpBody.flatMap { String(data: $0, encoding: .utf8) }

        // Detailed request logging for debugging
        var requestLog = "Sending \(requestType.displayName) request"
        requestLog += " | URL: \(request.url?.absoluteString ?? "unknown")"
        requestLog += " | Method: \(request.httpMethod ?? "unknown")"
        requestLog += " | Headers: \(requestHeaders)"
        if let body = requestBody {
            requestLog += " | Body: \(body)"
        }
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
            try handleNetworkError(error, context: context)
            fatalError("handleNetworkError should throw")
        }
    }

    private func handleSuccessfulRequest(
        data: Data, response: URLResponse, context: RequestContext) throws -> (Data, HTTPURLResponse) {
        guard let httpResponse = response as? HTTPURLResponse else {
            try handleInvalidResponse(
                requestType: context.requestType,
                request: context.request,
                requestHeaders: context.requestHeaders,
                requestBody: context.requestBody,
                startTime: context.startTime
            )
            fatalError("handleInvalidResponse should throw")
        }

        let responseHeaders = extractResponseHeaders(from: httpResponse)
        let responseBody = String(data: data, encoding: .utf8)
        let apiError = extractAPIError(from: data)

        var responseLog = "Received response for \(context.requestType.displayName)"
        responseLog += " | Status Code: \(httpResponse.statusCode)"
        responseLog += " | Headers: \(responseHeaders)"
        if let responseBody {
            responseLog += " | Body: \(responseBody)"
        }
        BBLogger.debug(.api, responseLog)

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

    func extractResponseHeaders(from httpResponse: HTTPURLResponse) -> [String: String] {
        httpResponse.allHeaderFields.reduce(into: [:]) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String {
                result[key] = value
            }
        }
    }

    struct RequestContext {
        let requestType: HTTPRequestType
        let request: URLRequest
        let requestHeaders: [String: String]
        let requestBody: String?
        let startTime: Date
    }
}

// Extend the generic APIClient to conform to the protocol
extension APIClient: APIClientProtocol {}

func extractNumber<T: LosslessStringConvertible>(from value: Any?) -> T? {
    guard let value = value else {
        return nil
    }
    if let num = value as? T {
        return num
    }
    if let numString = value as? String {
        return T(numString)
    }
    return nil
}
