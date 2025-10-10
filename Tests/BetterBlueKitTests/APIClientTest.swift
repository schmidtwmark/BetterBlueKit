//
//  APIClientTests.swift
//  BetterBlueKit
//
//  Created by Eric Rolf on 10/9/25.
//

import Foundation
import Testing
@testable import BetterBlueKit

// MARK: - Test Provider
struct TestProvider: APIEndpointProvider {
    func loginEndpoint() -> APIEndpoint {
        APIEndpoint(url: "https://example.com/login", method: .POST)
    }
    
    func fetchVehiclesEndpoint(authToken: AuthToken) -> APIEndpoint {
        APIEndpoint(url: "https://example.com/vehicles", method: .GET)
    }
    
    func fetchVehicleStatusEndpoint(for vehicle: Vehicle, authToken: AuthToken) -> APIEndpoint {
        APIEndpoint(url: "https://example.com/vehicles/\(vehicle.vin)/status", method: .GET)
    }
    
    func sendCommandEndpoint(for vehicle: Vehicle, command: VehicleCommand, authToken: AuthToken) -> APIEndpoint {
        APIEndpoint(url: "https://example.com/vehicles/\(vehicle.vin)/command", method: .POST)
    }

    // Parsing canned responses
    func parseLoginResponse(_ data: Data, headers: [String: String]) throws -> AuthToken {
        return AuthToken(accessToken: "test_access_token", refreshToken: "test_refresh_token", expiresAt: Date().addingTimeInterval(3600), pin: "0000")
    }
    
    func parseVehiclesResponse(_ data: Data) throws -> [Vehicle] {
        return [
            Vehicle(vin: "TEST123VIN", regId: "REG123", model: "Test Model", accountId: UUID(), isElectric: true, generation: 3, odometer: Distance(length: 0, units: .miles))
        ]
    }
    
    func parseVehicleStatusResponse(_ data: Data, for vehicle: Vehicle) throws -> VehicleStatus {
        return VehicleStatus(
            vin: vehicle.vin,
            gasRange: nil,
            evStatus: .init(charging: false, chargeSpeed: 0, pluggedIn: false, evRange: .init(range: Distance(length: 100, units: .miles), percentage: 80)),
            location: .init(latitude: 37.7749, longitude: -122.4194),
            lockStatus: .locked,
            climateStatus: .init(defrostOn: false, airControlOn: false, steeringWheelHeatingOn: false, temperature: Temperature(value: 70, units: .fahrenheit)),
            odometer: nil,
            syncDate: nil
        )
    }
    
    func parseCommandResponse(_ data: Data) throws { 
        // no-op for successful commands
    }
}

// MARK: - APIClient Configuration Tests

@Suite("APIClient Configuration Tests")
struct APIClientConfigurationTests {
    
    @Test("APIClientConfiguration creation")
    func testAPIClientConfigurationCreation() {
        let accountId = UUID()
        let logSink: HTTPLogSink = { _ in }
        
        let config = APIClientConfiguration(
            region: .usa,
            brand: .hyundai,
            username: "test@example.com",
            password: "password123",
            pin: "1234",
            accountId: accountId,
            logSink: logSink
        )
        
        #expect(config.region == .usa)
        #expect(config.brand == .hyundai)
        #expect(config.username == "test@example.com")
        #expect(config.password == "password123")
        #expect(config.pin == "1234")
        #expect(config.accountId == accountId)
        #expect(config.logSink != nil)
    }
    
    @Test("APIClientConfiguration creation without log sink")
    func testAPIClientConfigurationWithoutLogSink() {
        let config = APIClientConfiguration(
            region: .canada,
            brand: .kia,
            username: "user@test.com",
            password: "secret",
            pin: "0000",
            accountId: UUID()
        )
        
        #expect(config.region == .canada)
        #expect(config.brand == .kia)
        #expect(config.logSink == nil)
    }
}

// MARK: - APIEndpoint Tests

@Suite("APIEndpoint Tests")
struct APIEndpointTests {
    
    @Test("APIEndpoint creation with all parameters")
    func testAPIEndpointCreation() {
        let headers = ["Authorization": "Bearer token", "Content-Type": "application/json"]
        let body = Data("{\"test\":\"data\"}".utf8)
        
        let endpoint = APIEndpoint(
            url: "https://api.example.com/test",
            method: .POST,
            headers: headers,
            body: body
        )
        
        #expect(endpoint.url == "https://api.example.com/test")
        #expect(endpoint.method == .POST)
        #expect(endpoint.headers["Authorization"] == "Bearer token")
        #expect(endpoint.headers["Content-Type"] == "application/json")
        #expect(endpoint.body == body)
    }
    
    @Test("APIEndpoint creation with minimal parameters")
    func testAPIEndpointMinimal() {
        let endpoint = APIEndpoint(
            url: "https://api.example.com/get",
            method: .GET
        )
        
        #expect(endpoint.url == "https://api.example.com/get")
        #expect(endpoint.method == .GET)
        #expect(endpoint.headers.isEmpty)
        #expect(endpoint.body == nil)
    }
    
    @Test("HTTPMethod raw values")
    func testHTTPMethodRawValues() {
        #expect(HTTPMethod.GET.rawValue == "GET")
        #expect(HTTPMethod.POST.rawValue == "POST")
        #expect(HTTPMethod.PUT.rawValue == "PUT")
        #expect(HTTPMethod.DELETE.rawValue == "DELETE")
    }
}

// MARK: - APIClient Core Tests

@Suite("APIClient Core Tests")
struct APIClientTests {

    @MainActor private func makeClient() -> APIClient<TestProvider> {
        let config = APIClientConfiguration(
            region: .usa,
            brand: .hyundai,
            username: "test@example.com",
            password: "password123",
            pin: "0000",
            accountId: UUID(),
            logSink: nil
        )
        return APIClient(configuration: config, endpointProvider: TestProvider())
    }

    @Test("APIClient initialization")
    @MainActor func testAPIClientInitialization() {
        let client = makeClient()
        
        #expect(client.region == .usa)
        #expect(client.brand == .hyundai)
        #expect(client.username == "test@example.com")
        #expect(client.password == "password123")
        #expect(client.pin == "0000")
        #expect(client.logSink == nil)
    }
    
    @Test("APIClient endpoint provider integration")
    @MainActor func testAPIClientEndpointProvider() {
        let client = makeClient()
        let provider = TestProvider()
        
        // Test that endpoints are created correctly
        let loginEndpoint = provider.loginEndpoint()
        #expect(loginEndpoint.url == "https://example.com/login")
        #expect(loginEndpoint.method == .POST)
        
        let authToken = AuthToken(accessToken: "test", refreshToken: "test", expiresAt: Date(), pin: "0000")
        let vehiclesEndpoint = provider.fetchVehiclesEndpoint(authToken: authToken)
        #expect(vehiclesEndpoint.url == "https://example.com/vehicles")
        #expect(vehiclesEndpoint.method == .GET)
    }
}

