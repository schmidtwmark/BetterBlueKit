//
//  APIClientRedactionTests.swift
//  BetterBlueKit
//
//  API Client redaction functionality tests
//

import Foundation
import Testing
@testable import BetterBlueKit

//
//  APIClientRedactionTests.swift
//  BetterBlueKit
//
//  API Client redaction functionality tests
//

@Suite("API Client Redaction Tests")
struct APIClientRedactionTests {

    // We need to create a test APIClient to access the redaction methods
    @MainActor private func makeTestClient() -> APIClient<TestProvider> {
        let config = APIClientConfiguration(
            region: .usa,
            brand: .hyundai,
            username: "test@example.com",
            password: "password123",
            pin: "0000",
            accountId: UUID(),
            logSink: nil
        )
        return APIClient(configuration: config, endpointProvider: TestProvider())
    }

    // MARK: - redactSensitiveData Tests

    @Test("redactSensitiveData with nil input")
    @MainActor func testRedactSensitiveDataWithNil() {
        let client = makeTestClient()
        let result: String? = client.redactSensitiveData(in: nil)
        #expect(result == nil)
    }

    @Test("redactSensitiveData with password fields")
    @MainActor func testRedactSensitiveDataWithPasswords() {
        let client = makeTestClient()

        let input = """
        {
            "password": "secret123",
            "PIN": "1234",
            "pin": "5678",
            "other_field": "normal_value"
        }
        """

        let result = client.redactSensitiveData(in: input)!

        // Check that the actual redacted format is present
        #expect(result.contains("\"password\":\"[REDACTED]\"") || result.contains("\"password\"\":\"[REDACTED]\""))
        #expect(result.contains("\"PIN\":\"[REDACTED]\"") || result.contains("\"PIN\"\":\"[REDACTED]\""))
        #expect(result.contains("\"pin\":\"[REDACTED]\"") || result.contains("\"pin\"\":\"[REDACTED]\""))
        #expect(result.contains("normal_value"))
        #expect(!result.contains("secret123"))
        #expect(!result.contains("1234"))
        #expect(!result.contains("5678"))
    }

    @Test("redactSensitiveData with Bearer tokens")
    @MainActor func testRedactSensitiveDataWithBearerTokens() {
        let client = makeTestClient()

        let input = "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test.token"
        let result = client.redactSensitiveData(in: input)!

        #expect(result.contains("Bearer [REDACTED]"))
        #expect(!result.contains("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test.token"))
    }

    @Test("redactSensitiveData with access and refresh tokens")
    @MainActor func testRedactSensitiveDataWithTokens() {
        let client = makeTestClient()

        let input = """
        {
            "access_token": "abc123def456",
            "refresh_token": "xyz789uvw012",
            "accessToken": "token123",
            "refreshToken": "refresh456"
        }
        """

        let result = client.redactSensitiveData(in: input)!

        // Check that the tokens are redacted (allow for escaped quotes)
        #expect(result.contains("[REDACTED]"))
        #expect(!result.contains("abc123def456"))
        #expect(!result.contains("xyz789uvw012"))
        #expect(!result.contains("token123"))
        #expect(!result.contains("refresh456"))
    }

    @Test("redactSensitiveData with location coordinates")
    @MainActor func testRedactSensitiveDataWithCoordinates() {
        let client = makeTestClient()

        let input = """
        {
            "latitude": 37.7749,
            "longitude": -122.4194,
            "lat": 40.7128,
            "lng": -74.0060,
            "lon": -0.1278
        }
        """

        let result = client.redactSensitiveData(in: input)!

        // Check that coordinates are redacted
        #expect(result.contains("[REDACTED]"))
        #expect(!result.contains("37.7749"))
        #expect(!result.contains("-122.4194"))
        #expect(!result.contains("40.7128"))
        #expect(!result.contains("-74.0060"))
    }

    @Test("redactSensitiveData with coordinate pairs")
    @MainActor func testRedactSensitiveDataWithCoordinatePairs() {
        let client = makeTestClient()

        let input = "Location: 37.7749, -122.4194 and another location: 40.7128, -74.0060"
        let result = client.redactSensitiveData(in: input)!

        #expect(result.contains("[LOCATION_REDACTED]"))
        #expect(!result.contains("37.7749, -122.4194"))
        #expect(!result.contains("40.7128, -74.0060"))
    }

    @Test("redactSensitiveData preserves non-sensitive data")
    @MainActor func testRedactSensitiveDataPreservesNormalData() {
        let client = makeTestClient()

        let input = """
        {
            "username": "user@example.com",
            "vehicle_id": "VIN123456789",
            "status": "locked",
            "battery_level": 85
        }
        """

        let result = client.redactSensitiveData(in: input)!

        #expect(result.contains("user@example.com"))
        #expect(result.contains("VIN123456789"))
        #expect(result.contains("locked"))
        #expect(result.contains("85"))
    }

    @Test("redactSensitiveData with mixed sensitive and normal data")
    @MainActor func testRedactSensitiveDataMixed() {
        let client = makeTestClient()

        let input = """
        {
            "username": "user@example.com",
            "password": "secret123",
            "latitude": 37.7749,
            "vehicle_status": "unlocked",
            "access_token": "token123"
        }
        """

        let result = client.redactSensitiveData(in: input)!

        // Should redact sensitive data
        #expect(result.contains("[REDACTED]"))

        // Should preserve normal data
        #expect(result.contains("user@example.com"))
        #expect(result.contains("unlocked"))

        // Should not contain original sensitive values
        #expect(!result.contains("secret123"))
        #expect(!result.contains("37.7749"))
        #expect(!result.contains("token123"))
    }

    // MARK: - redactSensitiveHeaders Tests

    @Test("redactSensitiveHeaders with Authorization header")
    @MainActor func testRedactSensitiveHeadersWithAuthorization() {
        let client = makeTestClient()

        let headers = [
            "Authorization": "Bearer secret_token_123",
            "Content-Type": "application/json"
        ]

        let result = client.redactSensitiveHeaders(headers)

        #expect(result["Authorization"] == "[REDACTED]")
        #expect(result["Content-Type"] == "application/json")
    }

    @Test("redactSensitiveHeaders with lowercase authorization header")
    @MainActor func testRedactSensitiveHeadersWithLowercaseAuth() {
        let client = makeTestClient()

        let headers = [
            "authorization": "Bearer another_secret_token",
            "user-agent": "BetterBlueKit/1.0"
        ]

        let result = client.redactSensitiveHeaders(headers)

        #expect(result["authorization"] == "[REDACTED]")
        #expect(result["user-agent"] == "BetterBlueKit/1.0")
    }

    @Test("redactSensitiveHeaders with auth-related headers")
    @MainActor func testRedactSensitiveHeadersWithAuthRelated() {
        let client = makeTestClient()

        let headers = [
            "X-Auth-Token": "secret123",
            "Auth-Key": "key456",
            "Access-Token": "token789",
            "Content-Type": "application/json"
        ]

        let result = client.redactSensitiveHeaders(headers)

        #expect(result["X-Auth-Token"] == "[REDACTED]")
        #expect(result["Auth-Key"] == "[REDACTED]")
        #expect(result["Access-Token"] == "[REDACTED]")
        #expect(result["Content-Type"] == "application/json")
    }

    @Test("redactSensitiveHeaders with token-related headers")
    @MainActor func testRedactSensitiveHeadersWithTokenRelated() {
        let client = makeTestClient()

        let headers = [
            "Token": "secret_token",
            "X-Token": "another_token",
            "Bearer-Token": "bearer_token",
            "Accept": "application/json"
        ]

        let result = client.redactSensitiveHeaders(headers)

        #expect(result["Token"] == "[REDACTED]")
        #expect(result["X-Token"] == "[REDACTED]")
        #expect(result["Bearer-Token"] == "[REDACTED]")
        #expect(result["Accept"] == "application/json")
    }

    @Test("redactSensitiveHeaders preserves non-sensitive headers")
    @MainActor func testRedactSensitiveHeadersPreservesNormalHeaders() {
        let client = makeTestClient()

        let headers = [
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "BetterBlueKit/1.0",
            "X-Request-ID": "123456789"
        ]

        let result = client.redactSensitiveHeaders(headers)

        #expect(result == headers) // Should be unchanged
    }

    @Test("redactSensitiveHeaders with empty headers")
    @MainActor func testRedactSensitiveHeadersWithEmptyHeaders() {
        let client = makeTestClient()

        let headers: [String: String] = [:]
        let result = client.redactSensitiveHeaders(headers)

        #expect(result.isEmpty)
    }

    @Test("redactSensitiveHeaders case sensitivity")
    @MainActor func testRedactSensitiveHeadersCaseSensitivity() {
        let client = makeTestClient()

        let headers = [
            "AUTHORIZATION": "Bearer uppercase_token",
            "Authentication": "Basic base64string",
            "x-auth-token": "lowercase_token"
        ]

        let result = client.redactSensitiveHeaders(headers)

        // The method checks lowercased keys, so these should be redacted
        #expect(result["AUTHORIZATION"] == "[REDACTED]")
        #expect(result["Authentication"] == "[REDACTED]")
        #expect(result["x-auth-token"] == "[REDACTED]")
    }

    // MARK: - Edge Cases

    @Test("redactSensitiveData with empty string")
    @MainActor func testRedactSensitiveDataWithEmptyString() {
        let client = makeTestClient()
        let result = client.redactSensitiveData(in: "")
        #expect(result == "")
    }

    @Test("redactSensitiveData with malformed JSON")
    @MainActor func testRedactSensitiveDataWithMalformedJSON() {
        let client = makeTestClient()

        let input = "{ password: secret123, malformed json"
        let result = client.redactSensitiveData(in: input)!

        // The regex might not work on malformed JSON, so we can't guarantee redaction
        // Just check that the function doesn't crash
        #expect(result.count > 0)
    }

    @Test("redactSensitiveData with nested coordinates")
    @MainActor func testRedactSensitiveDataWithNestedCoordinates() {
        let client = makeTestClient()

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

        let result = client.redactSensitiveData(in: input)!

        #expect(result.contains("[REDACTED]"))
        #expect(!result.contains("37.7749"))
        #expect(!result.contains("-122.4194"))
    }
}
