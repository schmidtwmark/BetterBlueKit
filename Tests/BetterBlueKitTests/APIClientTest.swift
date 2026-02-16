// swiftlint:disable file_length type_body_length line_length force_try
//
//  APIClientTests.swift
//  BetterBlueKit
//
//  Tests for API client configuration and utilities
//

import Foundation
import Testing
@testable import BetterBlueKit

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

    @Test("APIClientConfiguration with rememberMeToken")
    func testAPIClientConfigurationWithRememberMeToken() {
        let config = APIClientConfiguration(
            region: .usa,
            brand: .kia,
            username: "user@test.com",
            password: "secret",
            pin: "0000",
            accountId: UUID(),
            rememberMeToken: "rmtoken123"
        )

        #expect(config.rememberMeToken == "rmtoken123")
    }
}

// MARK: - HTTPMethod Tests

@Suite("HTTPMethod Tests")
struct HTTPMethodTests {

    @Test("HTTPMethod raw values")
    func testHTTPMethodRawValues() {
        #expect(HTTPMethod.GET.rawValue == "GET")
        #expect(HTTPMethod.POST.rawValue == "POST")
        #expect(HTTPMethod.PUT.rawValue == "PUT")
        #expect(HTTPMethod.DELETE.rawValue == "DELETE")
    }
}

// MARK: - APIClientProtocol Default Implementation Tests

@Suite("APIClientProtocol Default Tests")
struct APIClientProtocolDefaultTests {

    @Test("Default supportsMFA returns false")
    @MainActor func testDefaultSupportsMFA() {
        // HyundaiUSAAPIClient does not override supportsMFA, so it should use default
        let config = APIClientConfiguration(
            region: .usa,
            brand: .hyundai,
            username: "test@example.com",
            password: "password123",
            pin: "0000",
            accountId: UUID()
        )
        let client = HyundaiUSAAPIClient(configuration: config)

        #expect(client.supportsMFA() == false)
    }

    @Test("KiaUSAAPIClient supports MFA")
    @MainActor func testKiaSupportsMFA() {
        let config = APIClientConfiguration(
            region: .usa,
            brand: .kia,
            username: "test@example.com",
            password: "password123",
            pin: "0000",
            accountId: UUID()
        )
        let client = KiaUSAAPIClient(configuration: config)

        #expect(client.supportsMFA() == true)
    }
}

// MARK: - API Client Factory Tests

@Suite("API Client Factory Tests")
struct APIClientFactoryTests {

    @Test("Create Hyundai USA client")
    @MainActor func testCreateHyundaiUSAClient() throws {
        let config = APIClientConfiguration(
            region: .usa,
            brand: .hyundai,
            username: "test@example.com",
            password: "password123",
            pin: "0000",
            accountId: UUID()
        )

        let client = try createBetterBlueKitAPIClient(configuration: config)
        #expect(client is HyundaiUSAAPIClient)
    }

    @Test("Create Kia USA client")
    @MainActor func testCreateKiaUSAClient() throws {
        let config = APIClientConfiguration(
            region: .usa,
            brand: .kia,
            username: "test@example.com",
            password: "password123",
            pin: "0000",
            accountId: UUID()
        )

        let client = try createBetterBlueKitAPIClient(configuration: config)
        #expect(client is KiaUSAAPIClient)
    }

    @Test("Create Hyundai Europe client")
    @MainActor func testCreateHyundaiEuropeClient() throws {
        let config = APIClientConfiguration(
            region: .europe,
            brand: .hyundai,
            username: "test@example.com",
            password: "password123",
            pin: "0000",
            accountId: UUID()
        )

        let client = try createBetterBlueKitAPIClient(configuration: config)
        #expect(client is HyundaiEuropeAPIClient)
    }

    @Test("Unsupported Hyundai region throws error")
    @MainActor func testUnsupportedRegionThrows() {
        let config = APIClientConfiguration(
            region: .australia,
            brand: .hyundai,
            username: "test@example.com",
            password: "password123",
            pin: "0000",
            accountId: UUID()
        )

        #expect(throws: RegionSupportError.self) {
            _ = try createBetterBlueKitAPIClient(configuration: config)
        }
    }

    @Test("Create Hyundai Canada client")
    @MainActor func testCreateHyundaiCanadaClient() throws {
        let config = APIClientConfiguration(
            region: .canada,
            brand: .hyundai,
            username: "test@example.com",
            password: "password123",
            pin: "0000",
            accountId: UUID()
        )

        let client = try createBetterBlueKitAPIClient(configuration: config)
        #expect(client is HyundaiCanadaAPIClient)
    }

    @Test("Fake brand throws error")
    @MainActor func testFakeBrandThrows() {
        let config = APIClientConfiguration(
            region: .usa,
            brand: .fake,
            username: "test@example.com",
            password: "password123",
            pin: "0000",
            accountId: UUID()
        )

        #expect(throws: RegionSupportError.self) {
            _ = try createBetterBlueKitAPIClient(configuration: config)
        }
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

// MARK: - Region Not Supported Tests

@Suite("Region Not Supported Tests")
struct RegionNotSupportedTests {

    @Test("Hyundai Canada client can be created")
    @MainActor func testHyundaiCanadaClientCreation() {
        let config = APIClientConfiguration(
            region: .canada,
            brand: .hyundai,
            username: "test@example.com",
            password: "password123",
            pin: "0000",
            accountId: UUID()
        )

        let client = HyundaiCanadaAPIClient(configuration: config)
        #expect(client.apiName == "HyundaiCanada")
    }

    @Test("Kia Canada throws region not supported")
    @MainActor func testKiaCanadaNotSupported() async {
        let config = APIClientConfiguration(
            region: .canada,
            brand: .kia,
            username: "test@example.com",
            password: "password123",
            pin: "0000",
            accountId: UUID()
        )
        let client = KiaCanadaAPIClient(configuration: config)

        do {
            _ = try await client.login()
            #expect(Bool(false), "Should have thrown")
        } catch let error as APIError {
            #expect(error.errorType == .regionNotSupported)
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }

    @Test("Kia Australia throws region not supported")
    @MainActor func testKiaAustraliaNotSupported() async {
        let config = APIClientConfiguration(
            region: .australia,
            brand: .kia,
            username: "test@example.com",
            password: "password123",
            pin: "0000",
            accountId: UUID()
        )
        let client = KiaAustraliaAPIClient(configuration: config)

        do {
            _ = try await client.login()
            #expect(Bool(false), "Should have thrown")
        } catch let error as APIError {
            #expect(error.errorType == .regionNotSupported)
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }
}

// MARK: - Sensitive Data Redactor Tests

@Suite("Sensitive Data Redactor Tests")
struct SensitiveDataRedactorTests {

    @Test("Redact password from JSON")
    func testRedactPassword() {
        let json = """
        {"username": "test@example.com", "password": "secret123"}
        """
        let redacted = SensitiveDataRedactor.redact(json)

        #expect(redacted?.contains("[REDACTED]") == true)
        #expect(redacted?.contains("secret123") == false)
    }

    @Test("Redact Bearer token")
    func testRedactBearerToken() {
        let text = "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
        let redacted = SensitiveDataRedactor.redact(text)

        #expect(redacted?.contains("[REDACTED]") == true)
        #expect(redacted?.contains("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9") == false)
    }

    @Test("Redact access_token from JSON")
    func testRedactAccessToken() {
        let json = """
        {"access_token": "abc123token", "expires_in": 3600}
        """
        let redacted = SensitiveDataRedactor.redact(json)

        #expect(redacted?.contains("[REDACTED]") == true)
        #expect(redacted?.contains("abc123token") == false)
    }

    @Test("Redact coordinates")
    func testRedactCoordinates() {
        let json = """
        {"latitude": 37.7749, "longitude": -122.4194}
        """
        let redacted = SensitiveDataRedactor.redact(json)

        #expect(redacted?.contains("[REDACTED]") == true)
    }

    @Test("Redact nil returns nil")
    func testRedactNil() {
        let result = SensitiveDataRedactor.redact(nil)
        #expect(result == nil)
    }

    @Test("Redact headers")
    func testRedactHeaders() {
        let headers = [
            "Authorization": "Bearer secret123",
            "Content-Type": "application/json",
            "X-Auth-Token": "token456"
        ]

        let redacted = SensitiveDataRedactor.redactHeaders(headers)

        #expect(redacted["Authorization"] == "Bearer [REDACTED]")
        #expect(redacted["Content-Type"] == "application/json")
        #expect(redacted["X-Auth-Token"] == "[REDACTED]")
    }
}
