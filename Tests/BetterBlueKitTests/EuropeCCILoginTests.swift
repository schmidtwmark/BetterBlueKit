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

// MARK: - X-Fingerprint signing

/// Pins the EU CCI X-Fingerprint scheme to the two vectors in
/// hyundai_kia_connect_api's `tests/eu_cci_fingerprint_test.py` (#1352):
/// bodyless exchanges that answered 200 live on 2026-10-14 with exactly
/// these timestamps and fingerprints.
@MainActor
@Suite("Europe CCI Fingerprint")
struct EuropeCCIFingerprintTests {

    private static let kiaTimestamp = "1700000000123"
    private static let kiaFingerprint = "0a3ceccc83823ec0d2c5d39a15dbf722c813e6da48800a0156a7a8459db63337"
    private static let hyundaiTimestamp = "1792000084084"
    private static let hyundaiFingerprint = "df04e3dadd52288ce5b280b368af261272556b5360adbc90a817a167526e2946"

    private func identity(_ config: EuropeCCIConfig, timestamp: String) -> [String: String] {
        [
            "client-id": config.packageId,
            "client-name": config.fingerprintClientName,
            "client-version": "1.4.0",
            "client-os-code": "android",
            "client-os-version": "14",
            "X-Timestamp": timestamp
        ]
    }

    private func signedHeaders(_ config: EuropeCCIConfig, body: String = "") -> [String: String] {
        let brand: Brand = config.packageId.contains("kia") ? .kia : .hyundai
        let configuration = APIClientConfiguration(
            region: .europe,
            brand: brand,
            username: "test@example.com",
            password: "password123",
            pin: "0000",
            accountId: UUID(),
            deviceId: "11111111-2222-3333-4444-555555555555"
        )
        let client: APIClientBase = brand == .kia
            ? KiaEuropeAPIClient(configuration: configuration)
            : HyundaiEuropeAPIClient(configuration: configuration)
        return client.cciSignedHeaders(config: config, body: body)
    }

    @Test("Kia vector matches the live 200")
    func testKiaVector() {
        let headers = identity(.kia, timestamp: Self.kiaTimestamp)
        #expect(EuropeCCIFingerprint.signature(headers: headers, keyPieces: EuropeCCIConfig.kia.fingerprintKey)
            == Self.kiaFingerprint)
    }

    @Test("Hyundai vector matches the live 200")
    func testHyundaiVector() {
        let headers = identity(.hyundai, timestamp: Self.hyundaiTimestamp)
        #expect(EuropeCCIFingerprint.signature(headers: headers, keyPieces: EuropeCCIConfig.hyundai.fingerprintKey)
            == Self.hyundaiFingerprint)
    }

    @Test("Header names are matched case-insensitively")
    func testHeaderNameCase() {
        var headers: [String: String] = [:]
        for (name, value) in identity(.kia, timestamp: Self.kiaTimestamp) {
            headers[name.uppercased()] = value
        }
        #expect(EuropeCCIFingerprint.signature(headers: headers, keyPieces: EuropeCCIConfig.kia.fingerprintKey)
            == Self.kiaFingerprint)
    }

    @Test("Only ASCII whitespace is stripped from the body")
    func testWhitespaceStripping() {
        let headers = identity(.kia, timestamp: Self.kiaTimestamp)
        let key = EuropeCCIConfig.kia.fingerprintKey
        let bare = EuropeCCIFingerprint.signature(headers: headers, keyPieces: key)
        #expect(EuropeCCIFingerprint.signature(headers: headers, keyPieces: key, body: " \t\r\n\u{0B}\u{0C}") == bare)
        #expect(EuropeCCIFingerprint.signature(headers: headers, keyPieces: key, body: "\u{00A0}") != bare)
        #expect(EuropeCCIFingerprint.signature(headers: headers, keyPieces: key, body: #"{ "a": 1 }"#)
            == EuropeCCIFingerprint.signature(headers: headers, keyPieces: key, body: #"{"a":1}"#))
    }

    @Test("The body and the brand both change the signature")
    func testBodyAndBrandAreSigned() {
        let headers = identity(.hyundai, timestamp: Self.hyundaiTimestamp)
        let bare = EuropeCCIFingerprint.signature(headers: headers, keyPieces: EuropeCCIConfig.hyundai.fingerprintKey)
        #expect(EuropeCCIFingerprint.signature(
            headers: headers, keyPieces: EuropeCCIConfig.hyundai.fingerprintKey, body: #"{"a":1}"#
        ) != bare)
        #expect(EuropeCCIFingerprint.signature(headers: headers, keyPieces: EuropeCCIConfig.kia.fingerprintKey) != bare)
    }

    @Test("Signed headers carry the identity the live vectors were taken with")
    func testSignedHeadersIdentity() {
        for (config, timestamp, fingerprint) in [
            (EuropeCCIConfig.hyundai, Self.hyundaiTimestamp, Self.hyundaiFingerprint),
            (EuropeCCIConfig.kia, Self.kiaTimestamp, Self.kiaFingerprint)
        ] {
            var headers = signedHeaders(config)
            // The header's own fingerprint covers its own timestamp...
            let own = headers.removeValue(forKey: "X-Fingerprint")
            #expect(own == EuropeCCIFingerprint.signature(headers: headers, keyPieces: config.fingerprintKey))
            // ...and with the vector's timestamp, it reproduces the live 200.
            headers["X-Timestamp"] = timestamp
            #expect(EuropeCCIFingerprint.signature(headers: headers, keyPieces: config.fingerprintKey) == fingerprint)
            #expect(headers["Content-Length"] == "0")
            #expect(headers["X-Region"] == "eu")
            #expect(headers["App-Request-Id"]?.hasSuffix("_11111111222233334444555555555555_AOS") == true)
        }
        #expect(signedHeaders(.hyundai)["X-Brand"] == "Hyundai")
        #expect(signedHeaders(.kia)["X-Brand"] == "Kia")
    }

    @Test("A signed body covers the body and drops Content-Length: 0")
    func testSignedBodyHeaders() {
        let body = #"{"refreshToken":"r"}"#
        var headers = signedHeaders(.hyundai, body: body)
        let own = headers.removeValue(forKey: "X-Fingerprint")
        #expect(headers["Content-Length"] == nil)
        #expect(own == EuropeCCIFingerprint.signature(
            headers: headers, keyPieces: EuropeCCIConfig.hyundai.fingerprintKey, body: body
        ))
    }

    @Test("Only 9035/9036/9037 on a 4xx count as gate rejections")
    func testGateRejectionCodes() {
        func body(_ code: Int) -> Data { Data(#"{"code":\#(code),"message":"x"}"#.utf8) }
        for code in [9035, 9036, 9037] {
            #expect(EuropeCCIFingerprint.isGateRejection(statusCode: 400, data: body(code)))
        }
        #expect(!EuropeCCIFingerprint.isGateRejection(statusCode: 400, data: body(9013)))
        #expect(!EuropeCCIFingerprint.isGateRejection(statusCode: 500, data: body(9035)))
        #expect(!EuropeCCIFingerprint.isGateRejection(statusCode: 200, data: body(9035)))
        #expect(!EuropeCCIFingerprint.isGateRejection(statusCode: 502, data: Data("upstream html error".utf8)))
    }
}
