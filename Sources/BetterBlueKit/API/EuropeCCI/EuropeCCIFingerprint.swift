//
//  EuropeCCIFingerprint.swift
//  BetterBlueKit
//
//  X-Fingerprint request signing for the EU CCI auth endpoints.
//
//  Since 2026-10-13/14 the cci-api-eu auth endpoints (auth-code exchange,
//  CCS token exchange, token refresh) reject unsigned POSTs with
//  `{"code": 9035, "message": "Unusual activity has been detected…"}`
//  (BetterBlue#122). The OneApp signs those calls with an HMAC-SHA256
//  `X-Fingerprint` header. This ports hyundai_kia_connect_api's
//  `cci_fingerprint.py` (PR #1352, v4.35.3), which recovered the scheme
//  from the Android OneApp 1.4.0 build and verified it live on both brands.
//

import CryptoKit
import Foundation

enum EuropeCCIFingerprint {

    // MARK: OneApp build identity

    /// The Android OneApp build the signing constants came from. The gate
    /// checks the signature against the identity headers, so these must
    /// stay in step with `EuropeCCIConfig.fingerprintKey` — when the
    /// constants rotate with an app release, both change together.
    static let clientVersion = "1.4.0"
    static let clientOSCode = "android"
    static let clientOSVersion = "14"
    static let clientDeviceModel = "SM-S918B"
    static let notificationProvider = "FCM"
    static let userAgent = "okhttp/4.12.0"
    static let appRegion = "eu"

    // MARK: Gate rejections

    /// The gate's own rejections: 9035 header missing, 9036 bad signature,
    /// 9037 timestamp out of window (~120 s, checked before the signature).
    static let gateRejectionCodes: Set<Int> = [9035, 9036, 9037]

    /// True when a CCI response is one of the gate's rejections. Anything
    /// else — a 5xx, or a business error such as 9013 (invalid code) or
    /// 9030 (token expired) — is a real failure of the signed call.
    static func isGateRejection(statusCode: Int, data: Data) -> Bool {
        guard (400 ..< 500).contains(statusCode), let code = errorCode(in: data) else { return false }
        return gateRejectionCodes.contains(code)
    }

    /// The numeric `code` of a CCI error body (`{"code": 9035, "message": …}`).
    static func errorCode(in data: Data) -> Int? {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return json?["code"] as? Int
    }

    // MARK: Signing

    private static let identityHeaders = ["client-id", "client-name", "client-version", "client-os-code"]

    /// HMAC-SHA256, lowercase hex.
    ///
    /// - Key: client-id + client-name + client-version + client-os-code,
    ///   then the brand's secret pieces.
    /// - Message: the same identity + client-os-version + X-Timestamp +
    ///   the request body with ASCII whitespace removed.
    ///
    /// `body` must be the exact body sent, or empty for a bodyless POST.
    static func signature(headers: [String: String], keyPieces: [String], body: String = "") -> String {
        var lowered: [String: String] = [:]
        for (name, value) in headers {
            lowered[name.lowercased()] = value
        }
        let identity = identityHeaders.map { lowered[$0] ?? "" }.joined()
        let message = identity
            + (lowered["client-os-version"] ?? "")
            + (lowered["x-timestamp"] ?? "")
            + strippingASCIIWhitespace(body)
        let key = SymmetricKey(data: Data((identity + keyPieces.joined()).utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    /// Removes what Java's (and Python's ASCII-mode) `\s` matches: space,
    /// tab, LF, VT, FF, CR. Unicode whitespace stays, as the app leaves it.
    static func strippingASCIIWhitespace(_ body: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: body.unicodeScalars.filter { !asciiWhitespace.contains($0) })
        return String(scalars)
    }

    private static let asciiWhitespace: Set<Unicode.Scalar> = [" ", "\t", "\n", "\u{0B}", "\u{0C}", "\r"]
}
