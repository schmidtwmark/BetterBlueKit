//
//  APIErrorsTests.swift
//  BetterBlueKit
//
//  API error handling tests
//

import Foundation
import Testing
@testable import BetterBlueKit

@Suite("API Errors Tests")
struct APIErrorsTests {

    // MARK: - APIError Basic Tests

    @Test("APIError basic creation")
    func testAPIErrorCreation() {
        let error = APIError(
            message: "Test error message",
            code: 400,
            apiName: "TestAPI",
            errorType: .general
        )

        #expect(error.message == "Test error message")
        #expect(error.code == 400)
        #expect(error.apiName == "TestAPI")
        #expect(error.errorType == .general)
    }

    @Test("APIError creation with defaults")
    func testAPIErrorDefaults() {
        let error = APIError(message: "Simple error")

        #expect(error.message == "Simple error")
        #expect(error.code == nil)
        #expect(error.apiName == nil)
        #expect(error.errorType == .general)
    }

    @Test("APIError ErrorType cases")
    func testErrorTypeCases() {
        let errorTypes: [APIError.ErrorType] = [
            .general,
            .invalidVehicleSession,
            .invalidCredentials,
            .serverError,
            .invalidPin,
            .concurrentRequest,
            .failedRetryLogin
        ]

        // Test that all cases are valid
        #expect(errorTypes.count == 7)

        // Test raw values
        #expect(APIError.ErrorType.general.rawValue == "general")
        #expect(APIError.ErrorType.invalidVehicleSession.rawValue == "invalidVehicleSession")
        #expect(APIError.ErrorType.invalidCredentials.rawValue == "invalidCredentials")
        #expect(APIError.ErrorType.serverError.rawValue == "serverError")
        #expect(APIError.ErrorType.invalidPin.rawValue == "invalidPin")
        #expect(APIError.ErrorType.concurrentRequest.rawValue == "concurrentRequest")
        #expect(APIError.ErrorType.failedRetryLogin.rawValue == "failedRetryLogin")
    }

    @Test("APIError Codable")
    func testAPIErrorCodable() throws {
        let original = APIError(
            message: "Codable test error",
            code: 500,
            apiName: "CodableAPI",
            errorType: .serverError
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(APIError.self, from: encoded)

        #expect(decoded.message == original.message)
        #expect(decoded.code == original.code)
        #expect(decoded.apiName == original.apiName)
        #expect(decoded.errorType == original.errorType)
    }

    // MARK: - Static Factory Methods Tests

    @Test("APIError logError factory method")
    func testLogErrorFactoryMethod() {
        let error = APIError.logError(
            "Log error test",
            code: 404,
            apiName: "LogAPI",
            errorType: .invalidVehicleSession
        )

        #expect(error.message == "Log error test")
        #expect(error.code == 404)
        #expect(error.apiName == "LogAPI")
        #expect(error.errorType == .invalidVehicleSession)
    }

    @Test("APIError invalidVehicleSession factory method")
    func testInvalidVehicleSessionFactoryMethod() {
        let error = APIError.invalidVehicleSession("Custom vehicle session error", apiName: "VehicleAPI")

        #expect(error.message == "Custom vehicle session error")
        #expect(error.code == 1005)
        #expect(error.apiName == "VehicleAPI")
        #expect(error.errorType == .invalidVehicleSession)
    }

    @Test("APIError invalidVehicleSession factory method with defaults")
    func testInvalidVehicleSessionFactoryMethodDefaults() {
        let error = APIError.invalidVehicleSession()

        #expect(error.message == "Invalid vehicle for current session")
        #expect(error.code == 1005)
        #expect(error.apiName == nil)
        #expect(error.errorType == .invalidVehicleSession)
    }

    @Test("APIError invalidCredentials factory method")
    func testInvalidCredentialsFactoryMethod() {
        let error = APIError.invalidCredentials("Wrong username or password", apiName: "AuthAPI")

        #expect(error.message == "Wrong username or password")
        #expect(error.code == 401)
        #expect(error.apiName == "AuthAPI")
        #expect(error.errorType == .invalidCredentials)
    }

    @Test("APIError invalidCredentials factory method with defaults")
    func testInvalidCredentialsFactoryMethodDefaults() {
        let error = APIError.invalidCredentials()

        #expect(error.message == "Invalid username or password")
        #expect(error.code == 401)
        #expect(error.apiName == nil)
        #expect(error.errorType == .invalidCredentials)
    }

    @Test("APIError serverError factory method")
    func testServerErrorFactoryMethod() {
        let error = APIError.serverError("Custom server error", apiName: "ServerAPI")

        #expect(error.message == "Custom server error")
        #expect(error.code == 502)
        #expect(error.apiName == "ServerAPI")
        #expect(error.errorType == .serverError)
    }

    @Test("APIError serverError factory method with defaults")
    func testServerErrorFactoryMethodDefaults() {
        let error = APIError.serverError()

        #expect(error.message == "Server temporarily unavailable")
        #expect(error.code == 502)
        #expect(error.apiName == nil)
        #expect(error.errorType == .serverError)
    }

    @Test("APIError invalidPin factory method")
    func testInvalidPinFactoryMethod() {
        let error = APIError.invalidPin("PIN is incorrect", apiName: "PinAPI")

        #expect(error.message == "PIN is incorrect")
        #expect(error.code == nil)
        #expect(error.apiName == "PinAPI")
        #expect(error.errorType == .invalidPin)
    }

    @Test("APIError concurrentRequest factory method")
    func testConcurrentRequestFactoryMethod() {
        let error = APIError.concurrentRequest("Custom concurrent request error", apiName: "ConcurrentAPI")

        #expect(error.message == "Custom concurrent request error")
        #expect(error.code == 502)
        #expect(error.apiName == "ConcurrentAPI")
        #expect(error.errorType == .concurrentRequest)
    }

    @Test("APIError concurrentRequest factory method with defaults")
    func testConcurrentRequestFactoryMethodDefaults() {
        let error = APIError.concurrentRequest()

        #expect(error.message == "Another request is already in progress. Please wait and try again.")
        #expect(error.code == 502)
        #expect(error.apiName == nil)
        #expect(error.errorType == .concurrentRequest)
    }

    @Test("APIError failedRetryLogin factory method")
    func testFailedRetryLoginFactoryMethod() {
        let error = APIError.failedRetryLogin("Custom retry login error", apiName: "RetryAPI")

        #expect(error.message == "Custom retry login error")
        #expect(error.code == 502)
        #expect(error.apiName == "RetryAPI")
        #expect(error.errorType == .failedRetryLogin)
    }

    @Test("APIError failedRetryLogin factory method with defaults")
    func testFailedRetryLoginFactoryMethodDefaults() {
        let error = APIError.failedRetryLogin()

        #expect(error.message == "Failed to reauthenticate")
        #expect(error.code == 502)
        #expect(error.apiName == nil)
        #expect(error.errorType == .failedRetryLogin)
    }

    // MARK: - Error Protocol Conformance Tests

    @Test("APIError as Error")
    func testAPIErrorAsError() {
        let error: Error = APIError(message: "Test error")

        #expect(error is APIError)

        if let apiError = error as? APIError {
            #expect(apiError.message == "Test error")
        } else {
            #expect(Bool(false), "Should be able to cast to APIError")
        }
    }

    @Test("APIError in throwing context")
    func testAPIErrorInThrowingContext() async {
        func throwError() throws {
            throw APIError.invalidCredentials("Test credentials error")
        }

        do {
            try throwError()
            #expect(Bool(false), "Should have thrown an error")
        } catch let error as APIError {
            #expect(error.errorType == .invalidCredentials)
            #expect(error.message == "Test credentials error")
        } catch {
            #expect(Bool(false), "Should have thrown APIError")
        }
    }

    // MARK: - ErrorType Codable Tests

    @Test("ErrorType Codable")
    func testErrorTypeCodable() throws {
        let errorTypes: [APIError.ErrorType] = [
            .general, .invalidVehicleSession, .invalidCredentials,
            .serverError, .invalidPin, .concurrentRequest, .failedRetryLogin
        ]

        for errorType in errorTypes {
            let encoded = try JSONEncoder().encode(errorType)
            let decoded = try JSONDecoder().decode(APIError.ErrorType.self, from: encoded)
            #expect(decoded == errorType)
        }
    }

    // MARK: - Edge Cases

    @Test("APIError with empty message")
    func testAPIErrorEmptyMessage() {
        let error = APIError(message: "")

        #expect(error.message == "")
        #expect(error.code == nil)
        #expect(error.errorType == .general)
    }

    @Test("APIError with very long message")
    func testAPIErrorLongMessage() {
        let longMessage = String(repeating: "A", count: 1000)
        let error = APIError(message: longMessage)

        #expect(error.message == longMessage)
        #expect(error.message.count == 1000)
    }

    @Test("APIError with negative error code")
    func testAPIErrorNegativeCode() {
        let error = APIError(message: "Negative code test", code: -1)

        #expect(error.code == -1)
        #expect(error.message == "Negative code test")
    }

    @Test("APIError with zero error code")
    func testAPIErrorZeroCode() {
        let error = APIError(message: "Zero code test", code: 0)

        #expect(error.code == 0)
        #expect(error.message == "Zero code test")
    }

    @Test("APIError with special characters in message")
    func testAPIErrorSpecialCharacters() {
        let specialMessage = "Error with special chars: äöü ñ 中文 🚗 💨"
        let error = APIError(message: specialMessage)

        #expect(error.message == specialMessage)
    }

    @Test("APIError with special characters in apiName")
    func testAPIErrorSpecialCharactersInAPIName() {
        let specialAPIName = "API-Name_With.Special@Chars#123"
        let error = APIError(message: "Test", apiName: specialAPIName)

        #expect(error.apiName == specialAPIName)
    }
}
