//
//  APIClientLoggingTests.swift
//  BetterBlueKit
//
//  Unit tests for APIClientLogging
//

import Foundation
import Testing
@testable import BetterBlueKit

@Suite("APIClientLogging Tests")
@MainActor
struct APIClientLoggingTests {
    struct DummyProvider: APIEndpointProvider {
        func loginEndpoint() -> APIEndpoint {
            APIEndpoint(url: "https://example.com/login", method: .POST)
        }
        func fetchVehiclesEndpoint(authToken: AuthToken) -> APIEndpoint {
            APIEndpoint(url: "https://example.com/vehicles", method: .GET)
        }
        func fetchVehicleStatusEndpoint(for vehicle: Vehicle, authToken: AuthToken) -> APIEndpoint {
            APIEndpoint(url: "https://example.com/vehicleStatus", method: .GET)
        }
        func sendCommandEndpoint(for vehicle: Vehicle, command: VehicleCommand, authToken: AuthToken) -> APIEndpoint {
            APIEndpoint(url: "https://example.com/sendCommand", method: .POST)
        }
        func parseLoginResponse(_ data: Data, headers: [String: String]) throws -> AuthToken {
            AuthToken(accessToken: "token", refreshToken: "refresh", expiresAt: Date().addingTimeInterval(3600), pin: "1234")
        }
        func parseVehiclesResponse(_ data: Data) throws -> [Vehicle] { [] }
        func parseVehicleStatusResponse(_ data: Data, for vehicle: Vehicle) throws -> VehicleStatus { throw NSError(domain: "", code: 0) }
        func parseCommandResponse(_ data: Data) throws {}
    }

    class DummyAPIClient: APIClient<DummyProvider> {
        init(logSink: HTTPLogSink? = nil) {
            let config = APIClientConfiguration(
                region: .usa,
                brand: .kia,
                username: "testuser",
                password: "testpass",
                pin: "1234",
                accountId: UUID(),
                logSink: logSink
            )
            super.init(configuration: config, endpointProvider: DummyProvider())
        }
        override func login() async throws -> AuthToken { fatalError() }
        override func fetchVehicles(authToken: AuthToken) async throws -> [Vehicle] { fatalError() }
        override func fetchVehicleStatus(for vehicle: Vehicle, authToken: AuthToken) async throws -> VehicleStatus { fatalError() }
        override func sendCommand(for vehicle: Vehicle, command: VehicleCommand, authToken: AuthToken) async throws { fatalError() }
    }

    @Test("extractAPIError returns nil for nil data")
    func testExtractAPIErrorNil() {
        let client = DummyAPIClient()
        let result = client.extractAPIError(from: nil)
        #expect(result == nil)
    }

    @Test("extractAPIError returns nil for non-JSON data")
    func testExtractAPIErrorNonJSON() {
        let client = DummyAPIClient()
        let data = "not json".data(using: .utf8)!
        let result = client.extractAPIError(from: data)
        #expect(result == nil)
    }

    @Test("extractAPIError handles status error pattern")
    func testExtractAPIErrorStatusPattern() {
        let client = DummyAPIClient()
        let json: [String: Any] = [
            "status": ["errorCode": 123, "errorMessage": "Something went wrong"]
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let result = client.extractAPIError(from: data)
        #expect(result?.contains("API Error 123") == true)
        #expect(result?.contains("Something went wrong") == true)
    }

    @Test("extractAPIError handles errorCode 401 pattern")
    func testExtractAPIError401() {
        let client = DummyAPIClient()
        let json: [String: Any] = ["errorCode": 401, "errorMessage": "Auth fail"]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let result = client.extractAPIError(from: data)
        #expect(result?.contains("API Error 401") == true)
        #expect(result?.contains("Auth fail") == true)
    }

    @Test("extractAPIError handles errorCode 502 pattern")
    func testExtractAPIError502() {
        let client = DummyAPIClient()
        let json: [String: Any] = ["errorCode": 502, "errorMessage": "Server fail"]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let result = client.extractAPIError(from: data)
        #expect(result?.contains("API Error 502") == true)
        #expect(result?.contains("Server fail") == true)
    }

    @Test("extractAPIError handles error string pattern")
    func testExtractAPIErrorString() {
        let client = DummyAPIClient()
        let json: [String: Any] = ["error": "Something bad"]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let result = client.extractAPIError(from: data)
        #expect(result?.contains("API Error: Something bad") == true)
    }

    @Test("extractAPIError handles message with success false pattern")
    func testExtractAPIErrorMessageSuccessFalse() {
        let client = DummyAPIClient()
        let json: [String: Any] = ["message": "Failed", "success": false]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let result = client.extractAPIError(from: data)
        #expect(result?.contains("API Error: Failed") == true)
    }

    @Test("logHTTPRequest logs with redaction and stack trace")
    func testLogHTTPRequest() async {
        actor LogFlag { var didLog = false; func set() { didLog = true } }
        let logFlag = LogFlag()
        let logSink: HTTPLogSink = { log in Task { await logFlag.set() } }
        let apiClient = DummyAPIClient(logSink: logSink)
        let logData = APIClient<DummyProvider>.HTTPRequestLogData(
            requestType: .login,
            request: {
                var req = URLRequest(url: URL(string: "https://example.com")!)
                req.httpMethod = "POST"
                return req
            }(),
            requestHeaders: ["Authorization": "Bearer token"],
            requestBody: "mysecret",
            responseStatus: 200,
            responseHeaders: ["Authorization": "Bearer token"],
            responseBody: "mysecret",
            error: "Test error",
            apiError: "Test API error",
            startTime: Date(timeIntervalSinceNow: -1)
        )
        apiClient.logHTTPRequest(logData)
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        let didLog = await logFlag.didLog
        #expect(didLog == true)
    }
}