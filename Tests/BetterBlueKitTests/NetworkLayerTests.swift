//
//  NetworkLayerTests.swift
//  BetterBlueKit
//
//  Network layer and HTTP handling tests
//

import Foundation
import Testing
@testable import BetterBlueKit

@Suite("Network Layer Tests")
struct NetworkLayerTests {

    // MARK: - URL Construction Tests

    @Test("URL construction with various regions")
    func testURLConstructionWithRegions() {
        let regions: [Region] = [.usa, .europe, .canada]
        let brands: [Brand] = [.kia, .hyundai]

        for region in regions {
            for brand in brands {
                let baseURL = region.apiBaseURL(for: brand)

                // Verify URL is well-formed
                #expect(baseURL.hasPrefix("https://"))
                #expect(!baseURL.contains(" ")) // No spaces
                #expect(baseURL.count > 10) // Reasonable length

                // Verify it can be converted to URL
                let url = URL(string: baseURL)
                #expect(url != nil)
                #expect(url?.scheme == "https")
                #expect(url?.host != nil)
                #expect(url?.host?.isEmpty == false)
            }
        }
    }

    // MARK: - HTTP Status Code Handling Tests

    @Test("HTTP status code interpretation")
    func testHTTPStatusCodeInterpretation() {
        // Test various status codes
        let successCodes = [200, 201, 202, 204]
        let errorCodes = [400, 401, 403, 404, 429, 500, 502, 503]

        for code in successCodes {
            let log = HTTPLog(
                timestamp: Date(),
                accountId: UUID(),
                requestType: .fetchVehicleStatus,
                method: "GET",
                url: "https://test.com",
                requestHeaders: [:],
                requestBody: nil,
                responseStatus: code,
                responseHeaders: [:],
                responseBody: nil,
                error: nil,
                duration: 0.1
            )
            #expect(log.isSuccess == true)
        }

        for code in errorCodes {
            let log = HTTPLog(
                timestamp: Date(),
                accountId: UUID(),
                requestType: .fetchVehicleStatus,
                method: "GET",
                url: "https://test.com",
                requestHeaders: [:],
                requestBody: nil,
                responseStatus: code,
                responseHeaders: [:],
                responseBody: nil,
                error: nil,
                duration: 0.1
            )
            #expect(log.isSuccess == false)
        }
    }

    @Test("HTTP status text generation")
    func testHTTPStatusTextGeneration() {
        let testCases: [(Int, String)] = [
            (200, "200"),
            (201, "201"),
            (400, "400"),
            (401, "401"),
            (403, "403"),
            (404, "404"),
            (429, "429"),
            (500, "500"),
            (502, "502"),
            (503, "503"),
            (999, "999") // Unknown status
        ]

        for (code, expectedText) in testCases {
            let log = HTTPLog(
                timestamp: Date(),
                accountId: UUID(),
                requestType: .fetchVehicleStatus,
                method: "GET",
                url: "https://test.com",
                requestHeaders: [:],
                requestBody: nil,
                responseStatus: code,
                responseHeaders: [:],
                responseBody: nil,
                error: nil,
                duration: 0.1
            )
            #expect(log.statusText == expectedText)
        }
    }

    // MARK: - Large Payload Handling Tests

    @Test("Large JSON response parsing")
    func testLargeJSONResponseParsing() throws {
        // Create a large JSON structure
        var largeVehicleData: [String: Any] = [:]

        // Add many properties to simulate a large response
        for i in 0..<1000 {
            largeVehicleData["property_\(i)"] = "value_\(i)_\(String(repeating: "data", count: 100))"
        }

        let largeJSON: [String: Any] = [
            "payload": [
                "vehicleInfoList": [[
                    "lastVehicleInfo": [
                        "vehicleStatusRpt": [
                            "vehicleStatus": largeVehicleData
                        ],
                        "location": [
                            "coord": ["lat": 0.0, "lon": 0.0]
                        ]
                    ]
                ]]
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: largeJSON)

        // Verify we can parse large JSON without issues
        #expect(data.count > 100000) // Should be a substantial size

        let parsedJSON = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(parsedJSON != nil)

        // Verify parsing time is reasonable
        let startTime = Date()
        for _ in 0..<100 {
            _ = try JSONSerialization.jsonObject(with: data)
        }
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)

        #expect(duration < 1.0) // Should parse 100 times in under 1 second
    }

    // MARK: - Error Response Handling Tests

    @Test("Malformed JSON response handling")
    func testMalformedJSONResponseHandling() {
        let malformedJSONStrings = [
            "{ invalid json",
            "{ \"key\": }",
            "{ \"key\": \"value\", }",
            "{ \"key\": \"value\" \"another\": \"value\" }",
            "null",
            "",
            "{ \"key\": undefined }",
            "{ \"key\": NaN }"
        ]

        for malformedJSON in malformedJSONStrings {
            // HTTPLog should be able to handle any data, even malformed JSON
            let log = HTTPLog(
                timestamp: Date(),
                accountId: UUID(),
                requestType: .fetchVehicleStatus,
                method: "GET",
                url: "https://api.example.com/test",
                requestHeaders: [:],
                requestBody: malformedJSON,
                responseStatus: 400,
                responseHeaders: [:],
                responseBody: malformedJSON,
                error: nil,
                duration: 0.1
            )

            #expect(log.responseStatus == 400)
            #expect(log.statusText == "400")
            #expect(log.requestBody == malformedJSON)
            #expect(log.responseBody == malformedJSON)
        }
    }

    @Test("Network error simulation")
    func testNetworkErrorSimulation() {
        // Test various network error scenarios
        let errorLog = HTTPLog(
            timestamp: Date(),
            accountId: UUID(),
            requestType: .fetchVehicleStatus,
            method: "GET",
            url: "https://test.com",
            requestHeaders: [:],
            requestBody: nil,
            responseStatus: nil, // No status code indicates network error
            responseHeaders: [:],
            responseBody: nil,
            error: "Network timeout",
            duration: 30.0 // Long duration suggests timeout
        )

        #expect(errorLog.responseStatus == nil)
        #expect(errorLog.isSuccess == false)
        #expect(errorLog.statusText == "Error")
        #expect(errorLog.duration == 30.0)
    }

    // MARK: - Response Time Tests

    @Test("Response time tracking accuracy")
    func testResponseTimeTrackingAccuracy() {
        let durations: [TimeInterval] = [0.001, 0.1, 1.0, 5.0, 30.0, 60.0]

        for duration in durations {
            let log = HTTPLog(
                timestamp: Date(),
                accountId: UUID(),
                requestType: .fetchVehicleStatus,
                method: "GET",
                url: "https://test.com",
                requestHeaders: [:],
                requestBody: nil,
                responseStatus: 200,
                responseHeaders: [:],
                responseBody: nil,
                error: nil,
                duration: duration
            )

            #expect(log.duration == duration)

            let formattedDuration = log.formattedDuration
            #expect(formattedDuration.contains("s")) // Should contain 's' for seconds
            #expect(formattedDuration.hasSuffix("s")) // Should end with 's'

            // The actual format is "X.XXs" regardless of duration
            #expect(!formattedDuration.matches(of: /\d+\.\d{2}s/).isEmpty)
        }
    }

    // MARK: - Content Type Validation Tests

    @Test("Response content type validation")
    func testResponseContentTypeValidation() {
        let contentTypes = [
            "application/json",
            "application/json; charset=utf-8",
            "text/plain",
            "text/html",
            "application/xml",
            "application/octet-stream"
        ]

        for contentType in contentTypes {
            let log = HTTPLog(
                timestamp: Date(),
                accountId: UUID(),
                requestType: .fetchVehicleStatus,
                method: "GET",
                url: "https://test.com",
                requestHeaders: [:],
                requestBody: nil,
                responseStatus: 200,
                responseHeaders: ["Content-Type": contentType],
                responseBody: nil,
                error: nil,
                duration: 0.1
            )

            #expect(log.responseHeaders["Content-Type"] == contentType)

            // Could add validation logic here based on content type
            #expect(contentType.isEmpty == false)
        }
    }
}
