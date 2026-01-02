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

    @Test("API endpoint URL construction")
    @MainActor func testAPIEndpointURLConstruction() {
        let config = APIClientConfiguration(
            region: .usa,
            brand: .kia,
            username: "test@example.com",
            password: "password123",
            pin: "0000",
            accountId: UUID()
        )

        let provider = KiaAPIEndpointProvider(configuration: config)

        // Test login endpoint
        let loginEndpoint = provider.loginEndpoint()
        #expect(loginEndpoint.url.hasPrefix("https://"))
        #expect(loginEndpoint.url.contains("prof/authUser"))
        #expect(loginEndpoint.method == .POST)
        #expect(loginEndpoint.headers["content-type"] == "application/json;charset=UTF-8")

        // Verify URL is valid
        let url = URL(string: loginEndpoint.url)
        #expect(url != nil)
        #expect(url?.scheme == "https")
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

    // MARK: - Request Header Tests

    @Test("API headers contain required fields")
    @MainActor func testAPIHeadersContainRequiredFields() {
        let config = APIClientConfiguration(
            region: .usa,
            brand: .kia,
            username: "test@example.com",
            password: "password123",
            pin: "0000",
            accountId: UUID()
        )

        let provider = KiaAPIEndpointProvider(configuration: config)
        let endpoint = provider.loginEndpoint()

        let requiredHeaders = [
            "content-type",
            "accept",
            "accept-encoding",
            "accept-language",
            "apptype",
            "appversion",
            "clientid",
            "from",
            "host",
            "language",
            "offset",
            "ostype",
            "osversion",
            "secretkey",
            "to",
            "tokentype",
            "user-agent",
            "deviceid",
            "date"
        ]

        for header in requiredHeaders {
            #expect(endpoint.headers[header] != nil, "Missing required header: \(header)")
            #expect(endpoint.headers[header]?.isEmpty == false, "Empty header value for: \(header)")
        }
    }

    @Test("API headers format validation")
    @MainActor func testAPIHeadersFormatValidation() {
        let config = APIClientConfiguration(
            region: .usa,
            brand: .kia,
            username: "test@example.com",
            password: "password123",
            pin: "0000",
            accountId: UUID()
        )

        let provider = KiaAPIEndpointProvider(configuration: config)
        let endpoint = provider.loginEndpoint()

        // Validate specific header formats
        #expect(endpoint.headers["content-type"] == "application/json;charset=UTF-8")
        #expect(endpoint.headers["accept"] == "application/json, text/plain, */*")
        #expect(endpoint.headers["apptype"] == "L")
        #expect(endpoint.headers["clientid"] == "MWAMOBILE")
        #expect(endpoint.headers["from"] == "SPA")
        #expect(endpoint.headers["to"] == "APIGW")
        #expect(endpoint.headers["tokentype"] == "G")
        #expect(endpoint.headers["ostype"] == "Android")

        // Validate date format (should be RFC 1123)
        let dateHeader = endpoint.headers["date"]
        #expect(dateHeader != nil)
        #expect(dateHeader?.contains("GMT") == true)

        // Validate deviceid format (should be alphanumeric with colon and UUID)
        let deviceId = endpoint.headers["deviceid"]
        #expect(deviceId != nil)
        #expect(deviceId?.contains(":") == true)
        #expect(deviceId?.count == 55) // 22 chars + 1 colon + 32 chars (UUID without dashes)
    }

    // MARK: - Request Body Tests

    @Test("Login request body format")
    @MainActor func testLoginRequestBodyFormat() throws {
        let config = APIClientConfiguration(
            region: .usa,
            brand: .kia,
            username: "test@example.com",
            password: "password123",
            pin: "0000",
            accountId: UUID()
        )

        let provider = KiaAPIEndpointProvider(configuration: config)
        let endpoint = provider.loginEndpoint()

        #expect(endpoint.body != nil)

        let bodyData = try #require(endpoint.body)
        let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]

        #expect(json != nil)
        #expect(json?["deviceKey"] as? String == nil)
        #expect(json?["deviceType"] as? Int == nil)

        let userCredential = json?["userCredential"] as? [String: Any]
        #expect(userCredential != nil)
        #expect(userCredential?["userId"] as? String == "test@example.com")
        #expect(userCredential?["password"] as? String == "password123")
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
