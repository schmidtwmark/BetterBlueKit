//
//  AdvancedErrorHandlingTests.swift
//  BetterBlueKit
//
//  Advanced error scenarios and edge cases
//

import Foundation
import Testing
@testable import BetterBlueKit

@Suite("Advanced Error Handling Tests")
struct AdvancedErrorHandlingTests {

    // MARK: - API Error Type Tests

    @Test("APIError types are correctly identified")
    func testAPIErrorTypes() {
        let invalidCredentials = APIError.invalidCredentials("Bad credentials", apiName: "Test")
        #expect(invalidCredentials.errorType == .invalidCredentials)
        #expect(invalidCredentials.apiName == "Test")

        let invalidPin = APIError.invalidPin("Wrong PIN", apiName: "Test")
        #expect(invalidPin.errorType == .invalidPin)

        let serverError = APIError.serverError("Server down", apiName: "Test")
        #expect(serverError.errorType == .serverError)

        let regionNotSupported = APIError.regionNotSupported("Not available", apiName: "Test")
        #expect(regionNotSupported.errorType == .regionNotSupported)

        let invalidVehicleSession = APIError.invalidVehicleSession("Session expired", apiName: "Test")
        #expect(invalidVehicleSession.errorType == .invalidVehicleSession)
    }

    @Test("MFA required error contains correct user info")
    func testMFARequiredError() {
        let error = APIError.requiresMFA(
            xid: "xid123",
            otpKey: "otp456",
            hasEmail: true,
            hasPhone: false,
            email: "test@example.com",
            phone: nil,
            rmTokenExpired: false,
            apiName: "KiaUSA"
        )

        #expect(error.errorType == .requiresMFA)
        #expect(error.userInfo?["xid"] == "xid123")
        #expect(error.userInfo?["otpKey"] == "otp456")
        #expect(error.userInfo?["hasEmail"] == "true")
        #expect(error.userInfo?["hasPhone"] == "false")
        #expect(error.userInfo?["email"] == "test@example.com")
        #expect(error.userInfo?["phone"] == nil)
    }

    // MARK: - HTTPLog Tests

    @Test("HTTPLog success detection")
    func testHTTPLogSuccessDetection() {
        let successLog = HTTPLog(
            timestamp: Date(),
            accountId: UUID(),
            requestType: .fetchVehicles,
            method: "GET",
            url: "https://example.com/api/vehicles",
            requestHeaders: [:],
            requestBody: nil,
            responseStatus: 200,
            responseHeaders: [:],
            responseBody: "[]",
            error: nil,
            duration: 0.5
        )

        #expect(successLog.isSuccess == true)
        #expect(successLog.statusText.contains("200"))
    }

    @Test("HTTPLog error detection")
    func testHTTPLogErrorDetection() {
        let errorLog = HTTPLog(
            timestamp: Date(),
            accountId: UUID(),
            requestType: .login,
            method: "POST",
            url: "https://example.com/api/login",
            requestHeaders: [:],
            requestBody: nil,
            responseStatus: 401,
            responseHeaders: [:],
            responseBody: nil,
            error: "Unauthorized",
            duration: 0.3
        )

        #expect(errorLog.isSuccess == false)
        #expect(errorLog.statusText.contains("401"))
    }

    @Test("HTTPLog timeout characteristics")
    func testHTTPLogTimeoutCharacteristics() {
        let timeoutLog = HTTPLog(
            timestamp: Date(),
            accountId: UUID(),
            requestType: .sendCommand,
            method: "POST",
            url: "https://example.com/api/timeout",
            requestHeaders: ["Content-Type": "application/json"],
            requestBody: "{}",
            responseStatus: nil,
            responseHeaders: [:],
            responseBody: nil,
            error: "Request timeout",
            duration: 30.0
        )

        #expect(timeoutLog.responseStatus == nil)
        #expect(timeoutLog.isSuccess == false)
        #expect(timeoutLog.statusText == "Error")
        #expect(timeoutLog.duration >= 30.0)
        #expect(timeoutLog.formattedDuration.contains("30"))
    }

    @Test("HTTPLog duration formatting")
    func testHTTPLogDurationFormatting() {
        let quickLog = HTTPLog(
            timestamp: Date(),
            accountId: UUID(),
            requestType: .fetchVehicleStatus,
            method: "GET",
            url: "https://example.com/api/status",
            requestHeaders: [:],
            requestBody: nil,
            responseStatus: 200,
            responseHeaders: [:],
            responseBody: "{}",
            error: nil,
            duration: 0.123
        )

        #expect(quickLog.formattedDuration.contains("123") || quickLog.formattedDuration.contains("0.12"))
    }

    // MARK: - JSON Edge Cases

    @Test("Deeply nested JSON handling")
    func testDeeplyNestedJSONHandling() throws {
        let nestedJSON = """
        {
          "level1": {
            "level2": {
              "level3": {
                "level4": {
                  "level5": {
                    "level6": {
                      "level7": {
                        "level8": {
                          "level9": {
                            "level10": {
                              "data": "deep_value"
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
        """

        let data = Data(nestedJSON.utf8)

        let startTime = Date()
        let json = try JSONSerialization.jsonObject(with: data)
        let endTime = Date()

        #expect(json is [String: Any])
        #expect(endTime.timeIntervalSince(startTime) < 0.1)
    }

    @Test("Different JSON encoding formats parse identically")
    func testDifferentJSONEncodingFormats() throws {
        let compactJSON = """
        {"key":"value","number":123,"nested":{"inner":"data"}}
        """

        let prettyJSON = """
        {
          "key" : "value",
          "number" : 123,
          "nested" : {
            "inner" : "data"
          }
        }
        """

        let compactData = Data(compactJSON.utf8)
        let prettyData = Data(prettyJSON.utf8)

        let compact = try JSONSerialization.jsonObject(with: compactData) as? [String: Any]
        let pretty = try JSONSerialization.jsonObject(with: prettyData) as? [String: Any]

        #expect(compact?["key"] as? String == pretty?["key"] as? String)
        #expect(compact?["number"] as? Int == pretty?["number"] as? Int)

        let compactNested = compact?["nested"] as? [String: Any]
        let prettyNested = pretty?["nested"] as? [String: Any]
        #expect(compactNested?["inner"] as? String == prettyNested?["inner"] as? String)
    }

    // MARK: - Error Message Tests

    @Test("Invalid credentials error message")
    func testInvalidCredentialsErrorMessage() {
        let error = APIError.invalidCredentials("Invalid username or password", apiName: "TestAPI")

        #expect(error.message.contains("Invalid username or password"))
        #expect(error.apiName == "TestAPI")
    }

    @Test("Session expired error message")
    func testSessionExpiredErrorMessage() {
        let error = APIError.invalidCredentials(
            "Session Key is either invalid or expired",
            apiName: "KiaUSA"
        )

        #expect(error.errorType == .invalidCredentials)
        #expect(error.message.lowercased().contains("session"))
        #expect(error.message.lowercased().contains("expired"))
    }

    @Test("Invalid PIN error with attempt count")
    func testInvalidPINErrorWithAttemptCount() {
        let error = APIError.invalidPin("Invalid PIN, 2 attempts remaining", apiName: "HyundaiUSA")

        #expect(error.errorType == .invalidPin)
        #expect(error.message.contains("2 attempts remaining"))
    }

    // MARK: - Kia-specific Error Tests

    @Test("Kia invalid request error")
    func testKiaInvalidRequestError() {
        let error = APIError.kiaInvalidRequest(
            "Kia API is currently unsupported",
            apiName: "KiaUSA"
        )

        #expect(error.errorType == .kiaInvalidRequest)
        #expect(error.message.contains("unsupported"))
    }

    // MARK: - Region Support Error Tests

    @Test("APIError.regionNotSupported for unsupported region")
    func testRegionNotSupportedError() {
        let error = APIError.regionNotSupported(
            "\(Brand.hyundai.displayName) is not yet supported in \(Region.canada.rawValue)"
        )

        #expect(error.errorType == .regionNotSupported)
        #expect(error.message.lowercased().contains("hyundai"))
        #expect(error.message.lowercased().contains("ca") || error.message.lowercased().contains("canada"))
    }

    // MARK: - Error Logging Tests

    @Test("APIError logs error correctly")
    func testAPIErrorLogsCorrectly() {
        // This tests that logError doesn't crash and returns an error
        let error = APIError.logError("Test error message", apiName: "TestClient")

        #expect(error.message == "Test error message")
        #expect(error.apiName == "TestClient")
        #expect(error.errorType == .general)
    }
}
