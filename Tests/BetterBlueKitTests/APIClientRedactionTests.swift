//
//  APIClientRedactionTests.swift
//  BetterBlueKit
//
//  Tests for SensitiveDataRedactor functionality
//

import Foundation
import Testing
@testable import BetterBlueKit

@Suite("Sensitive Data Redaction Tests")
struct APIClientRedactionTests {

    // MARK: - redact Tests

    @Test("redact with nil input")
    func testRedactSensitiveDataWithNil() {
        let result = SensitiveDataRedactor.redact(nil)
        #expect(result == nil)
    }

    @Test("redact with password fields")
    func testRedactSensitiveDataWithPasswords() {
        let input = """
        {
            "password": "secret123",
            "PIN": "1234",
            "pin": "5678",
            "other_field": "normal_value"
        }
        """

        let result = SensitiveDataRedactor.redact(input)!

        // Check that sensitive data is redacted
        #expect(result.contains("[REDACTED]"))
        #expect(result.contains("normal_value"))
        #expect(!result.contains("secret123"))
    }

    @Test("redact with Bearer tokens")
    func testRedactSensitiveDataWithBearerTokens() {
        let input = "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test.token"
        let result = SensitiveDataRedactor.redact(input)!

        #expect(result.contains("Bearer [REDACTED]"))
        #expect(!result.contains("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test.token"))
    }

    @Test("redact with access and refresh tokens")
    func testRedactSensitiveDataWithTokens() {
        let input = """
        {
            "access_token": "abc123def456",
            "refresh_token": "xyz789uvw012",
            "accessToken": "token123",
            "refreshToken": "refresh456"
        }
        """

        let result = SensitiveDataRedactor.redact(input)!

        // Check that the tokens are redacted
        #expect(result.contains("[REDACTED]"))
        #expect(!result.contains("abc123def456"))
        #expect(!result.contains("xyz789uvw012"))
        #expect(!result.contains("token123"))
        #expect(!result.contains("refresh456"))
    }

    @Test("redact with location coordinates")
    func testRedactSensitiveDataWithCoordinates() {
        let input = """
        {
            "latitude": 37.7749,
            "longitude": -122.4194,
            "lat": 40.7128,
            "lng": -74.0060,
            "lon": -0.1278
        }
        """

        let result = SensitiveDataRedactor.redact(input)!

        // Check that coordinates are redacted
        #expect(result.contains("[REDACTED]"))
        #expect(!result.contains("37.7749"))
        #expect(!result.contains("-122.4194"))
        #expect(!result.contains("40.7128"))
        #expect(!result.contains("-74.0060"))
    }

    @Test("redact with coordinate pairs")
    func testRedactSensitiveDataWithCoordinatePairs() {
        let input = "Location: 37.7749, -122.4194 and another location: 40.7128, -74.0060"
        let result = SensitiveDataRedactor.redact(input)!

        #expect(result.contains("[LOCATION_REDACTED]"))
        #expect(!result.contains("37.7749, -122.4194"))
        #expect(!result.contains("40.7128, -74.0060"))
    }

    @Test("redact preserves non-sensitive data")
    func testRedactSensitiveDataPreservesNormalData() {
        let input = """
        {
            "vehicle_id": "VIN123456789",
            "status": "locked",
            "battery_level": 85
        }
        """

        let result = SensitiveDataRedactor.redact(input)!

        #expect(result.contains("VIN123456789"))
        #expect(result.contains("locked"))
        #expect(result.contains("85"))
    }

    @Test("redact with mixed sensitive and normal data")
    func testRedactSensitiveDataMixed() {
        let input = """
        {
            "vehicle_status": "unlocked",
            "password": "secret123",
            "latitude": 37.7749,
            "access_token": "token123"
        }
        """

        let result = SensitiveDataRedactor.redact(input)!

        // Should redact sensitive data
        #expect(result.contains("[REDACTED]"))

        // Should preserve normal data
        #expect(result.contains("unlocked"))

        // Should not contain original sensitive values
        #expect(!result.contains("secret123"))
        #expect(!result.contains("37.7749"))
        #expect(!result.contains("token123"))
    }

    // MARK: - redactHeaders Tests

    @Test("redactHeaders with Authorization header")
    func testRedactSensitiveHeadersWithAuthorization() {
        let headers = [
            "Authorization": "Bearer secret_token_123",
            "Content-Type": "application/json"
        ]

        let result = SensitiveDataRedactor.redactHeaders(headers)

        #expect(result["Authorization"] == "Bearer [REDACTED]")
        #expect(result["Content-Type"] == "application/json")
    }

    @Test("redactHeaders with lowercase authorization header")
    func testRedactSensitiveHeadersWithLowercaseAuth() {
        let headers = [
            "authorization": "Bearer another_secret_token",
            "user-agent": "BetterBlueKit/1.0"
        ]

        let result = SensitiveDataRedactor.redactHeaders(headers)

        #expect(result["authorization"] == "Bearer [REDACTED]")
        #expect(result["user-agent"] == "BetterBlueKit/1.0")
    }

    @Test("redactHeaders with auth-related headers")
    func testRedactSensitiveHeadersWithAuthRelated() {
        let headers = [
            "X-Auth-Token": "secret123",
            "Access-Token": "token789",
            "Content-Type": "application/json"
        ]

        let result = SensitiveDataRedactor.redactHeaders(headers)

        #expect(result["X-Auth-Token"] == "[REDACTED]")
        #expect(result["Access-Token"] == "[REDACTED]")
        #expect(result["Content-Type"] == "application/json")
    }

    @Test("redactHeaders with token-related headers")
    func testRedactSensitiveHeadersWithTokenRelated() {
        let headers = [
            "X-Token": "another_token",
            "Bearer-Token": "bearer_token",
            "Accept": "application/json"
        ]

        let result = SensitiveDataRedactor.redactHeaders(headers)

        #expect(result["X-Token"] == "[REDACTED]")
        #expect(result["Bearer-Token"] == "[REDACTED]")
        #expect(result["Accept"] == "application/json")
    }

    @Test("redactHeaders preserves non-sensitive headers")
    func testRedactSensitiveHeadersPreservesNormalHeaders() {
        let headers = [
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "BetterBlueKit/1.0",
            "X-Request-ID": "123456789"
        ]

        let result = SensitiveDataRedactor.redactHeaders(headers)

        #expect(result == headers) // Should be unchanged
    }

    @Test("redactHeaders with Canada cookie and transaction headers")
    func testRedactSensitiveHeadersWithCanadaHeaders() {
        let headers = [
            "Cookie": "__cf_bm=secret_cookie",
            "TransactionId": "txn-12345",
            "Pauth": "pauth-secret",
            "Accesstoken": "access-secret",
            "Content-Type": "application/json"
        ]

        let result = SensitiveDataRedactor.redactHeaders(headers)
        #expect(result["Cookie"] == "[REDACTED]")
        #expect(result["TransactionId"] == "[REDACTED]")
        #expect(result["Pauth"] == "[REDACTED]")
        #expect(result["Accesstoken"] == "[REDACTED]")
        #expect(result["Content-Type"] == "application/json")
    }

    @Test("redactHeaders with empty headers")
    func testRedactSensitiveHeadersWithEmptyHeaders() {
        let headers: [String: String] = [:]
        let result = SensitiveDataRedactor.redactHeaders(headers)

        #expect(result.isEmpty)
    }

    // MARK: - Edge Cases

    @Test("redact with empty string")
    func testRedactSensitiveDataWithEmptyString() {
        let result = SensitiveDataRedactor.redact("")
        #expect(result == "")
    }

    @Test("redact with malformed JSON")
    func testRedactSensitiveDataWithMalformedJSON() {
        let input = "{ password: secret123, malformed json"
        let result = SensitiveDataRedactor.redact(input)!

        // The regex might not work on malformed JSON, so we can't guarantee redaction
        // Just check that the function doesn't crash
        #expect(result.count > 0)
    }

    @Test("redact with nested coordinates")
    func testRedactSensitiveDataWithNestedCoordinates() {
        let input = """
        {
            "location": {
                "coordinates": {
                    "latitude": 37.7749,
                    "longitude": -122.4194
                }
            }
        }
        """

        let result = SensitiveDataRedactor.redact(input)!

        #expect(result.contains("[REDACTED]"))
        #expect(!result.contains("37.7749"))
        #expect(!result.contains("-122.4194"))
    }

    @Test("redact VIN numbers")
    func testRedactVINNumbers() {
        let input = """
        {
            "vin": "KMHJ3314HMU000001",
            "VIN": "5YJXCBE29KF000002"
        }
        """

        let result = SensitiveDataRedactor.redact(input)!

        // VINs should be partially redacted (first 3 and last 4 chars preserved)
        #expect(result.contains("KMH**********0001"))
        #expect(result.contains("5YJ**********0002"))
        #expect(!result.contains("KMHJ3314HMU000001"))
        #expect(!result.contains("5YJXCBE29KF000002"))
    }

    @Test("redact regId")
    func testRedactRegId() {
        let input = """
        {
            "regId": "ABC123456789",
            "regID": "XYZ987654321"
        }
        """

        let result = SensitiveDataRedactor.redact(input)!

        #expect(result.contains("[REDACTED]"))
        #expect(!result.contains("ABC123456789"))
        #expect(!result.contains("XYZ987654321"))
    }

    @Test("redact rememberMeToken")
    func testRedactRememberMeToken() {
        let input = """
        {
            "rememberMeToken": "some_long_token_value_here"
        }
        """

        let result = SensitiveDataRedactor.redact(input)!

        #expect(result.contains("[REDACTED]"))
        #expect(!result.contains("some_long_token_value_here"))
    }
}
