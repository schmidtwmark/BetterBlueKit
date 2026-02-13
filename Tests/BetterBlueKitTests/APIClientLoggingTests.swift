//
//  APIClientLoggingTests.swift
//  BetterBlueKit
//
//  Unit tests for HTTP logging functionality
//
//  Note: Tests for internal APIClient methods (extractAPIError, logHTTPRequest)
//  have been removed as these are now private implementation details.
//  This file retains tests for the public HTTPLog model.
//

import Foundation
import Testing
@testable import BetterBlueKit

@Suite("HTTP Logging Tests")
struct APIClientLoggingTests {

    // MARK: - HTTPLog Tests

    @Test("HTTPLog creation with all fields")
    func testHTTPLogCreation() {
        let timestamp = Date()
        let accountId = UUID()

        let log = HTTPLog(
            timestamp: timestamp,
            accountId: accountId,
            requestType: .login,
            method: "POST",
            url: "https://example.com/login",
            requestHeaders: ["Authorization": "Bearer token"],
            requestBody: "{\"username\": \"test\"}",
            responseStatus: 200,
            responseHeaders: ["Content-Type": "application/json"],
            responseBody: "{\"success\": true}",
            error: nil,
            duration: 0.5
        )

        #expect(log.timestamp == timestamp)
        #expect(log.accountId == accountId)
        #expect(log.requestType == .login)
        #expect(log.method == "POST")
        #expect(log.url == "https://example.com/login")
        #expect(log.requestHeaders["Authorization"] == "Bearer token")
        #expect(log.requestBody == "{\"username\": \"test\"}")
        #expect(log.responseStatus == 200)
        #expect(log.responseHeaders["Content-Type"] == "application/json")
        #expect(log.responseBody == "{\"success\": true}")
        #expect(log.error == nil)
        #expect(log.duration == 0.5)
    }

    @Test("HTTPLog isSuccess for various status codes")
    func testHTTPLogIsSuccess() {
        let successCodes = [200, 201, 202, 204, 299]
        let failureCodes = [400, 401, 403, 404, 500, 502, 503]

        for code in successCodes {
            let log = createLog(status: code)
            #expect(log.isSuccess == true, "Status \(code) should be success")
        }

        for code in failureCodes {
            let log = createLog(status: code)
            #expect(log.isSuccess == false, "Status \(code) should be failure")
        }
    }

    @Test("HTTPLog isSuccess when no status code")
    func testHTTPLogIsSuccessNoStatus() {
        let log = HTTPLog(
            timestamp: Date(),
            accountId: UUID(),
            requestType: .fetchVehicles,
            method: "GET",
            url: "https://test.com",
            requestHeaders: [:],
            requestBody: nil,
            responseStatus: nil,
            responseHeaders: [:],
            responseBody: nil,
            error: "Network error",
            duration: 0.1
        )

        #expect(log.isSuccess == false)
    }

    @Test("HTTPLog statusText for known codes")
    func testHTTPLogStatusText() {
        let log200 = createLog(status: 200)
        #expect(log200.statusText.contains("200"))

        let log401 = createLog(status: 401)
        #expect(log401.statusText.contains("401"))

        let log500 = createLog(status: 500)
        #expect(log500.statusText.contains("500"))
    }

    @Test("HTTPLog statusText when no status code")
    func testHTTPLogStatusTextNoStatus() {
        let log = HTTPLog(
            timestamp: Date(),
            accountId: UUID(),
            requestType: .sendCommand,
            method: "POST",
            url: "https://test.com",
            requestHeaders: [:],
            requestBody: nil,
            responseStatus: nil,
            responseHeaders: [:],
            responseBody: nil,
            error: "Timeout",
            duration: 30.0
        )

        #expect(log.statusText == "Error")
    }

    @Test("HTTPLog formattedDuration")
    func testHTTPLogFormattedDuration() {
        let log = createLog(status: 200, duration: 1.234)
        let formatted = log.formattedDuration

        #expect(formatted.contains("1.23"))
        #expect(formatted.hasSuffix("s"))
    }

    // MARK: - HTTPRequestType Tests

    @Test("HTTPRequestType covers all API operations")
    func testHTTPRequestTypeCoverage() {
        let allTypes: [HTTPRequestType] = [
            .login,
            .fetchVehicles,
            .fetchVehicleStatus,
            .sendCommand,
            .fetchEVTripDetails,
            .sendMFA,
            .verifyMFA
        ]

        // Verify all types can be used in HTTPLog
        for requestType in allTypes {
            let log = HTTPLog(
                timestamp: Date(),
                accountId: UUID(),
                requestType: requestType,
                method: "POST",
                url: "https://test.com",
                requestHeaders: [:],
                requestBody: nil,
                responseStatus: 200,
                responseHeaders: [:],
                responseBody: nil,
                error: nil,
                duration: 0.1
            )

            #expect(log.requestType == requestType)
        }
    }

    // MARK: - Helpers

    private func createLog(status: Int?, duration: Double = 0.1) -> HTTPLog {
        HTTPLog(
            timestamp: Date(),
            accountId: UUID(),
            requestType: .fetchVehicleStatus,
            method: "GET",
            url: "https://test.com",
            requestHeaders: [:],
            requestBody: nil,
            responseStatus: status,
            responseHeaders: [:],
            responseBody: nil,
            error: nil,
            duration: duration
        )
    }
}
