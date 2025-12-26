//
//  AuthenticationTests.swift
//  BetterBlueKit
//
//  Authentication model tests
//

import Foundation
import Testing
@testable import BetterBlueKit

@Suite("Authentication Tests")
struct AuthenticationTests {

    @Test("AuthToken creation with valid data")
    func testAuthTokenCreation() {
        let now = Date()
        let expiresAt = now.addingTimeInterval(3600)

        let token = AuthToken(
            accessToken: "access123",
            refreshToken: "refresh456",
            expiresAt: expiresAt,
            pin: "1234"
        )

        #expect(token.accessToken == "access123")
        #expect(token.refreshToken == "refresh456")
        #expect(token.expiresAt == expiresAt)
        #expect(token.pin == "1234")
    }

    @Test("AuthToken isValid returns true for future expiration")
    func testAuthTokenIsValidTrue() {
        let futureDate = Date().addingTimeInterval(3600) // 1 hour from now
        let token = AuthToken(
            accessToken: "test",
            refreshToken: "test",
            expiresAt: futureDate,
            pin: "0000"
        )

        #expect(token.isValid == true)
    }

    @Test("AuthToken isValid returns false for past expiration")
    func testAuthTokenIsValidFalse() {
        let pastDate = Date().addingTimeInterval(-3600) // 1 hour ago
        let token = AuthToken(
            accessToken: "test",
            refreshToken: "test",
            expiresAt: pastDate,
            pin: "0000"
        )

        #expect(token.isValid == false)
    }

    @Test("AuthToken isValid returns false for expiration within 5 minute buffer")
    func testAuthTokenIsValidWithBuffer() {
        let nearFuture = Date().addingTimeInterval(240) // 4 minutes from now (less than 5 minute buffer)
        let token = AuthToken(
            accessToken: "test",
            refreshToken: "test",
            expiresAt: nearFuture,
            pin: "0000"
        )

        #expect(token.isValid == false)
    }

    @Test("AuthToken isValid returns true for expiration beyond 5 minute buffer")
    func testAuthTokenIsValidBeyondBuffer() {
        let safeFuture = Date().addingTimeInterval(360) // 6 minutes from now (beyond 5 minute buffer)
        let token = AuthToken(
            accessToken: "test",
            refreshToken: "test",
            expiresAt: safeFuture,
            pin: "0000"
        )

        #expect(token.isValid == true)
    }

    @Test("AuthToken Codable encoding and decoding")
    func testAuthTokenCodable() throws {
        let original = AuthToken(
            accessToken: "access123",
            refreshToken: "refresh456",
            expiresAt: Date(),
            pin: "1234"
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AuthToken.self, from: encoded)

        #expect(decoded.accessToken == original.accessToken)
        #expect(decoded.refreshToken == original.refreshToken)
        #expect(abs(decoded.expiresAt.timeIntervalSince(original.expiresAt)) < 1.0) // Allow small time difference
        #expect(decoded.pin == original.pin)
    }
}
