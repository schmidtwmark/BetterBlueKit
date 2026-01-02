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
}

// MARK: - Generic API Client

@MainActor
public class APIClient<Provider: APIEndpointProvider> {
    let region: Region
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
        region = configuration.region
        brand = configuration.brand
        username = configuration.username
        password = configuration.password
        pin = configuration.pin
        accountId = configuration.accountId
        self.endpointProvider = endpointProvider
        logSink = configuration.logSink
        self.urlSession = urlSession
    }

    public func login() async throws -> AuthToken {
        let endpoint = endpointProvider.loginEndpoint()
        let request = try createRequest(from: endpoint)

        print("📤 [APIClient] Attempting login")
        let (data, response) = try await performLoggedRequest(request, requestType: .login)

        // Extract headers for parsing
        let headers: [String: String] = response.allHeaderFields.reduce(into: [:]) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String {
                result[key] = value
            }
        }

        return try endpointProvider.parseLoginResponse(data, headers: headers)
    }

    public func fetchVehicles(authToken: AuthToken) async throws -> [Vehicle] {
        let endpoint = endpointProvider.fetchVehiclesEndpoint(authToken: authToken)
        let request = try createRequest(from: endpoint)
        let (data, _) = try await performLoggedRequest(request, requestType: .fetchVehicles)
        return try endpointProvider.parseVehiclesResponse(data)
    }

    public func fetchVehicleStatus(
        for vehicle: Vehicle,
        authToken: AuthToken,
    ) async throws -> VehicleStatus {
        let endpoint = endpointProvider.fetchVehicleStatusEndpoint(
            for: vehicle,
            authToken: authToken,
        )
        let request = try createRequest(from: endpoint)
        let (data, _) = try await performLoggedRequest(request, requestType: .fetchVehicleStatus)
        return try endpointProvider.parseVehicleStatusResponse(data, for: vehicle)
    }

    public func sendCommand(
        for vehicle: Vehicle,
        command: VehicleCommand,
        authToken: AuthToken,
    ) async throws {
        let endpoint = endpointProvider.sendCommandEndpoint(
            for: vehicle,
            command: command,
            authToken: authToken,
        )
        let request = try createRequest(from: endpoint)
        let (data, _) = try await performLoggedRequest(request, requestType: .sendCommand)
        try endpointProvider.parseCommandResponse(data)
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
        print("🚀 [APIClient] Sending \(requestType.displayName) request to \(request.url?.absoluteString ?? "unknown")")
        let startTime = Date()
        let requestHeaders = request.allHTTPHeaderFields ?? [:]
        let requestBody = request.httpBody.flatMap { String(data: $0, encoding: .utf8) }

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                try handleInvalidResponse(
                    requestType: requestType,
                    request: request,
                    requestHeaders: requestHeaders,
                    requestBody: requestBody,
                    startTime: startTime,
                )
                fatalError("handleInvalidResponse should throw")
            }

            let responseHeaders = extractResponseHeaders(from: httpResponse)
            let responseBody = String(data: data, encoding: .utf8)
            let apiError = extractAPIError(from: data)

            print("📥 [APIClient] Received response for \(requestType.displayName)")
            print("   Status Code: \(httpResponse.statusCode)")
            print("   Headers: \(responseHeaders)")
            if let responseBody {
                print("   Body: \(responseBody)")
            }

            logHTTPRequest(HTTPRequestLogData(
                requestType: requestType,
                request: request,
                requestHeaders: requestHeaders,
                requestBody: requestBody,
                responseStatus: httpResponse.statusCode,
                responseHeaders: responseHeaders,
                responseBody: responseBody,
                error: nil,
                apiError: apiError,
                startTime: startTime,
            ))

            try validateHTTPResponse(httpResponse, data: data, responseBody: responseBody)

            return (data, httpResponse)

        } catch let error as APIError {
            throw error
        } catch {
            try handleNetworkError(
                error,
                context: RequestContext(
                    requestType: requestType,
                    request: request,
                    requestHeaders: requestHeaders,
                    requestBody: requestBody,
                    startTime: startTime,
                ),
            )
            fatalError("handleNetworkError should throw")
        }
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
