// swiftlint:disable:next concurrency_safety
// MARK: - Global Helper Functions

@MainActor func makeHyundaiProvider(region: Region = .usa) -> HyundaiAPIEndpointProvider {
    let config = APIClientConfiguration(
        region: region,
        brand: .hyundai,
        username: "test@hyundai.com",
        password: "testpassword",
        pin: "1234",
        accountId: UUID()
    )
    return HyundaiAPIEndpointProvider(configuration: config)
}

@MainActor func makeKiaProvider(region: Region = .usa) -> KiaAPIEndpointProvider {
    let config = APIClientConfiguration(
        region: region,
        brand: .kia,
        username: "test@kia.com",
        password: "testpassword",
        pin: "1234",
        accountId: UUID()
    )
    return KiaAPIEndpointProvider(configuration: config)
}

@MainActor func makeConfiguration(region: Region = .usa, brand: Brand = .hyundai) -> APIClientConfiguration {
    return APIClientConfiguration(
        region: region,
        brand: brand,
        username: "test@\(brand == .hyundai ? "hyundai" : "kia").com",
        password: "testpassword",
        pin: "1234",
        accountId: UUID()
    )
}

// MARK: - Canned Response Models

struct LoginResponse: Codable { let accessToken, refreshToken, pin: String; let expiresAt: Date }
struct VehicleResponse: Codable { let vin, regId, model, accountId: String; let isElectric: Bool; let generation: Int; let odometer: Odometer }
struct Odometer: Codable { let length: Int; let units: String }
struct StatusResponse: Codable { let vin: String; let evStatus: EVStatus }
struct EVStatus: Codable { let evRange: EVRange }
struct EVRange: Codable { let range: Odometer; let percentage: Int }

// MARK: - APIClient Async/Core Logic Tests

@Suite("APIClient Async/Core Logic Tests")
struct APIClientAsyncTests {
    actor LogCollector {
        var logs: [HTTPLog] = []
        func add(_ log: HTTPLog) { logs.append(log) }
    }

    // Mock URLProtocol to intercept network calls and return canned responses
    class MockURLProtocol: URLProtocol {
        // Simple test-only responses - accessing only from main thread in tests
        nonisolated(unsafe) static var cannedResponses: [String: (Int, Data)] = [:]
        
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let url = request.url!.absoluteString
            if let (status, data) = MockURLProtocol.cannedResponses[url] {
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
            } else {
                let response = HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data())
            }
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    // Helper to create a mock URLSession
    private func makeMockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    @MainActor private func makeClient<P: APIEndpointProvider>(logSink: HTTPLogSink? = nil, provider: P = TestProvider()) -> APIClient<P> {
        let config = APIClientConfiguration(
            region: .usa,
            brand: .hyundai,
            username: "test@example.com",
            password: "password123",
            pin: "0000",
            accountId: UUID(),
            logSink: logSink
        )
        // Set up canned responses for all endpoints used by TestProvider
        let loginData = try! JSONEncoder().encode(LoginResponse(accessToken: "test_access_token", refreshToken: "test_refresh_token", pin: "0000", expiresAt: Date().addingTimeInterval(3600)))
        let vehiclesData = try! JSONEncoder().encode([VehicleResponse(vin: "TEST123VIN", regId: "REG123", model: "Test Model", accountId: UUID().uuidString, isElectric: true, generation: 3, odometer: Odometer(length: 0, units: "miles"))])
        let statusData = try! JSONEncoder().encode(StatusResponse(vin: "TEST123VIN", evStatus: EVStatus(evRange: EVRange(range: Odometer(length: 100, units: "miles"), percentage: 80))))
        MockURLProtocol.cannedResponses = [
            "https://example.com/login": (200, loginData),
            "https://example.com/vehicles": (200, vehiclesData),
            "https://example.com/vehicles/TEST123VIN/status": (200, statusData),
            "https://example.com/vehicles/TEST123VIN/command": (200, Data()),
        ]
        return APIClient(configuration: config, endpointProvider: provider, urlSession: makeMockSession())
    }

    // NOTE: All async/core tests below use TestProvider, which returns canned responses for full coverage.
    @Test("login() returns AuthToken")
    @MainActor
    func testLoginReturnsAuthToken() async throws {
        let client = makeClient()
        let token = try await client.login()
        #expect(token.accessToken == "test_access_token")
        #expect(token.refreshToken == "test_refresh_token")
        #expect(token.pin == "0000")
    }

    @Test("fetchVehicles() returns vehicles")
    @MainActor
    func testFetchVehiclesReturnsVehicles() async throws {
        let client = makeClient()
        let token = try await client.login()
        let vehicles = try await client.fetchVehicles(authToken: token)
        #expect(vehicles.count == 1)
        #expect(vehicles[0].vin == "TEST123VIN")
    }

    @Test("fetchVehicleStatus() returns status")
    @MainActor
    func testFetchVehicleStatusReturnsStatus() async throws {
        let client = makeClient()
        let token = try await client.login()
        let vehicles = try await client.fetchVehicles(authToken: token)
        let status = try await client.fetchVehicleStatus(for: vehicles[0], authToken: token)
        #expect(status.vin == "TEST123VIN")
        #expect(status.evStatus?.evRange.percentage == 80)
    }

    @Test("sendCommand() completes without error")
    @MainActor
    func testSendCommandCompletes() async throws {
        let client = makeClient()
        let token = try await client.login()
        let vehicles = try await client.fetchVehicles(authToken: token)
        try await client.sendCommand(for: vehicles[0], command: .lock, authToken: token)
        // Test completed successfully if we reach here
    }

    @Test("login() throws on invalid URL")
    @MainActor
    func testLoginThrowsOnInvalidURL() async {
        struct BadProvider: APIEndpointProvider {
            func loginEndpoint() -> APIEndpoint { APIEndpoint(url: "not a url", method: .POST) }
            func fetchVehiclesEndpoint(authToken: AuthToken) -> APIEndpoint { fatalError() }
            func fetchVehicleStatusEndpoint(for vehicle: Vehicle, authToken: AuthToken) -> APIEndpoint { fatalError() }
            func sendCommandEndpoint(for vehicle: Vehicle, command: VehicleCommand, authToken: AuthToken) -> APIEndpoint { fatalError() }
            func parseLoginResponse(_ data: Data, headers: [String: String]) throws -> AuthToken { fatalError() }
            func parseVehiclesResponse(_ data: Data) throws -> [Vehicle] { fatalError() }
            func parseVehicleStatusResponse(_ data: Data, for vehicle: Vehicle) throws -> VehicleStatus { fatalError() }
            func parseCommandResponse(_ data: Data) throws { fatalError() }
        }
    let client = makeClient(provider: BadProvider())
        do {
            _ = try await client.login()
            #expect(Bool(false), "Should have thrown")
        } catch {
            // The test just needs to verify that an error is thrown for invalid URL
            // The specific error message can vary based on the URL validation implementation
            print("Error thrown for invalid URL: \(error)")
            // Test passes if any error is thrown for the invalid URL
        }
    }

    @Test("logSink is called on request")
    @MainActor
    func testLogSinkIsCalled() async throws {
        let collector = LogCollector()
        let logSink: HTTPLogSink = { log in Task { await collector.add(log) } }
        let client = makeClient(logSink: logSink)
        let token = try await client.login()
        _ = try await client.fetchVehicles(authToken: token)
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s for logs
        let logs = await collector.logs
        #expect(logs.count > 0)
    }

    // Add more error/edge case tests as needed for coverage
}
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
        _ = client // Suppress unused variable warning
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

// MARK: - Hyundai API Client Tests

@Suite("Hyundai API Client Tests")
struct HyundaiAPIClientTests {
    
    @MainActor private func makeHyundaiProvider(region: Region = .usa) -> HyundaiAPIEndpointProvider {
        let config = APIClientConfiguration(
            region: region,
            brand: .hyundai,
            username: "test@hyundai.com",
            password: "testpassword",
            pin: "1234",
            accountId: UUID()
        )
        return HyundaiAPIEndpointProvider(configuration: config)
    }
    
    @Test("HyundaiAPIEndpointProvider initialization")
    @MainActor func testHyundaiProviderInitialization() {
        let provider = makeHyundaiProvider()
        // Test that provider was created successfully
        let endpoint = provider.loginEndpoint()
        #expect(endpoint.url.contains("api.telematics.hyundaiusa.com"))
        #expect(endpoint.method == .POST)
    }
    
    @Test("Hyundai login endpoint creation")
    @MainActor func testHyundaiLoginEndpoint() {
        let provider = makeHyundaiProvider()
        let endpoint = provider.loginEndpoint()
        
        #expect(endpoint.url.contains("/v2/ac/oauth/token"))
        #expect(endpoint.method == .POST)
        #expect(endpoint.headers["Content-Type"] == "application/json")
        #expect(endpoint.headers["client_id"] == "m66129Bb-em93-SPAHYN-bZ91-am4540zp19920")
        #expect(endpoint.body != nil)
    }
    
    @Test("Hyundai client ID based on region")
    @MainActor func testHyundaiClientIdByRegion() {
        let usaProvider = makeHyundaiProvider(region: .usa)
        let europeProvider = makeHyundaiProvider(region: .europe)
        
        let usaEndpoint = usaProvider.loginEndpoint()
        let europeEndpoint = europeProvider.loginEndpoint()
        
        #expect(usaEndpoint.headers["client_id"] == "m66129Bb-em93-SPAHYN-bZ91-am4540zp19920")
        #expect(europeEndpoint.headers["client_id"] == "m0na2res08hlm125puuhqzpv")
    }
    
    @Test("Hyundai fetch vehicles endpoint")
    @MainActor func testHyundaiFetchVehiclesEndpoint() {
        let provider = makeHyundaiProvider()
        let authToken = AuthToken(accessToken: "test_token", refreshToken: "refresh", expiresAt: Date().addingTimeInterval(3600), pin: "1234")
        
        let endpoint = provider.fetchVehiclesEndpoint(authToken: authToken)
        
        #expect(endpoint.url.contains("/ac/v2/enrollment/details/test@hyundai.com"))
        #expect(endpoint.method == .GET)
        #expect(endpoint.headers["accessToken"] == "test_token")
        #expect(endpoint.headers["username"] == "test@hyundai.com")
        #expect(endpoint.headers["blueLinkServicePin"] == "1234")
    }
    
    @Test("Hyundai vehicle status endpoint")
    @MainActor func testHyundaiVehicleStatusEndpoint() {
        let provider = makeHyundaiProvider()
        let authToken = AuthToken(accessToken: "test_token", refreshToken: "refresh", expiresAt: Date().addingTimeInterval(3600), pin: "1234")
        let vehicle = Vehicle(vin: "TEST123VIN", regId: "REG123", model: "Test Model", accountId: UUID(), isElectric: true, generation: 3, odometer: Distance(length: 0, units: .miles))
        
        let endpoint = provider.fetchVehicleStatusEndpoint(for: vehicle, authToken: authToken)
        
        #expect(endpoint.url.contains("/ac/v2/rcs/rvs/vehicleStatus"))
        #expect(endpoint.method == .GET)
        #expect(endpoint.headers["vin"] == "TEST123VIN")
        #expect(endpoint.headers["registrationId"] == "REG123")
        #expect(endpoint.headers["gen"] == "3")
    }
    
    @Test("Hyundai command endpoints for different commands")
    @MainActor func testHyundaiCommandEndpoints() {
        let provider = makeHyundaiProvider()
        let authToken = AuthToken(accessToken: "test_token", refreshToken: "refresh", expiresAt: Date().addingTimeInterval(3600), pin: "1234")
        let electricVehicle = Vehicle(vin: "EV123", regId: "REG123", model: "Electric", accountId: UUID(), isElectric: true, generation: 3, odometer: Distance(length: 0, units: .miles))
        let gasVehicle = Vehicle(vin: "GAS123", regId: "REG456", model: "Gas", accountId: UUID(), isElectric: false, generation: 2, odometer: Distance(length: 0, units: .miles))
        
        // Test unlock command
        let unlockEndpoint = provider.sendCommandEndpoint(for: electricVehicle, command: .unlock, authToken: authToken)
        #expect(unlockEndpoint.url.contains("/ac/v2/rcs/rdo/on"))
        
        // Test lock command
        let lockEndpoint = provider.sendCommandEndpoint(for: electricVehicle, command: .lock, authToken: authToken)
        #expect(lockEndpoint.url.contains("/ac/v2/rcs/rdo/off"))
        
        // Test electric vehicle climate commands
        let evStartClimateEndpoint = provider.sendCommandEndpoint(for: electricVehicle, command: .startClimate(ClimateOptions()), authToken: authToken)
        #expect(evStartClimateEndpoint.url.contains("/ac/v2/evc/fatc/start"))
        
        let evStopClimateEndpoint = provider.sendCommandEndpoint(for: electricVehicle, command: .stopClimate, authToken: authToken)
        #expect(evStopClimateEndpoint.url.contains("/ac/v2/evc/fatc/stop"))
        
        // Test gas vehicle climate commands
        let gasStartClimateEndpoint = provider.sendCommandEndpoint(for: gasVehicle, command: .startClimate(ClimateOptions()), authToken: authToken)
        #expect(gasStartClimateEndpoint.url.contains("/ac/v2/rcs/rsc/start"))
        
        let gasStopClimateEndpoint = provider.sendCommandEndpoint(for: gasVehicle, command: .stopClimate, authToken: authToken)
        #expect(gasStopClimateEndpoint.url.contains("/ac/v2/rcs/rsc/stop"))
        
        // Test charge commands
        let startChargeEndpoint = provider.sendCommandEndpoint(for: electricVehicle, command: .startCharge, authToken: authToken)
        #expect(startChargeEndpoint.url.contains("/ac/v2/evc/charge/start"))
        
        let stopChargeEndpoint = provider.sendCommandEndpoint(for: electricVehicle, command: .stopCharge, authToken: authToken)
        #expect(stopChargeEndpoint.url.contains("/ac/v2/evc/charge/stop"))
    }
    
    @Test("Hyundai parse login response success")
    @MainActor func testHyundaiParseLoginResponseSuccess() throws {
        let provider = makeHyundaiProvider()
        let responseData = """
        {
            "access_token": "hyundai_access_token",
            "refresh_token": "hyundai_refresh_token",
            "expires_in": "3600"
        }
        """.data(using: .utf8)!
        
        let authToken = try provider.parseLoginResponse(responseData, headers: [:])
        
        #expect(authToken.accessToken == "hyundai_access_token")
        #expect(authToken.refreshToken == "hyundai_refresh_token")
        #expect(authToken.pin == "1234")
        #expect(authToken.expiresAt > Date())
    }
    
    @Test("Hyundai parse login response failure")
    @MainActor func testHyundaiParseLoginResponseFailure() {
        let provider = makeHyundaiProvider()
        let invalidResponseData = """
        {
            "error": "invalid_credentials"
        }
        """.data(using: .utf8)!
        
        #expect(throws: HyundaiKiaAPIError.self) {
            try provider.parseLoginResponse(invalidResponseData, headers: [:])
        }
    }
    
    @Test("Hyundai parse vehicles response success")
    @MainActor func testHyundaiParseVehiclesResponseSuccess() throws {
        let provider = makeHyundaiProvider()
        let responseData = """
        {
            "enrolledVehicleDetails": [
                {
                    "vehicleDetails": {
                        "vin": "HYUNDAI123VIN",
                        "regid": "HYUNDAI_REG_123",
                        "nickName": "My Hyundai",
                        "evStatus": "E",
                        "vehicleGeneration": "3",
                        "odometer": 15000
                    }
                },
                {
                    "vehicleDetails": {
                        "vin": "HYUNDAI456VIN",
                        "regid": "HYUNDAI_REG_456",
                        "nickName": "Gas Hyundai",
                        "evStatus": "G",
                        "vehicleGeneration": "2",
                        "odometer": "25000"
                    }
                }
            ]
        }
        """.data(using: .utf8)!
        
        let vehicles = try provider.parseVehiclesResponse(responseData)
        
        #expect(vehicles.count == 2)
        
        let evVehicle = vehicles[0]
        #expect(evVehicle.vin == "HYUNDAI123VIN")
        #expect(evVehicle.regId == "HYUNDAI_REG_123")
        #expect(evVehicle.model == "My Hyundai")
        #expect(evVehicle.isElectric == true)
        #expect(evVehicle.generation == 3)
        #expect(evVehicle.odometer.length == 15000)
        
        let gasVehicle = vehicles[1]
        #expect(gasVehicle.vin == "HYUNDAI456VIN")
        #expect(gasVehicle.isElectric == false)
        #expect(gasVehicle.generation == 2)
        #expect(gasVehicle.odometer.length == 25000)
    }
    
    @Test("Hyundai parse vehicles response failure")
    @MainActor func testHyundaiParseVehiclesResponseFailure() {
        let provider = makeHyundaiProvider()
        let invalidResponseData = """
        {
            "error": "no_vehicles"
        }
        """.data(using: .utf8)!
        
        #expect(throws: HyundaiKiaAPIError.self) {
            try provider.parseVehiclesResponse(invalidResponseData)
        }
    }
    
    @Test("Hyundai parse command response with invalid PIN")
    @MainActor func testHyundaiParseCommandResponseInvalidPin() {
        let provider = makeHyundaiProvider()
        let responseData = """
        {
            "isBlueLinkServicePinValid": "invalid",
            "remainingAttemptCount": "2"
        }
        """.data(using: .utf8)!
        
        #expect(throws: HyundaiKiaAPIError.self) {
            try provider.parseCommandResponse(responseData)
        }
    }
    
    @Test("Hyundai parse command response success")
    @MainActor func testHyundaiParseCommandResponseSuccess() throws {
        let provider = makeHyundaiProvider()
        let responseData = """
        {
            "isBlueLinkServicePinValid": "valid",
            "result": "success"
        }
        """.data(using: .utf8)!
        
        // Should not throw
        try provider.parseCommandResponse(responseData)
    }
    
    @Test("Hyundai parse vehicle status response - electric vehicle")
    @MainActor func testHyundaiParseVehicleStatusResponseElectric() throws {
        let provider = makeHyundaiProvider()
        let vehicle = Vehicle(vin: "EV123VIN", regId: "EVREG123", model: "EV Model", accountId: UUID(), isElectric: true, generation: 3, odometer: Distance(length: 15000, units: .miles))
        
        let responseData = """
        {
            "vehicleStatus": {
                "evStatus": {
                    "batteryStatus": 85.5,
                    "batteryCharge": true,
                    "batteryStndChrgPower": 0,
                    "batteryFstChrgPower": 7.2,
                    "batteryPlugin": 1,
                    "drvDistance": [{
                        "type": 1,
                        "rangeByFuel": {
                            "totalAvailableRange": {
                                "value": 250,
                                "unit": 3
                            }
                        }
                    }]
                },
                "doorLock": true,
                "defrost": false,
                "airCtrlOn": true,
                "steerWheelHeat": 1,
                "airTemp": {
                    "value": "72",
                    "unit": 1
                },
                "vehicleLocation": {
                    "coord": {
                        "lat": 37.7749,
                        "lon": -122.4194
                    }
                },
                "dateTime": "2023-10-10T14:30:00Z"
            }
        }
        """.data(using: .utf8)!
        
        let status = try provider.parseVehicleStatusResponse(responseData, for: vehicle)
        
        #expect(status.vin == "EV123VIN")
        #expect(status.evStatus?.charging == true)
        #expect(status.evStatus?.chargeSpeed == 7.2)
        #expect(status.evStatus?.pluggedIn == true)
        #expect(status.evStatus?.evRange.percentage == 85.5)
        #expect(status.evStatus?.evRange.range.length == 250)
        #expect(status.lockStatus == .locked)
        #expect(status.location.latitude == 37.7749)
        #expect(status.location.longitude == -122.4194)
        #expect(status.climateStatus.airControlOn == true)
        #expect(status.climateStatus.defrostOn == false)
        #expect(status.climateStatus.steeringWheelHeatingOn == true)
    }
    
    @Test("Hyundai parse vehicle status response - gas vehicle")
    @MainActor func testHyundaiParseVehicleStatusResponseGas() throws {
        let provider = makeHyundaiProvider()
        let vehicle = Vehicle(vin: "GAS123VIN", regId: "GASREG123", model: "Gas Model", accountId: UUID(), isElectric: false, generation: 2, odometer: Distance(length: 25000, units: .miles))
        
        let responseData = """
        {
            "vehicleStatus": {
                "fuelLevel": 65.5,
                "evStatus": {
                    "drvDistance": [{
                        "type": 3,
                        "rangeByFuel": {
                            "totalAvailableRange": {
                                "value": 350,
                                "unit": 3
                            }
                        }
                    }]
                },
                "doorLock": false,
                "defrost": true,
                "airCtrlOn": false,
                "steerWheelHeat": 0,
                "airTemp": {
                    "value": "68",
                    "unit": 1
                },
                "vehicleLocation": {
                    "coord": {
                        "lat": 40.7128,
                        "lon": -74.0060
                    }
                },
                "dateTime": "2023-10-10T16:45:00Z"
            }
        }
        """.data(using: .utf8)!
        
        let status = try provider.parseVehicleStatusResponse(responseData, for: vehicle)
        
        #expect(status.vin == "GAS123VIN")
        #expect(status.evStatus == nil)
        #expect(status.gasRange?.percentage == 65.5)
        #expect(status.gasRange?.range.length == 350)
        #expect(status.lockStatus == .unlocked)
        #expect(status.location.latitude == 40.7128)
        #expect(status.location.longitude == -74.0060)
        #expect(status.climateStatus.airControlOn == false)
        #expect(status.climateStatus.defrostOn == true)
        #expect(status.climateStatus.steeringWheelHeatingOn == false)
    }
    
    @Test("Hyundai parse vehicle status response - invalid response")
    @MainActor func testHyundaiParseVehicleStatusResponseInvalid() {
        let provider = makeHyundaiProvider()
        let vehicle = Vehicle(vin: "TEST123VIN", regId: "TESTREG123", model: "Test Model", accountId: UUID(), isElectric: true, generation: 3, odometer: Distance(length: 0, units: .miles))
        
        let invalidResponseData = """
        {
            "error": "invalid_status"
        }
        """.data(using: .utf8)!
        
        #expect(throws: HyundaiKiaAPIError.self) {
            try provider.parseVehicleStatusResponse(invalidResponseData, for: vehicle)
        }
    }
}

// MARK: - Kia API Client Tests

@Suite("Kia API Client Tests")
struct KiaAPIClientTests {
    
    @MainActor private func makeKiaProvider(region: Region = .usa) -> KiaAPIEndpointProvider {
        let config = APIClientConfiguration(
            region: region,
            brand: .kia,
            username: "test@kia.com",
            password: "testpassword",
            pin: "5678",
            accountId: UUID()
        )
        return KiaAPIEndpointProvider(configuration: config)
    }
    
    @Test("KiaAPIEndpointProvider initialization")
    @MainActor func testKiaProviderInitialization() {
        let provider = makeKiaProvider()
        let endpoint = provider.loginEndpoint()
        #expect(endpoint.url.contains("apigw/v1/prof/authUser"))
        #expect(endpoint.method == .POST)
    }
    
    @Test("Kia login endpoint creation")
    @MainActor func testKiaLoginEndpoint() {
        let provider = makeKiaProvider()
        let endpoint = provider.loginEndpoint()
        
        #expect(endpoint.url.contains("/apigw/v1/prof/authUser"))
        #expect(endpoint.method == .POST)
        #expect(endpoint.headers["content-type"] == "application/json;charset=UTF-8")
        #expect(endpoint.headers["clientid"] == "MWAMOBILE")
        #expect(endpoint.body != nil)
        
        // Verify login body contains correct structure
        if let bodyData = endpoint.body,
           let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
           let userCredential = json["userCredential"] as? [String: Any] {
            #expect(userCredential["userId"] as? String == "test@kia.com")
            #expect(userCredential["password"] as? String == "testpassword")
        }
    }
    
    @Test("Kia fetch vehicles endpoint")
    @MainActor func testKiaFetchVehiclesEndpoint() {
        let provider = makeKiaProvider()
        let authToken = AuthToken(accessToken: "kia_session_id", refreshToken: "kia_session_id", expiresAt: Date().addingTimeInterval(3600), pin: "5678")
        
        let endpoint = provider.fetchVehiclesEndpoint(authToken: authToken)
        
        #expect(endpoint.url.contains("/apigw/v1/ownr/gvl"))
        #expect(endpoint.method == .GET)
        #expect(endpoint.headers["sid"] == "kia_session_id")
    }
    
    @Test("Kia vehicle status endpoint")
    @MainActor func testKiaVehicleStatusEndpoint() {
        let provider = makeKiaProvider()
        let authToken = AuthToken(accessToken: "kia_session_id", refreshToken: "kia_session_id", expiresAt: Date().addingTimeInterval(3600), pin: "5678")
        let vehicle = Vehicle(vin: "KIA123VIN", regId: "KIA_REG_123", model: "Kia Model", accountId: UUID(), isElectric: true, generation: 3, odometer: Distance(length: 0, units: .miles), vehicleKey: "kia_vehicle_key")
        
        let endpoint = provider.fetchVehicleStatusEndpoint(for: vehicle, authToken: authToken)
        
        #expect(endpoint.url.contains("/apigw/v1/cmm/gvi"))
        #expect(endpoint.method == .POST)
        #expect(endpoint.headers["vinkey"] == "kia_vehicle_key")
        #expect(endpoint.body != nil)
    }
    
    @Test("Kia command endpoints for different commands")
    @MainActor func testKiaCommandEndpoints() {
        let provider = makeKiaProvider()
        let authToken = AuthToken(accessToken: "kia_session_id", refreshToken: "kia_session_id", expiresAt: Date().addingTimeInterval(3600), pin: "5678")
        let vehicle = Vehicle(vin: "KIA123VIN", regId: "KIA_REG_123", model: "Kia Model", accountId: UUID(), isElectric: true, generation: 3, odometer: Distance(length: 0, units: .miles), vehicleKey: "kia_vehicle_key")
        
        // Test lock/unlock commands
        let lockEndpoint = provider.sendCommandEndpoint(for: vehicle, command: .lock, authToken: authToken)
        #expect(lockEndpoint.url.contains("/apigw/v1/rems/door/lock"))
        
        let unlockEndpoint = provider.sendCommandEndpoint(for: vehicle, command: .unlock, authToken: authToken)
        #expect(unlockEndpoint.url.contains("/apigw/v1/rems/door/unlock"))
        
        // Test climate commands
        let startClimateEndpoint = provider.sendCommandEndpoint(for: vehicle, command: .startClimate(ClimateOptions()), authToken: authToken)
        #expect(startClimateEndpoint.url.contains("/apigw/v1/rems/start"))
        
        let stopClimateEndpoint = provider.sendCommandEndpoint(for: vehicle, command: .stopClimate, authToken: authToken)
        #expect(stopClimateEndpoint.url.contains("/apigw/v1/rems/stop"))
        
        // Test charge commands
        let startChargeEndpoint = provider.sendCommandEndpoint(for: vehicle, command: .startCharge, authToken: authToken)
        #expect(startChargeEndpoint.url.contains("/apigw/v1/evc/charge"))
        
        let stopChargeEndpoint = provider.sendCommandEndpoint(for: vehicle, command: .stopCharge, authToken: authToken)
        #expect(stopChargeEndpoint.url.contains("/apigw/v1/evc/cancel"))
    }
    
    @Test("Kia parse login response success")
    @MainActor func testKiaParseLoginResponseSuccess() throws {
        let provider = makeKiaProvider()
        let responseData = """
        {
            "status": {
                "statusCode": 0,
                "errorCode": 0
            }
        }
        """.data(using: .utf8)!
        
        let headers = ["sid": "kia_session_12345"]
        let authToken = try provider.parseLoginResponse(responseData, headers: headers)
        
        #expect(authToken.accessToken == "kia_session_12345")
        #expect(authToken.refreshToken == "kia_session_12345")
        #expect(authToken.pin == "5678")
        #expect(authToken.expiresAt > Date())
    }
    
    @Test("Kia parse login response missing session ID")
    @MainActor func testKiaParseLoginResponseMissingSessionId() {
        let provider = makeKiaProvider()
        let responseData = """
        {
            "status": {
                "statusCode": 0,
                "errorCode": 0
            }
        }
        """.data(using: .utf8)!
        
        #expect(throws: HyundaiKiaAPIError.self) {
            try provider.parseLoginResponse(responseData, headers: [:])
        }
    }
    
    @Test("Kia parse vehicles response success")
    @MainActor func testKiaParseVehiclesResponseSuccess() throws {
        let provider = makeKiaProvider()
        let responseData = """
        {
            "payload": {
                "vehicleSummary": [
                    {
                        "vin": "KIA123VIN",
                        "vehicleIdentifier": "KIA_REG_123",
                        "nickName": "My Kia EV",
                        "vehicleKey": "kia_key_123",
                        "genType": "3",
                        "fuelType": 1,
                        "mileage": 12500
                    },
                    {
                        "vin": "KIA456VIN",
                        "vehicleIdentifier": "KIA_REG_456",
                        "nickName": "My Kia Gas",
                        "vehicleKey": "kia_key_456",
                        "genType": "2",
                        "fuelType": 3,
                        "mileage": "35000"
                    }
                ]
            }
        }
        """.data(using: .utf8)!
        
        let vehicles = try provider.parseVehiclesResponse(responseData)
        
        #expect(vehicles.count == 2)
        
        let evVehicle = vehicles[0]
        #expect(evVehicle.vin == "KIA123VIN")
        #expect(evVehicle.regId == "KIA_REG_123")
        #expect(evVehicle.model == "My Kia EV")
        #expect(evVehicle.isElectric == true)
        #expect(evVehicle.generation == 3)
        #expect(evVehicle.vehicleKey == "kia_key_123")
        #expect(evVehicle.odometer.length == 12500)
        
        let gasVehicle = vehicles[1]
        #expect(gasVehicle.vin == "KIA456VIN")
        #expect(gasVehicle.isElectric == false)
        #expect(gasVehicle.generation == 2)
        #expect(gasVehicle.vehicleKey == "kia_key_456")
        #expect(gasVehicle.odometer.length == 35000)
    }
    
    @Test("Kia parse vehicles response failure")
    @MainActor func testKiaParseVehiclesResponseFailure() {
        let provider = makeKiaProvider()
        let invalidResponseData = """
        {
            "error": "no_vehicles"
        }
        """.data(using: .utf8)!
        
        #expect(throws: HyundaiKiaAPIError.self) {
            try provider.parseVehiclesResponse(invalidResponseData)
        }
    }
    
    @Test("Kia error handling - invalid credentials")
    @MainActor func testKiaErrorHandlingInvalidCredentials() {
        let provider = makeKiaProvider()
        let responseData = """
        {
            "status": {
                "statusCode": 1,
                "errorCode": 1,
                "errorMessage": "Invalid username or password",
                "errorType": 1
            }
        }
        """.data(using: .utf8)!
        
        #expect(throws: HyundaiKiaAPIError.self) {
            try provider.parseLoginResponse(responseData, headers: ["sid": "test"])
        }
    }
    
    @Test("Kia error handling - session expired")
    @MainActor func testKiaErrorHandlingSessionExpired() {
        let provider = makeKiaProvider()
        let responseData = """
        {
            "status": {
                "statusCode": 1,
                "errorCode": 1003,
                "errorMessage": "Session key is invalid or expired",
                "errorType": 1
            }
        }
        """.data(using: .utf8)!
        
        #expect(throws: HyundaiKiaAPIError.self) {
            try provider.parseLoginResponse(responseData, headers: ["sid": "test"])
        }
    }
    
    @Test("Kia error handling - vehicle session error")
    @MainActor func testKiaErrorHandlingVehicleSession() {
        let provider = makeKiaProvider()
        let responseData = """
        {
            "status": {
                "statusCode": 1,
                "errorCode": 1005,
                "errorMessage": "Invalid vehicle session",
                "errorType": 1
            }
        }
        """.data(using: .utf8)!
        
        #expect(throws: HyundaiKiaAPIError.self) {
            try provider.parseLoginResponse(responseData, headers: ["sid": "test"])
        }
    }
    
    @Test("Kia parse vehicle status response - electric vehicle")
    @MainActor func testKiaParseVehicleStatusResponseElectric() throws {
        let provider = makeKiaProvider()
        let vehicle = Vehicle(vin: "KIA_EV123", regId: "KIA_EV_REG", model: "Kia EV", accountId: UUID(), isElectric: true, generation: 3, odometer: Distance(length: 12000, units: .miles), vehicleKey: "kia_ev_key")
        
        let responseData = """
        {
            "payload": {
                "vehicleInfoList": [{
                    "lastVehicleInfo": {
                        "location": {
                            "coord": {
                                "lat": 35.6762,
                                "lon": 139.6503
                            }
                        },
                        "vehicleStatusRpt": {
                            "vehicleStatus": {
                                "evStatus": {
                                    "batteryStatus": 78.5,
                                    "batteryCharge": false,
                                    "batteryStndChrgPower": 0,
                                    "batteryFstChrgPower": 0,
                                    "batteryPlugin": 0,
                                    "drvDistance": [{
                                        "rangeByFuel": {
                                            "evModeRange": {
                                                "value": 180,
                                                "unit": 3
                                            }
                                        }
                                    }]
                                },
                                "doorLock": true,
                                "climate": {
                                    "defrost": false,
                                    "airCtrl": true,
                                    "airTemp": {
                                        "value": "70",
                                        "unit": 1
                                    },
                                    "heatingAccessory": {
                                        "steeringWheel": 1
                                    }
                                },
                                "syncDate": {
                                    "utc": "20231010143000"
                                }
                            }
                        }
                    }
                }]
            }
        }
        """.data(using: .utf8)!
        
        let status = try provider.parseVehicleStatusResponse(responseData, for: vehicle)
        
        #expect(status.vin == "KIA_EV123")
        #expect(status.evStatus?.charging == false)
        #expect(status.evStatus?.chargeSpeed == 0)
        #expect(status.evStatus?.pluggedIn == false)
        #expect(status.evStatus?.evRange.percentage == 78.5)
        #expect(status.evStatus?.evRange.range.length == 180)
        #expect(status.lockStatus == .locked)
        #expect(status.location.latitude == 35.6762)
        #expect(status.location.longitude == 139.6503)
        #expect(status.climateStatus.airControlOn == true)
        #expect(status.climateStatus.defrostOn == false)
        #expect(status.climateStatus.steeringWheelHeatingOn == true)
        #expect(status.syncDate != nil)
    }
    
    @Test("Kia parse vehicle status response - gas vehicle")
    @MainActor func testKiaParseVehicleStatusResponseGas() throws {
        let provider = makeKiaProvider()
        let vehicle = Vehicle(vin: "KIA_GAS456", regId: "KIA_GAS_REG", model: "Kia Gas", accountId: UUID(), isElectric: false, generation: 2, odometer: Distance(length: 35000, units: .miles), vehicleKey: "kia_gas_key")
        
        let responseData = """
        {
            "payload": {
                "vehicleInfoList": [{
                    "lastVehicleInfo": {
                        "location": {
                            "coord": {
                                "lat": 51.5074,
                                "lon": -0.1278
                            }
                        },
                        "vehicleStatusRpt": {
                            "vehicleStatus": {
                                "evStatus": {
                                    "batteryStatus": 0
                                },
                                "fuelLevel": 45.8,
                                "distanceToEmpty": {
                                    "value": 280,
                                    "unit": 3
                                },
                                "doorLock": false,
                                "climate": {
                                    "defrost": true,
                                    "airCtrl": false,
                                    "airTemp": {
                                        "value": "22",
                                        "unit": 2
                                    },
                                    "heatingAccessory": {
                                        "steeringWheel": 0
                                    }
                                },
                                "syncDate": {
                                    "utc": "20231010180000"
                                }
                            }
                        }
                    }
                }]
            }
        }
        """.data(using: .utf8)!
        
        let status = try provider.parseVehicleStatusResponse(responseData, for: vehicle)
        
        #expect(status.vin == "KIA_GAS456")
        #expect(status.evStatus == nil)
        #expect(status.gasRange?.percentage == 45.8)
        #expect(status.gasRange?.range.length == 280)
        #expect(status.lockStatus == .unlocked)
        #expect(status.location.latitude == 51.5074)
        #expect(status.location.longitude == -0.1278)
        #expect(status.climateStatus.airControlOn == false)
        #expect(status.climateStatus.defrostOn == true)
        #expect(status.climateStatus.steeringWheelHeatingOn == false)
        #expect(status.syncDate != nil)
    }
    
    @Test("Kia parse vehicle status response - invalid response")
    @MainActor func testKiaParseVehicleStatusResponseInvalid() {
        let provider = makeKiaProvider()
        let vehicle = Vehicle(vin: "KIA_TEST123", regId: "KIA_TEST_REG", model: "Kia Test", accountId: UUID(), isElectric: true, generation: 3, odometer: Distance(length: 0, units: .miles), vehicleKey: "kia_test_key")
        
        let invalidResponseData = """
        {
            "error": "invalid_vehicle_status"
        }
        """.data(using: .utf8)!
        
        #expect(throws: HyundaiKiaAPIError.self) {
            try provider.parseVehicleStatusResponse(invalidResponseData, for: vehicle)
        }
    }
    
    @Test("Kia parse command response success")
    @MainActor func testKiaParseCommandResponseSuccess() throws {
        let provider = makeKiaProvider()
        let responseData = """
        {
            "status": {
                "statusCode": 0,
                "errorCode": 0,
                "errorMessage": "Success"
            }
        }
        """.data(using: .utf8)!
        
        // Should not throw
        try provider.parseCommandResponse(responseData)
    }
    
    @Test("Kia device ID generation")
    @MainActor func testKiaDeviceIdGeneration() {
        let provider1 = makeKiaProvider()
        let provider2 = makeKiaProvider()
        
        let endpoint1 = provider1.loginEndpoint()
        let endpoint2 = provider2.loginEndpoint()
        
        // Device IDs should be different for different instances
        #expect(endpoint1.headers["deviceid"] != endpoint2.headers["deviceid"])
        #expect(endpoint1.headers["deviceid"]?.count == 55) // 22 chars + ":" + 32 chars UUID
        #expect(endpoint2.headers["deviceid"]?.count == 55)
    }
}

// MARK: - Additional Edge Case Tests

@Suite("APIClient Edge Cases Tests")
struct APIClientEdgeCasesTests {
    
    @Test("Handle nil Content-Type header scenario")
    @MainActor func testNilContentTypeHeader() {
        let provider = makeHyundaiProvider()
        let client = APIClient(configuration: makeConfiguration(), endpointProvider: provider)
        
        let endpoint = APIEndpoint(
            url: "https://api.hyundai.com/test",
            method: .POST,
            headers: [:], // No Content-Type header
            body: nil
        )
        
        let request = try! client.createRequest(from: endpoint)
        
        // Should set default Content-Type
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }
    
    @Test("Handle custom Content-Type header")
    @MainActor func testCustomContentTypeHeader() {
        let provider = makeHyundaiProvider()
        let client = APIClient(configuration: makeConfiguration(), endpointProvider: provider)
        
        let endpoint = APIEndpoint(
            url: "https://api.hyundai.com/test",
            method: .POST,
            headers: ["Content-Type": "application/xml"],
            body: nil
        )
        
        let request = try! client.createRequest(from: endpoint)
        
        // Should preserve custom Content-Type
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/xml")
    }
    
    @Test("Test extractResponseHeaders with mixed header types")
    @MainActor func testExtractResponseHeaders() {
        let provider = makeHyundaiProvider()
        let client = APIClient(configuration: makeConfiguration(), endpointProvider: provider)
        
        // Create a mock HTTP response with mixed header types
        let url = URL(string: "https://test.com")!
        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: [
                "Content-Type": "application/json",
                "Authorization": "Bearer token123",
                "X-Custom-Header": "custom-value"
            ]
        )!
        
        let headers = client.extractResponseHeaders(from: httpResponse)
        
        #expect(headers["Content-Type"] == "application/json")
        #expect(headers["Authorization"] == "Bearer token123")
        #expect(headers["X-Custom-Header"] == "custom-value")
    }
    
    @Test("Test RequestContext creation")
    @MainActor func testRequestContextCreation() {
        let request = URLRequest(url: URL(string: "https://test.com")!)
        let headers = ["Authorization": "Bearer test"]
        let body = "test body"
        let startTime = Date()
        
        let context = APIClient<HyundaiAPIEndpointProvider>.RequestContext(
            requestType: .login,
            request: request,
            requestHeaders: headers,
            requestBody: body,
            startTime: startTime
        )
        
        #expect(context.requestType == .login)
        #expect(context.request == request)
        #expect(context.requestHeaders == headers)
        #expect(context.requestBody == body)
        #expect(context.startTime == startTime)
    }
    
    @Test("Test APIClient generic conformance")
    @MainActor func testAPIClientProtocolConformance() {
        let provider = makeHyundaiProvider()
        let client = APIClient(configuration: makeConfiguration(), endpointProvider: provider)
        
        // Should conform to APIClientProtocol
        let protocolClient: APIClientProtocol = client
        #expect(protocolClient is APIClient<HyundaiAPIEndpointProvider>)
    }
}

// MARK: - ExtractNumber Function Tests

@Suite("ExtractNumber Function Tests")
struct ExtractNumberFunctionTests {
    
    @Test("extractNumber with Double conversion")
    func testExtractNumberDouble() {
        let result: Double? = extractNumber(from: "123.45")
        #expect(result == 123.45)
        
        let resultDirect: Double? = extractNumber(from: 67.89)
        #expect(resultDirect == 67.89)
        
        let resultNil: Double? = extractNumber(from: nil)
        #expect(resultNil == nil)
        
        let resultInvalid: Double? = extractNumber(from: "invalid")
        #expect(resultInvalid == nil)
    }
    
    @Test("extractNumber with Int conversion")
    func testExtractNumberInt() {
        let result: Int? = extractNumber(from: "123")
        #expect(result == 123)
        
        let resultDirect: Int? = extractNumber(from: 456)
        #expect(resultDirect == 456)
        
        let resultFloat: Int? = extractNumber(from: 78.0)
        #expect(resultFloat == nil) // Float to Int conversion should fail
        
        let resultNil: Int? = extractNumber(from: nil)
        #expect(resultNil == nil)
    }
    
    @Test("extractNumber with Bool conversion")
    func testExtractNumberBool() {
        let resultTrue: Bool? = extractNumber(from: true)
        #expect(resultTrue == true)
        
        let resultFalse: Bool? = extractNumber(from: false)
        #expect(resultFalse == false)
        
        let resultStringTrue: Bool? = extractNumber(from: "true")
        #expect(resultStringTrue == true)
        
        let resultStringFalse: Bool? = extractNumber(from: "false")
        #expect(resultStringFalse == false)
    }
}

// MARK: - APIClient Logging Edge Cases Tests

@Suite("APIClient Logging Edge Cases Tests")
struct APIClientLoggingEdgeCasesTests {
    
    @Test("HTTPRequestLogData with all fields")
    @MainActor func testHTTPRequestLogDataComplete() {
        let request = URLRequest(url: URL(string: "https://test.com")!)
        let startTime = Date()
        
        let logData = APIClient<HyundaiAPIEndpointProvider>.HTTPRequestLogData(
            requestType: .login,
            request: request,
            requestHeaders: ["Authorization": "Bearer test"],
            requestBody: "test body",
            responseStatus: 200,
            responseHeaders: ["Content-Type": "application/json"],
            responseBody: "test response",
            error: "test error",
            apiError: "test api error",
            startTime: startTime
        )
        
        #expect(logData.requestType == .login)
        #expect(logData.request == request)
        #expect(logData.requestHeaders["Authorization"] == "Bearer test")
        #expect(logData.requestBody == "test body")
        #expect(logData.responseStatus == 200)
        #expect(logData.responseHeaders["Content-Type"] == "application/json")
        #expect(logData.responseBody == "test response")
        #expect(logData.error == "test error")
        #expect(logData.apiError == "test api error")
        #expect(logData.startTime == startTime)
    }
    
    @Test("logHTTPRequest with nil URL")
    @MainActor func testLogHTTPRequestWithNilURL() {
        let provider = makeHyundaiProvider()
        let client = APIClient(configuration: makeConfiguration(), endpointProvider: provider)
        
        // Create request with nil URL scenario
        var request = URLRequest(url: URL(string: "https://test.com")!)
        request.url = nil // This creates the nil URL scenario
        
        let logData = APIClient<HyundaiAPIEndpointProvider>.HTTPRequestLogData(
            requestType: .login,
            request: request,
            requestHeaders: [:],
            requestBody: nil,
            responseStatus: nil,
            responseHeaders: [:],
            responseBody: nil,
            error: nil,
            apiError: nil,
            startTime: Date()
        )
        
        // Test that it doesn't crash with nil URL and handles gracefully
        client.logHTTPRequest(logData)
    }
    
    @Test("logHTTPRequest with nil HTTP method")
    @MainActor func testLogHTTPRequestWithNilMethod() {
        let provider = makeHyundaiProvider()
        let client = APIClient(configuration: makeConfiguration(), endpointProvider: provider)
        
        // Create request with nil HTTP method
        var request = URLRequest(url: URL(string: "https://test.com")!)
        request.httpMethod = nil // This creates the nil method scenario
        
        let logData = APIClient<HyundaiAPIEndpointProvider>.HTTPRequestLogData(
            requestType: .login,
            request: request,
            requestHeaders: [:],
            requestBody: nil,
            responseStatus: nil,
            responseHeaders: [:],
            responseBody: nil,
            error: nil,
            apiError: nil,
            startTime: Date()
        )
        
        // Test that it doesn't crash with nil method and handles gracefully
        client.logHTTPRequest(logData)
    }
    
    @Test("extractAPIError with Kia/Hyundai status pattern")
    @MainActor func testExtractAPIErrorStatusPattern() {
        let provider = makeHyundaiProvider()
        let client = APIClient(configuration: makeConfiguration(), endpointProvider: provider)
        
        let errorData = """
        {
            "status": {
                "errorCode": 1001,
                "errorMessage": "Invalid session token"
            }
        }
        """.data(using: .utf8)!
        
        let result = client.extractAPIError(from: errorData)
        #expect(result == "API Error 1001: Invalid session token")
    }
    
    @Test("extractAPIError with zero errorCode")
    @MainActor func testExtractAPIErrorZeroErrorCode() {
        let provider = makeHyundaiProvider()
        let client = APIClient(configuration: makeConfiguration(), endpointProvider: provider)
        
        let successData = """
        {
            "status": {
                "errorCode": 0,
                "errorMessage": "Success"
            }
        }
        """.data(using: .utf8)!
        
        let result = client.extractAPIError(from: successData)
        #expect(result == nil) // Should return nil for errorCode 0
    }
    
    @Test("extractAPIError with direct errorCode 502")
    @MainActor func testExtractAPIErrorDirect502() {
        let provider = makeHyundaiProvider()
        let client = APIClient(configuration: makeConfiguration(), endpointProvider: provider)
        
        let errorData = """
        {
            "errorCode": 502,
            "errorMessage": "Bad Gateway"
        }
        """.data(using: .utf8)!
        
        let result = client.extractAPIError(from: errorData)
        #expect(result == "API Error 502: Bad Gateway")
    }
    
    @Test("extractAPIError with direct errorCode 502 no message")
    @MainActor func testExtractAPIErrorDirect502NoMessage() {
        let provider = makeHyundaiProvider()
        let client = APIClient(configuration: makeConfiguration(), endpointProvider: provider)
        
        let errorData = """
        {
            "errorCode": 502
        }
        """.data(using: .utf8)!
        
        let result = client.extractAPIError(from: errorData)
        #expect(result == "API Error 502: Server error")
    }
    
    @Test("extractAPIError with direct errorCode 401 no message")
    @MainActor func testExtractAPIErrorDirect401NoMessage() {
        let provider = makeHyundaiProvider()
        let client = APIClient(configuration: makeConfiguration(), endpointProvider: provider)
        
        let errorData = """
        {
            "errorCode": 401
        }
        """.data(using: .utf8)!
        
        let result = client.extractAPIError(from: errorData)
        #expect(result == "API Error 401: Authentication error")
    }
    
    @Test("extractAPIError with other errorCode")
    @MainActor func testExtractAPIErrorOtherCode() {
        let provider = makeHyundaiProvider()
        let client = APIClient(configuration: makeConfiguration(), endpointProvider: provider)
        
        let errorData = """
        {
            "errorCode": 999,
            "errorMessage": "Unknown error"
        }
        """.data(using: .utf8)!
        
        let result = client.extractAPIError(from: errorData)
        #expect(result == nil) // Should return nil for non-401/502 codes
    }
}

