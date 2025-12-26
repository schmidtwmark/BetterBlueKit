//
//  HTTPLoggingTests.swift
//  BetterBlueKit
//
//  HTTP logging models tests
//

import Foundation
import Testing
@testable import BetterBlueKit

@Suite("HTTP Logging Tests")
struct HTTPLoggingTests {

    // MARK: - HTTPRequestType Tests

    @Test("HTTPRequestType all cases")
    func testHTTPRequestTypeAllCases() {
        let allCases = HTTPRequestType.allCases
        #expect(allCases.count == 4)
        #expect(allCases.contains(.login))
        #expect(allCases.contains(.fetchVehicles))
        #expect(allCases.contains(.fetchVehicleStatus))
        #expect(allCases.contains(.sendCommand))
    }

    @Test("HTTPRequestType display names")
    func testHTTPRequestTypeDisplayNames() {
        #expect(HTTPRequestType.login.displayName == "Login")
        #expect(HTTPRequestType.fetchVehicles.displayName == "Fetch Vehicles")
        #expect(HTTPRequestType.fetchVehicleStatus.displayName == "Fetch Status")
        #expect(HTTPRequestType.sendCommand.displayName == "Send Command")
    }

    @Test("HTTPRequestType raw values")
    func testHTTPRequestTypeRawValues() {
        #expect(HTTPRequestType.login.rawValue == "login")
        #expect(HTTPRequestType.fetchVehicles.rawValue == "fetchVehicles")
        #expect(HTTPRequestType.fetchVehicleStatus.rawValue == "fetchVehicleStatus")
        #expect(HTTPRequestType.sendCommand.rawValue == "sendCommand")
    }

    @Test("HTTPRequestType Codable")
    func testHTTPRequestTypeCodable() throws {
        let requestTypes = HTTPRequestType.allCases

        for requestType in requestTypes {
            let encoded = try JSONEncoder().encode(requestType)
            let decoded = try JSONDecoder().decode(HTTPRequestType.self, from: encoded)
            #expect(decoded == requestType)
        }
    }

    // MARK: - HTTPLog Tests

    @Test("HTTPLog creation with all parameters")
    func testHTTPLogCreation() {
        let timestamp = Date()
        let accountId = UUID()
        let duration: TimeInterval = 1.5

        let log = HTTPLog(
            timestamp: timestamp,
            accountId: accountId,
            requestType: .login,
            method: "POST",
            url: "https://api.example.com/login",
            requestHeaders: ["Authorization": "Bearer token", "Content-Type": "application/json"],
            requestBody: "{\"username\":\"test\"}",
            responseStatus: 200,
            responseHeaders: ["Content-Type": "application/json"],
            responseBody: "{\"success\":true}",
            error: nil,
            apiError: nil,
            duration: duration,
            stackTrace: "Stack trace here"
        )

        #expect(log.timestamp == timestamp)
        #expect(log.accountId == accountId)
        #expect(log.requestType == .login)
        #expect(log.method == "POST")
        #expect(log.url == "https://api.example.com/login")
        #expect(log.requestHeaders["Authorization"] == "Bearer token")
        #expect(log.requestBody == "{\"username\":\"test\"}")
        #expect(log.responseStatus == 200)
        #expect(log.responseHeaders["Content-Type"] == "application/json")
        #expect(log.responseBody == "{\"success\":true}")
        #expect(log.error == nil)
        #expect(log.apiError == nil)
        #expect(log.duration == duration)
        #expect(log.stackTrace == "Stack trace here")
    }

    @Test("HTTPLog creation with minimal parameters")
    func testHTTPLogCreationMinimal() {
        let timestamp = Date()
        let accountId = UUID()

        let log = HTTPLog(
            timestamp: timestamp,
            accountId: accountId,
            requestType: .fetchVehicles,
            method: "GET",
            url: "https://api.example.com/vehicles",
            requestHeaders: [:],
            requestBody: nil,
            responseStatus: nil,
            responseHeaders: [:],
            responseBody: nil,
            error: "Network error",
            duration: 0.5
        )

        #expect(log.timestamp == timestamp)
        #expect(log.accountId == accountId)
        #expect(log.requestType == .fetchVehicles)
        #expect(log.method == "GET")
        #expect(log.url == "https://api.example.com/vehicles")
        #expect(log.requestHeaders.isEmpty)
        #expect(log.requestBody == nil)
        #expect(log.responseStatus == nil)
        #expect(log.responseHeaders.isEmpty)
        #expect(log.responseBody == nil)
        #expect(log.error == "Network error")
        #expect(log.apiError == nil)
        #expect(log.duration == 0.5)
        #expect(log.stackTrace == nil)
    }

    @Test("HTTPLog statusText for successful response")
    func testHTTPLogStatusTextSuccess() {
        let log = HTTPLog(
            timestamp: Date(),
            accountId: UUID(),
            requestType: .login,
            method: "POST",
            url: "https://api.example.com/login",
            requestHeaders: [:],
            requestBody: nil,
            responseStatus: 200,
            responseHeaders: [:],
            responseBody: nil,
            error: nil,
            duration: 1.0
        )

        #expect(log.statusText == "200")
    }

    @Test("HTTPLog statusText for error response")
    func testHTTPLogStatusTextError() {
        let log = HTTPLog(
            timestamp: Date(),
            accountId: UUID(),
            requestType: .login,
            method: "POST",
            url: "https://api.example.com/login",
            requestHeaders: [:],
            requestBody: nil,
            responseStatus: 401,
            responseHeaders: [:],
            responseBody: nil,
            error: nil,
            duration: 1.0
        )

        #expect(log.statusText == "401")
    }

    @Test("HTTPLog statusText for API error")
    func testHTTPLogStatusTextAPIError() {
        let log = HTTPLog(
            timestamp: Date(),
            accountId: UUID(),
            requestType: .login,
            method: "POST",
            url: "https://api.example.com/login",
            requestHeaders: [:],
            requestBody: nil,
            responseStatus: 200,
            responseHeaders: [:],
            responseBody: nil,
            error: nil,
            apiError: "API Error 1001: Invalid token",
            duration: 1.0
        )

        #expect(log.statusText == "200 (API Error)")
    }

    @Test("HTTPLog statusText for network error")
    func testHTTPLogStatusTextNetworkError() {
        let log = HTTPLog(
            timestamp: Date(),
            accountId: UUID(),
            requestType: .login,
            method: "POST",
            url: "https://api.example.com/login",
            requestHeaders: [:],
            requestBody: nil,
            responseStatus: nil,
            responseHeaders: [:],
            responseBody: nil,
            error: "Network connection failed",
            duration: 1.0
        )

        #expect(log.statusText == "Error")
    }

    @Test("HTTPLog statusText for pending request")
    func testHTTPLogStatusTextPending() {
        let log = HTTPLog(
            timestamp: Date(),
            accountId: UUID(),
            requestType: .login,
            method: "POST",
            url: "https://api.example.com/login",
            requestHeaders: [:],
            requestBody: nil,
            responseStatus: nil,
            responseHeaders: [:],
            responseBody: nil,
            error: nil,
            duration: 1.0
        )

        #expect(log.statusText == "Pending")
    }

    @Test("HTTPLog isSuccess for successful response")
    func testHTTPLogIsSuccessTrue() {
        let log = HTTPLog(
            timestamp: Date(),
            accountId: UUID(),
            requestType: .fetchVehicles,
            method: "GET",
            url: "https://api.example.com/vehicles",
            requestHeaders: [:],
            requestBody: nil,
            responseStatus: 200,
            responseHeaders: [:],
            responseBody: nil,
            error: nil,
            duration: 1.0
        )

        #expect(log.isSuccess == true)
    }

    @Test("HTTPLog isSuccess for error responses")
    func testHTTPLogIsSuccessFalse() {
        // Test 400 error
        let log400 = HTTPLog(
            timestamp: Date(),
            accountId: UUID(),
            requestType: .login,
            method: "POST",
            url: "https://api.example.com/login",
            requestHeaders: [:],
            requestBody: nil,
            responseStatus: 400,
            responseHeaders: [:],
            responseBody: nil,
            error: nil,
            duration: 1.0
        )
        #expect(log400.isSuccess == false)

        // Test with network error
        let logNetworkError = HTTPLog(
            timestamp: Date(),
            accountId: UUID(),
            requestType: .login,
            method: "POST",
            url: "https://api.example.com/login",
            requestHeaders: [:],
            requestBody: nil,
            responseStatus: 200,
            responseHeaders: [:],
            responseBody: nil,
            error: "Network error",
            duration: 1.0
        )
        #expect(logNetworkError.isSuccess == false)

        // Test with API error
        let logAPIError = HTTPLog(
            timestamp: Date(),
            accountId: UUID(),
            requestType: .login,
            method: "POST",
            url: "https://api.example.com/login",
            requestHeaders: [:],
            requestBody: nil,
            responseStatus: 200,
            responseHeaders: [:],
            responseBody: nil,
            error: nil,
            apiError: "API Error",
            duration: 1.0
        )
        #expect(logAPIError.isSuccess == false)

        // Test pending request
        let logPending = HTTPLog(
            timestamp: Date(),
            accountId: UUID(),
            requestType: .login,
            method: "POST",
            url: "https://api.example.com/login",
            requestHeaders: [:],
            requestBody: nil,
            responseStatus: nil,
            responseHeaders: [:],
            responseBody: nil,
            error: nil,
            duration: 1.0
        )
        #expect(logPending.isSuccess == false)
    }

    @Test("HTTPLog formattedDuration")
    func testHTTPLogFormattedDuration() {
        let log1 = HTTPLog(
            timestamp: Date(),
            accountId: UUID(),
            requestType: .login,
            method: "POST",
            url: "https://api.example.com/login",
            requestHeaders: [:],
            requestBody: nil,
            responseStatus: 200,
            responseHeaders: [:],
            responseBody: nil,
            error: nil,
            duration: 1.5
        )
        #expect(log1.formattedDuration == "1.50s")

        let log2 = HTTPLog(
            timestamp: Date(),
            accountId: UUID(),
            requestType: .fetchVehicles,
            method: "GET",
            url: "https://api.example.com/vehicles",
            requestHeaders: [:],
            requestBody: nil,
            responseStatus: 200,
            responseHeaders: [:],
            responseBody: nil,
            error: nil,
            duration: 0.123
        )
        #expect(log2.formattedDuration == "0.12s")
    }

    @Test("HTTPLog preciseTimestamp")
    func testHTTPLogPreciseTimestamp() {
        // Create a specific date for consistent testing
        let calendar = Calendar.current
        let dateComponents = DateComponents(year: 2023, month: 10, day: 15, hour: 14, minute: 30, second: 25, nanosecond: 123_000_000)
        let specificDate = calendar.date(from: dateComponents)!

        let log = HTTPLog(
            timestamp: specificDate,
            accountId: UUID(),
            requestType: .login,
            method: "POST",
            url: "https://api.example.com/login",
            requestHeaders: [:],
            requestBody: nil,
            responseStatus: 200,
            responseHeaders: [:],
            responseBody: nil,
            error: nil,
            duration: 1.0
        )

        // The format should be HH:mm:ss.SSS
        #expect(log.preciseTimestamp == "14:30:25.123")
    }

    @Test("HTTPLog Codable")
    func testHTTPLogCodable() throws {
        let original = HTTPLog(
            timestamp: Date(),
            accountId: UUID(),
            requestType: .sendCommand,
            method: "POST",
            url: "https://api.example.com/command",
            requestHeaders: ["Authorization": "Bearer token"],
            requestBody: "{\"command\":\"lock\"}",
            responseStatus: 200,
            responseHeaders: ["Content-Type": "application/json"],
            responseBody: "{\"result\":\"success\"}",
            error: nil,
            apiError: nil,
            duration: 2.5,
            stackTrace: "Stack trace"
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HTTPLog.self, from: encoded)

        #expect(abs(decoded.timestamp.timeIntervalSince(original.timestamp)) < 1.0)
        #expect(decoded.accountId == original.accountId)
        #expect(decoded.requestType == original.requestType)
        #expect(decoded.method == original.method)
        #expect(decoded.url == original.url)
        #expect(decoded.requestHeaders == original.requestHeaders)
        #expect(decoded.requestBody == original.requestBody)
        #expect(decoded.responseStatus == original.responseStatus)
        #expect(decoded.responseHeaders == original.responseHeaders)
        #expect(decoded.responseBody == original.responseBody)
        #expect(decoded.error == original.error)
        #expect(decoded.apiError == original.apiError)
        #expect(decoded.duration == original.duration)
        #expect(decoded.stackTrace == original.stackTrace)
    }

    // MARK: - Edge Cases

    @Test("HTTPLog with very long duration")
    func testHTTPLogLongDuration() {
        let log = HTTPLog(
            timestamp: Date(),
            accountId: UUID(),
            requestType: .login,
            method: "POST",
            url: "https://api.example.com/login",
            requestHeaders: [:],
            requestBody: nil,
            responseStatus: 200,
            responseHeaders: [:],
            responseBody: nil,
            error: nil,
            duration: 123.456789
        )

        #expect(log.formattedDuration == "123.46s")
    }

    @Test("HTTPLog with zero duration")
    func testHTTPLogZeroDuration() {
        let log = HTTPLog(
            timestamp: Date(),
            accountId: UUID(),
            requestType: .login,
            method: "POST",
            url: "https://api.example.com/login",
            requestHeaders: [:],
            requestBody: nil,
            responseStatus: 200,
            responseHeaders: [:],
            responseBody: nil,
            error: nil,
            duration: 0.0
        )

        #expect(log.formattedDuration == "0.00s")
    }

    @Test("HTTPLog with empty headers and body")
    func testHTTPLogEmptyData() {
        let log = HTTPLog(
            timestamp: Date(),
            accountId: UUID(),
            requestType: .fetchVehicleStatus,
            method: "GET",
            url: "https://api.example.com/status",
            requestHeaders: [:],
            requestBody: "",
            responseStatus: 200,
            responseHeaders: [:],
            responseBody: "",
            error: nil,
            duration: 1.0
        )

        #expect(log.requestHeaders.isEmpty)
        #expect(log.requestBody == "")
        #expect(log.responseHeaders.isEmpty)
        #expect(log.responseBody == "")
        #expect(log.isSuccess == true)
    }
}
