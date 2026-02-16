//
//  APIClientErrorHandlingTests.swift
//  BetterBlueKit
//
//  Unit tests for API error handling
//
//  Note: Tests for internal APIClient methods have been removed as these
//  are now private implementation details. This file retains tests for
//  public error types and behavior.
//

import Foundation
import Testing
@testable import BetterBlueKit

@Suite("API Error Handling Tests")
struct APIClientErrorHandlingTests {

    // MARK: - APIError Tests

    @Test("APIError creation with all fields")
    func testAPIErrorCreation() {
        let error = APIError(
            message: "Test error",
            code: 401,
            apiName: "TestAPI",
            errorType: .invalidCredentials,
            userInfo: ["key": "value"]
        )

        #expect(error.message == "Test error")
        #expect(error.code == 401)
        #expect(error.apiName == "TestAPI")
        #expect(error.errorType == .invalidCredentials)
        #expect(error.userInfo?["key"] == "value")
    }

    @Test("APIError default values")
    func testAPIErrorDefaults() {
        let error = APIError(message: "Simple error")

        #expect(error.message == "Simple error")
        #expect(error.code == nil)
        #expect(error.apiName == nil)
        #expect(error.errorType == .general)
        #expect(error.userInfo == nil)
    }

    @Test("APIError convenience initializers")
    func testAPIErrorConvenienceInitializers() {
        let invalidCreds = APIError.invalidCredentials("Bad password", apiName: "Test")
        #expect(invalidCreds.errorType == .invalidCredentials)
        #expect(invalidCreds.message == "Bad password")

        let invalidPin = APIError.invalidPin("Wrong PIN", apiName: "Test")
        #expect(invalidPin.errorType == .invalidPin)

        let serverError = APIError.serverError("Server down", apiName: "Test")
        #expect(serverError.errorType == .serverError)

        let vehicleSession = APIError.invalidVehicleSession("Session expired", apiName: "Test")
        #expect(vehicleSession.errorType == .invalidVehicleSession)

        let regionNotSupported = APIError.regionNotSupported("Not available", apiName: "Test")
        #expect(regionNotSupported.errorType == .regionNotSupported)
    }

    @Test("APIError requiresMFA with all fields")
    func testAPIErrorRequiresMFA() {
        let error = APIError.requiresMFA(
            xid: "xid123",
            otpKey: "otp456",
            hasEmail: true,
            hasPhone: false,
            email: "test@example.com",
            phone: nil,
            rmTokenExpired: true,
            apiName: "KiaUSA"
        )

        #expect(error.errorType == .requiresMFA)
        #expect(error.userInfo?["xid"] == "xid123")
        #expect(error.userInfo?["otpKey"] == "otp456")
        #expect(error.userInfo?["hasEmail"] == "true")
        #expect(error.userInfo?["hasPhone"] == "false")
        #expect(error.userInfo?["email"] == "test@example.com")
        #expect(error.userInfo?["rmTokenExpired"] == "true")
    }

    // MARK: - APIError.ErrorType Tests

    @Test("ErrorType has expected cases")
    func testErrorTypeCases() {
        let allTypes: [APIError.ErrorType] = [
            .general,
            .invalidVehicleSession,
            .invalidCredentials,
            .serverError,
            .invalidPin,
            .concurrentRequest,
            .failedRetryLogin,
            .requiresMFA,
            .kiaInvalidRequest,
            .regionNotSupported
        ]

        // Verify all types are unique
        let uniqueTypes = Set(allTypes.map(\.rawValue))
        #expect(uniqueTypes.count == allTypes.count)
    }

    // MARK: - RegionSupportError Tests

    @Test("RegionSupportError creation")
    func testRegionSupportErrorCreation() {
        let error = RegionSupportError.unsupportedRegion(brand: .hyundai, region: .canada)

        switch error {
        case .unsupportedRegion(let brand, let region):
            #expect(brand == .hyundai)
            #expect(region == .canada)
        }
    }

    @Test("RegionSupportError localizedDescription")
    func testRegionSupportErrorDescription() {
        let error = RegionSupportError.unsupportedRegion(brand: .kia, region: .australia)
        let description = error.localizedDescription.lowercased()

        #expect(description.contains("kia"))
        // Region can appear as "australia" or "au"
        #expect(description.contains("au"))
    }

    // MARK: - Error Codability Tests

    @Test("APIError is Codable")
    func testAPIErrorCodable() throws {
        let original = APIError(
            message: "Test message",
            code: 500,
            apiName: "TestAPI",
            errorType: .serverError,
            userInfo: ["key": "value"]
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(APIError.self, from: encoded)

        #expect(decoded.message == original.message)
        #expect(decoded.code == original.code)
        #expect(decoded.apiName == original.apiName)
        #expect(decoded.errorType == original.errorType)
        #expect(decoded.userInfo?["key"] == original.userInfo?["key"])
    }

    @Test("APIError.ErrorType is Codable")
    func testErrorTypeCodable() throws {
        let allTypes: [APIError.ErrorType] = [
            .general, .invalidVehicleSession, .invalidCredentials,
            .serverError, .invalidPin, .concurrentRequest,
            .failedRetryLogin, .requiresMFA, .kiaInvalidRequest,
            .regionNotSupported
        ]

        for errorType in allTypes {
            let encoded = try JSONEncoder().encode(errorType)
            let decoded = try JSONDecoder().decode(APIError.ErrorType.self, from: encoded)
            #expect(decoded == errorType)
        }
    }
}
