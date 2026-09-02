//
//  EuropeCCILoginTests.swift
//  BetterBlueKit
//
//  Tests for the EU OneApp/CCI login plumbing: the persisted token-set
//  encoding that rides in the account's `refreshToken` slot, the timezone
//  header format, and redaction of the new CCI token fields.
//

import Foundation
import Testing
@testable import BetterBlueKit

@Suite("Europe CCI Login")
struct EuropeCCILoginTests {

    private func makeSet() -> CCITokenSet {
        CCITokenSet(
            accessToken: "cci-access",
            refreshToken: "cci-refresh",
            exchangeableAccessToken: "exch-access",
            exchangeableRefreshToken: "exch-refresh",
            nonCcsToken: "non-ccs",
            nonCcsRefreshToken: "non-ccs-refresh",
            idToken: "id-token"
        )
    }

    @Test("Token set round-trips through the refreshToken slot")
    func testStorageRoundTrip() {
        let set = makeSet()
        let stored = set.encodeForStorage()
        #expect(stored.hasPrefix(CCITokenSet.storagePrefix))
        #expect(CCITokenSet.decodeFromStorage(stored) == set)
    }

    @Test("Legacy refresh tokens never decode as a CCI set")
    func testLegacyTokensDontMatch() {
        // The legacy grant hands out 48-char uppercase alphanumerics.
        let legacy = String(repeating: "A1B2C3D4E5F6", count: 4)
        #expect(CCITokenSet.decodeFromStorage(legacy) == nil)
        #expect(CCITokenSet.decodeFromStorage("") == nil)
        // Prefix with a corrupt payload must fail, not crash.
        #expect(CCITokenSet.decodeFromStorage("cci1:!!!not-base64!!!") == nil)
    }

    @Test("UTC offset header renders as +HH:MM")
    func testUTCOffsetFormat() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        #expect(APIClientBase.currentUTCOffsetString(timeZone: utc) == "+00:00")
        let berlinSummer = try #require(TimeZone(identifier: "Europe/Berlin"))
        let julyFirst = try #require(
            Calendar(identifier: .gregorian).date(from: DateComponents(
                timeZone: utc, year: 2026, month: 7, day: 1, hour: 12
            ))
        )
        #expect(APIClientBase.currentUTCOffsetString(timeZone: berlinSummer, at: julyFirst) == "+02:00")
        let stJohns = try #require(TimeZone(identifier: "America/St_Johns"))
        let januaryFirst = try #require(
            Calendar(identifier: .gregorian).date(from: DateComponents(
                timeZone: utc, year: 2026, month: 1, day: 1, hour: 12
            ))
        )
        #expect(APIClientBase.currentUTCOffsetString(timeZone: stJohns, at: januaryFirst) == "-03:30")
    }

    @Test("CCI token fields are redacted in JSON bodies")
    func testCCITokenRedaction() {
        let body = #"""
        {"accessToken":"secret-a","refreshToken":"secret-r",
        "exchangeableAccessToken":"secret-e","exchangeableRefreshToken":"secret-er",
        "nonCcsToken":"secret-n","nonCcsRefreshToken":"secret-nr","idToken":"secret-i"}
        """#
        let redacted = SensitiveDataRedactor.redact(body) ?? ""
        #expect(!redacted.contains("secret-a"))
        #expect(!redacted.contains("secret-e"))
        #expect(!redacted.contains("secret-er"))
        #expect(!redacted.contains("secret-n"))
        #expect(!redacted.contains("secret-nr"))
        #expect(!redacted.contains("secret-i"))
    }

    @Test("Form-encoded signin credentials are redacted")
    func testFormEncodedCredentialRedaction() {
        let body = "client_id=abc&encryptedPassword=true&password=deadbeef01"
            + "&state=ccsp&username=user%40example.com&kid=k1"
        let redacted = SensitiveDataRedactor.redact(body) ?? ""
        #expect(!redacted.contains("deadbeef01"))
        #expect(!redacted.contains("user%40example.com"))
        // The boolean flag is not a secret and must survive.
        #expect(redacted.contains("encryptedPassword=true"))
        #expect(redacted.contains("state=ccsp"))
    }

    @Test("OAuth authorization codes in URLs are redacted")
    func testAuthorizationCodeRedaction() {
        let url = "https://cci-api-eu.hyundai.com/domain/api/v1/auth/token?code=SECRET-CODE-123"
        let redacted = SensitiveDataRedactor.redact(url) ?? ""
        #expect(!redacted.contains("SECRET-CODE-123"))
        #expect(redacted.contains("code=[REDACTED]"))
        // Words merely containing "code" must survive.
        let benign = "https://example.com/api?promocode=abc&mode=1"
        #expect(SensitiveDataRedactor.redact(benign) == benign)
    }

    @Test("The Location response header is redacted")
    func testLocationHeaderRedaction() {
        let headers = [
            "Location": "https://oneapp.hyundai.com/redirect?code=SECRET-CODE-123&state=ccsp",
            "Content-Type": "application/json"
        ]
        let redacted = SensitiveDataRedactor.redactHeaders(headers)
        #expect(redacted["Location"] == "[REDACTED]")
        #expect(redacted["Content-Type"] == "application/json")
    }
}
