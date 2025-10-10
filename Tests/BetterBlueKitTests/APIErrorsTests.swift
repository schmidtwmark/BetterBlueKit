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
    
    // MARK: - HyundaiKiaAPIError Basic Tests
    
    @Test("HyundaiKiaAPIError basic creation")
    func testHyundaiKiaAPIErrorCreation() {
        let error = HyundaiKiaAPIError(
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
    
    @Test("HyundaiKiaAPIError creation with defaults")
    func testHyundaiKiaAPIErrorDefaults() {
        let error = HyundaiKiaAPIError(message: "Simple error")
        
        #expect(error.message == "Simple error")
        #expect(error.code == nil)
        #expect(error.apiName == nil)
        #expect(error.errorType == .general)
    }
    
    @Test("HyundaiKiaAPIError ErrorType cases")
    func testErrorTypeCases() {
        let errorTypes: [HyundaiKiaAPIError.ErrorType] = [
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
        #expect(HyundaiKiaAPIError.ErrorType.general.rawValue == "general")
        #expect(HyundaiKiaAPIError.ErrorType.invalidVehicleSession.rawValue == "invalidVehicleSession")
        #expect(HyundaiKiaAPIError.ErrorType.invalidCredentials.rawValue == "invalidCredentials")
        #expect(HyundaiKiaAPIError.ErrorType.serverError.rawValue == "serverError")
        #expect(HyundaiKiaAPIError.ErrorType.invalidPin.rawValue == "invalidPin")
        #expect(HyundaiKiaAPIError.ErrorType.concurrentRequest.rawValue == "concurrentRequest")
        #expect(HyundaiKiaAPIError.ErrorType.failedRetryLogin.rawValue == "failedRetryLogin")
    }
    
    @Test("HyundaiKiaAPIError Codable")
    func testHyundaiKiaAPIErrorCodable() throws {
        let original = HyundaiKiaAPIError(
            message: "Codable test error",
            code: 500,
            apiName: "CodableAPI",
            errorType: .serverError
        )
        
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HyundaiKiaAPIError.self, from: encoded)
        
        #expect(decoded.message == original.message)
        #expect(decoded.code == original.code)
        #expect(decoded.apiName == original.apiName)
        #expect(decoded.errorType == original.errorType)
    }
    
    // MARK: - Static Factory Methods Tests
    
    @Test("HyundaiKiaAPIError logError factory method")
    func testLogErrorFactoryMethod() {
        let error = HyundaiKiaAPIError.logError(
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
    
    @Test("HyundaiKiaAPIError invalidVehicleSession factory method")
    func testInvalidVehicleSessionFactoryMethod() {
        let error = HyundaiKiaAPIError.invalidVehicleSession("Custom vehicle session error", apiName: "VehicleAPI")
        
        #expect(error.message == "Custom vehicle session error")
        #expect(error.code == 1005)
        #expect(error.apiName == "VehicleAPI")
        #expect(error.errorType == .invalidVehicleSession)
    }
    
    @Test("HyundaiKiaAPIError invalidVehicleSession factory method with defaults")
    func testInvalidVehicleSessionFactoryMethodDefaults() {
        let error = HyundaiKiaAPIError.invalidVehicleSession()
        
        #expect(error.message == "Invalid vehicle for current session")
        #expect(error.code == 1005)
        #expect(error.apiName == nil)
        #expect(error.errorType == .invalidVehicleSession)
    }
    
    @Test("HyundaiKiaAPIError invalidCredentials factory method")
    func testInvalidCredentialsFactoryMethod() {
        let error = HyundaiKiaAPIError.invalidCredentials("Wrong username or password", apiName: "AuthAPI")
        
        #expect(error.message == "Wrong username or password")
        #expect(error.code == 401)
        #expect(error.apiName == "AuthAPI")
        #expect(error.errorType == .invalidCredentials)
    }
    
    @Test("HyundaiKiaAPIError invalidCredentials factory method with defaults")
    func testInvalidCredentialsFactoryMethodDefaults() {
        let error = HyundaiKiaAPIError.invalidCredentials()
        
        #expect(error.message == "Invalid username or password")
        #expect(error.code == 401)
        #expect(error.apiName == nil)
        #expect(error.errorType == .invalidCredentials)
    }
    
    @Test("HyundaiKiaAPIError serverError factory method")
    func testServerErrorFactoryMethod() {
        let error = HyundaiKiaAPIError.serverError("Custom server error", apiName: "ServerAPI")
        
        #expect(error.message == "Custom server error")
        #expect(error.code == 502)
        #expect(error.apiName == "ServerAPI")
        #expect(error.errorType == .serverError)
    }
    
    @Test("HyundaiKiaAPIError serverError factory method with defaults")
    func testServerErrorFactoryMethodDefaults() {
        let error = HyundaiKiaAPIError.serverError()
        
        #expect(error.message == "Server temporarily unavailable")
        #expect(error.code == 502)
        #expect(error.apiName == nil)
        #expect(error.errorType == .serverError)
    }
    
    @Test("HyundaiKiaAPIError invalidPin factory method")
    func testInvalidPinFactoryMethod() {
        let error = HyundaiKiaAPIError.invalidPin("PIN is incorrect", apiName: "PinAPI")
        
        #expect(error.message == "PIN is incorrect")
        #expect(error.code == nil)
        #expect(error.apiName == "PinAPI")
        #expect(error.errorType == .invalidPin)
    }
    
    @Test("HyundaiKiaAPIError concurrentRequest factory method")
    func testConcurrentRequestFactoryMethod() {
        let error = HyundaiKiaAPIError.concurrentRequest("Custom concurrent request error", apiName: "ConcurrentAPI")
        
        #expect(error.message == "Custom concurrent request error")
        #expect(error.code == 502)
        #expect(error.apiName == "ConcurrentAPI")
        #expect(error.errorType == .concurrentRequest)
    }
    
    @Test("HyundaiKiaAPIError concurrentRequest factory method with defaults")
    func testConcurrentRequestFactoryMethodDefaults() {
        let error = HyundaiKiaAPIError.concurrentRequest()
        
        #expect(error.message == "Another request is already in progress. Please wait and try again.")
        #expect(error.code == 502)
        #expect(error.apiName == nil)
        #expect(error.errorType == .concurrentRequest)
    }
    
    @Test("HyundaiKiaAPIError failedRetryLogin factory method")
    func testFailedRetryLoginFactoryMethod() {
        let error = HyundaiKiaAPIError.failedRetryLogin("Custom retry login error", apiName: "RetryAPI")
        
        #expect(error.message == "Custom retry login error")
        #expect(error.code == 502)
        #expect(error.apiName == "RetryAPI")
        #expect(error.errorType == .failedRetryLogin)
    }
    
    @Test("HyundaiKiaAPIError failedRetryLogin factory method with defaults")
    func testFailedRetryLoginFactoryMethodDefaults() {
        let error = HyundaiKiaAPIError.failedRetryLogin()
        
        #expect(error.message == "Failed to reauthenticate")
        #expect(error.code == 502)
        #expect(error.apiName == nil)
        #expect(error.errorType == .failedRetryLogin)
    }
    
    // MARK: - Error Protocol Conformance Tests
    
    @Test("HyundaiKiaAPIError as Error")
    func testHyundaiKiaAPIErrorAsError() {
        let error: Error = HyundaiKiaAPIError(message: "Test error")
        
        #expect(error is HyundaiKiaAPIError)
        
        if let apiError = error as? HyundaiKiaAPIError {
            #expect(apiError.message == "Test error")
        } else {
            #expect(Bool(false), "Should be able to cast to HyundaiKiaAPIError")
        }
    }
    
    @Test("HyundaiKiaAPIError in throwing context")
    func testHyundaiKiaAPIErrorInThrowingContext() async {
        func throwError() throws {
            throw HyundaiKiaAPIError.invalidCredentials("Test credentials error")
        }
        
        do {
            try throwError()
            #expect(Bool(false), "Should have thrown an error")
        } catch let error as HyundaiKiaAPIError {
            #expect(error.errorType == .invalidCredentials)
            #expect(error.message == "Test credentials error")
        } catch {
            #expect(Bool(false), "Should have thrown HyundaiKiaAPIError")
        }
    }
    
    // MARK: - ErrorType Codable Tests
    
    @Test("ErrorType Codable")
    func testErrorTypeCodable() throws {
        let errorTypes: [HyundaiKiaAPIError.ErrorType] = [
            .general, .invalidVehicleSession, .invalidCredentials,
            .serverError, .invalidPin, .concurrentRequest, .failedRetryLogin
        ]
        
        for errorType in errorTypes {
            let encoded = try JSONEncoder().encode(errorType)
            let decoded = try JSONDecoder().decode(HyundaiKiaAPIError.ErrorType.self, from: encoded)
            #expect(decoded == errorType)
        }
    }
    
    // MARK: - Edge Cases
    
    @Test("HyundaiKiaAPIError with empty message")
    func testHyundaiKiaAPIErrorEmptyMessage() {
        let error = HyundaiKiaAPIError(message: "")
        
        #expect(error.message == "")
        #expect(error.code == nil)
        #expect(error.errorType == .general)
    }
    
    @Test("HyundaiKiaAPIError with very long message")
    func testHyundaiKiaAPIErrorLongMessage() {
        let longMessage = String(repeating: "A", count: 1000)
        let error = HyundaiKiaAPIError(message: longMessage)
        
        #expect(error.message == longMessage)
        #expect(error.message.count == 1000)
    }
    
    @Test("HyundaiKiaAPIError with negative error code")
    func testHyundaiKiaAPIErrorNegativeCode() {
        let error = HyundaiKiaAPIError(message: "Negative code test", code: -1)
        
        #expect(error.code == -1)
        #expect(error.message == "Negative code test")
    }
    
    @Test("HyundaiKiaAPIError with zero error code")
    func testHyundaiKiaAPIErrorZeroCode() {
        let error = HyundaiKiaAPIError(message: "Zero code test", code: 0)
        
        #expect(error.code == 0)
        #expect(error.message == "Zero code test")
    }
    
    @Test("HyundaiKiaAPIError with special characters in message")
    func testHyundaiKiaAPIErrorSpecialCharacters() {
        let specialMessage = "Error with special chars: äöü ñ 中文 🚗 💨"
        let error = HyundaiKiaAPIError(message: specialMessage)
        
        #expect(error.message == specialMessage)
    }
    
    @Test("HyundaiKiaAPIError with special characters in apiName")
    func testHyundaiKiaAPIErrorSpecialCharactersInAPIName() {
        let specialAPIName = "API-Name_With.Special@Chars#123"
        let error = HyundaiKiaAPIError(message: "Test", apiName: specialAPIName)
        
        #expect(error.apiName == specialAPIName)
    }
}