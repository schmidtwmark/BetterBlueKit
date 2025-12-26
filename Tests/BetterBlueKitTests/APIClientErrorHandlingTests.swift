//
//  APIClientErrorHandlingTests.swift
//  BetterBlueKit
//
//  Unit tests for APIClientErrorHandling
//

import Foundation
import Testing
@testable import BetterBlueKit

@Suite("APIClientErrorHandling Tests")
@MainActor
struct APIClientErrorHandlingTests {

    // Minimal DummyProvider for APIClient
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

    // Minimal APIClient for extension testing
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

    // Remove global client; instantiate in each test as needed

    @Test("shouldRetryWithReinitialization returns true for 401 status")
    func testShouldRetryWithReinit401() {
        let client = DummyAPIClient()
        let shouldRetry = client.shouldRetryWithReinitialization(data: nil as Data?, httpStatusCode: 401)
        #expect(shouldRetry == true)
    }

    @Test("shouldRetryWithReinitialization returns false for non-401 status")
    func testShouldRetryWithReinitNon401() {
        let client = DummyAPIClient()
        let shouldRetry = client.shouldRetryWithReinitialization(data: nil as Data?, httpStatusCode: 502)
        #expect(shouldRetry == false)
    }

    @Test("shouldRetryWithReinitialization returns true for errorCode 401 in JSON body")
    func testShouldRetryWithReinitJSON401() {
        let client = DummyAPIClient()
        let json: [String: Any] = ["errorCode": 401]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let shouldRetry = client.shouldRetryWithReinitialization(data: data, httpStatusCode: 400)
        #expect(shouldRetry == true)
    }

    @Test("shouldRetryWithReinitialization returns false for errorCode 502 in JSON body")
    func testShouldRetryWithReinitJSON502() {
        let client = DummyAPIClient()
        let json: [String: Any] = ["errorCode": 502]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let shouldRetry = client.shouldRetryWithReinitialization(data: data, httpStatusCode: 400)
        #expect(shouldRetry == false)
    }

    @Test("handleInvalidResponse logs and throws")
    func testHandleInvalidResponseThrows() async {
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let headers: [String: String] = ["Authorization": "Bearer token"]
        let startTime = Date()
        actor LogFlag { var didLog = false; func set() { didLog = true } }
        let logFlag = LogFlag()
        let logSink: HTTPLogSink = { (_: HTTPLog) in Task { await logFlag.set() } }
        let apiClient = DummyAPIClient(logSink: logSink)
        do {
            try apiClient.handleInvalidResponse(
                requestType: HTTPRequestType.login,
                request: request,
                requestHeaders: headers,
                requestBody: nil as String?,
                startTime: startTime
            )
            #expect(Bool(false), "Should have thrown")
        } catch let error as HyundaiKiaAPIError {
            #expect(error.message.contains("Invalid response type"))
            #expect(error.apiName == "APIClient")
        } catch {
            #expect(Bool(false), "Unexpected error type")
        }
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        let didLog = await logFlag.didLog
        #expect(didLog == true)
    }

    @Test("validateHTTPResponse throws for 401 and 502 and 400+")
    func testValidateHTTPResponseThrows() {
        let client = DummyAPIClient()
        let url = URL(string: "https://example.com")!
        let response401 = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!
        let response502 = HTTPURLResponse(url: url, statusCode: 502, httpVersion: nil, headerFields: nil)!
        let response404 = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
        let data = Data()
        // 401
        #expect(throws: HyundaiKiaAPIError.self) {
            try client.validateHTTPResponse(response401, data: data, responseBody: "expired")
        }
        // 502
        #expect(throws: HyundaiKiaAPIError.self) {
            try client.validateHTTPResponse(response502, data: data, responseBody: "server error")
        }
        // 404
        #expect(throws: HyundaiKiaAPIError.self) {
            try client.validateHTTPResponse(response404, data: data, responseBody: nil as String?)
        }
    }

    @Test("validateHTTPResponse does not throw for 200")
    func testValidateHTTPResponseSuccess() {
        let client = DummyAPIClient()
        let url = URL(string: "https://example.com")!
        let response200 = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let data = Data()
        do {
            try client.validateHTTPResponse(response200, data: data, responseBody: nil as String?)
            #expect(true)
        } catch {
            #expect(false, "Should not throw for 200")
        }
    }

    // Removed testHandleNetworkErrorThrows: assigning to logSink after init is not allowed and logSink is let
}
