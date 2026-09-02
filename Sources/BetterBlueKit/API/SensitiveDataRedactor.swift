//
//  SensitiveDataRedactor.swift
//  BetterBlueKit
//
//  Data redaction utilities for sensitive data
//

import Foundation

// MARK: - Public Redaction Utility

/// Public utility for redacting sensitive data from JSON strings
public enum SensitiveDataRedactor {

    private static let redactionRules: [(pattern: String, replacement: String)] = {
        let tokenKeys = [
            "access_token", "refresh_token", "accessToken", "refreshToken",
            "serializedAuthToken", "rememberMeToken", "Accesstoken", "Pauth",
            "TransactionId", "Cookie", "__cf_bm", "otpKey", "otpValidationKey",
            // EU OneApp/CCI token set (login + token-refresh bodies)
            "exchangeableAccessToken", "exchangeableRefreshToken",
            "nonCcsToken", "nonCcsRefreshToken", "idToken", "ccsAccessToken"
        ].joined(separator: "|")

        let emailKeys = [
            "username", "email", "userId", "loginId", "notificationEmail"
        ].joined(separator: "|")

        let phoneKeys = [
            "phone", "phoneNumber", "mobileNumber", "cellPhone",
            "telematicsPhoneNumber", "number"
        ].joined(separator: "|")

        let idKeys = [
            "accountId", "account_id", "userId", "user_id",
            "memberId", "member_id", "idmId", "nadid",
            "billingAccountNumber", "enrollmentId", "enrollmentCode"
        ].joined(separator: "|")

        // Device identifiers get partial masking instead of the blanket
        // redaction above — see the rule below for why.
        let deviceKeys = [
            "deviceid", "deviceId", "deviceKey", "clientuuid"
        ].joined(separator: "|")

        return [
            // Passwords, PINs, and one-time codes (otpNo is the code the
            // user types into the MFA prompt — never include it in a report)
            (#""(password|pin|PIN|otpNo)"\s*:\s*"[^"]*""#,
             "\"$1\":\"[REDACTED]\""),
            // Bearer tokens
            (#"Bearer\s+[A-Za-z0-9._-]+"#,
             "Bearer [REDACTED]"),
            // Form-encoded credentials — the EU IDPConnect signin POSTs
            // application/x-www-form-urlencoded, which the JSON rules
            // never match. Case-sensitive, so `encryptedPassword=true`
            // (a flag, not a secret) is left alone.
            (#"(?:^|(?<=&))(password|username)=[^&]*"#,
             "$1=[REDACTED]"),
            // OAuth authorization codes riding in a URL query (the EU CCI
            // token exchange puts the signin code in `?code=…`).
            (#"(?<=[?&])code=[^&\s"']+"#,
             "code=[REDACTED]"),
            // Token/secret fields (handles escaped quotes)
            (#""(\#(tokenKeys))"\s*:\s*"(?:[^"\\]|\\.)*""#,
             "\"$1\":\"[REDACTED]\""),
            // Latitude/longitude coordinates. Two spellings are accepted:
            // the bare keys, and any camelCase key ENDING in one of them —
            // the surround-view payload reports position as
            // `gpsDetail.coordLat` / `coordLon`, which the bare-key rule
            // alone let through into persisted logs and debug exports.
            // Requiring a capital on the prefixed form keeps innocent words
            // like "flat" and "gallon" from matching.
            //
            // The value alternation is quoted-OR-bare rather than a pair of
            // optional quotes: independent `"?` would happily match the
            // opening quote of `"43.6abc"` and stop at the digits, leaving
            // the tail behind as `"[REDACTED]"abc"` — malformed JSON in a
            // persisted log and in every debug export built from it.
            (#""((?:latitude|longitude|lat|lng|lon)|\w+(?:Latitude|Longitude|Lat|Lng|Lon))"\s*:\s*(?:"[-+]?\d+\.?\d*"|[-+]?\d+\.?\d*)"#,
             "\"$1\":\"[REDACTED]\""),
            // Coordinate pairs in arrays or objects
            (#"[-+]?\d{1,3}\.\d{3,10}\s*,\s*[-+]?\d{1,3}\.\d{3,10}"#,
             "[LOCATION_REDACTED]"),
            // Names
            (#""(firstName|lastName)"\s*:\s*"[^"]*""#,
             "\"$1\":\"[REDACTED]\""),
            // Email addresses in JSON fields (keep first char + TLD)
            (#""(\#(emailKeys))"\s*:\s*"([^"@])[^"@]*@[^".]*(\.[^"]+)""#,
             "\"$1\":\"$3***@***$4\""),
            // Emails embedded in URL paths
            (#"(\/)[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#,
             "$1[EMAIL_REDACTED]"),
            // Phone numbers
            (#""(\#(phoneKeys))"\s*:\s*"[^"]*""#,
             "\"$1\":\"[REDACTED]\""),
            // Account/user IDs
            (#""(\#(idKeys))"\s*:\s*"[^"]*""#,
             "\"$1\":\"[REDACTED]\""),
            // Device identifiers — partially masked rather than blanked, so a
            // reader can tell whether the id CHANGED between requests. A
            // rotating device id is the signature of the Hyundai Canada MFA
            // loop (BetterBlue#95): that region has no refresh endpoint, so
            // the `deviceid` header is the only thing letting the backend
            // recognize an install and skip the OTP challenge. Fully redacting
            // it made "stable" and "rotating every session" look identical in
            // a bug report. Same trade-off as the VIN rule below: a device id
            // is an opaque installation identifier, not a credential, and is
            // useless without the password/tokens that stay redacted.
            // Keeps the first 8 and last 4 characters.
            (#""(\#(deviceKeys))"\s*:\s*"([A-Za-z0-9]{8})[A-Za-z0-9._-]*([A-Za-z0-9]{4})""#,
             "\"$1\":\"$2…$3\""),
            // Fallback: a device id too short to partially mask is still
            // blanked. The `…` exclusion keeps this from re-redacting a value
            // the rule above already masked.
            (#""(\#(deviceKeys))"\s*:\s*"[^"…]*""#,
             "\"$1\":\"[REDACTED]\""),
            // Physical address fields
            (#""(street|postalCode)"\s*:\s*"[^"]*""#,
             "\"$1\":\"[REDACTED]\""),
            // VIN numbers (keep first 3 and last 4)
            (#""(vin|VIN)"\s*:\s*"([A-HJ-NPR-Z0-9]{3})[A-HJ-NPR-Z0-9]{10}([A-HJ-NPR-Z0-9]{4})""#,
             "\"$1\":\"$2**********$3\""),
            // Registration IDs
            (#""(regId|regID|regid)"\s*:\s*"[^"]*""#,
             "\"$1\":\"[REDACTED]\"")
        ]
    }()

    /// Redacts sensitive data from a JSON string including passwords, tokens, locations, emails, and VINs
    public static func redact(_ text: String?) -> String? {
        guard let text else { return nil }

        var redacted = text
        for rule in redactionRules {
            redacted = redacted.replacingOccurrences(
                of: rule.pattern,
                with: rule.replacement,
                options: .regularExpression
            )
        }
        return redacted
    }

    /// Replaces JSON string values longer than `threshold` with a note
    /// of their length, leaving the surrounding structure intact.
    ///
    /// Surround-view responses carry megabytes of base64 JPEG in a single
    /// field. HTTP logs are persisted to SwiftData, synced, and bundled
    /// into debug exports, so storing that verbatim would bloat all three
    /// — and the imagery tells a reader nothing the metadata doesn't.
    public static func elideOversizedValues(_ text: String?, threshold: Int = 4096) -> String? {
        guard let text else { return nil }
        guard text.utf8.count > threshold else { return text }

        let quote = UInt8(ascii: "\"")
        let backslash = UInt8(ascii: "\\")
        let bytes = Array(text.utf8)

        var output: [UInt8] = []
        output.reserveCapacity(bytes.count / 2)

        var index = 0
        while index < bytes.count {
            guard bytes[index] == quote else {
                output.append(bytes[index])
                index += 1
                continue
            }

            // Walk to the closing quote, honoring backslash escapes.
            var cursor = index + 1
            var escaped = false
            while cursor < bytes.count {
                let byte = bytes[cursor]
                if escaped {
                    escaped = false
                } else if byte == backslash {
                    escaped = true
                } else if byte == quote {
                    break
                }
                cursor += 1
            }

            guard cursor < bytes.count else {
                // Unterminated string — copy the remainder verbatim.
                output.append(contentsOf: bytes[index...])
                break
            }

            let length = cursor - index - 1
            if length > threshold {
                output.append(contentsOf: Array("\"[\(length) characters elided]\"".utf8))
            } else {
                output.append(contentsOf: bytes[index ... cursor])
            }
            index = cursor + 1
        }

        // Cutting only at quote bytes keeps multi-byte scalars intact, so
        // this should never fail. If it somehow does, drop the body: the
        // obvious fallback — returning `text` — would log the exact
        // megabytes of base64 this function exists to remove.
        return String(bytes: output, encoding: .utf8) ?? "[body omitted: could not be decoded]"
    }

    /// Redacts sensitive HTTP headers
    public static func redactHeaders(_ headers: [String: String]) -> [String: String] {
        // Keys that should always be fully redacted (case-insensitive match)
        let sensitiveKeys: Set<String> = [
            "cookie", "set-cookie", "__cf_bm", "transactionid",
            "password", "pin", "bluelinkservicepin",
            "clientsecret", "client_secret", "secretkey",
            // The EU CCI signin answers with a 302 whose Location query
            // carries the live OAuth authorization code.
            "location"
        ]

        var redactedHeaders = headers

        for (key, _) in headers {
            let lowerKey = key.lowercased()

            // Authorization headers get special treatment (keep "Bearer" prefix)
            if lowerKey == "authorization" {
                redactedHeaders[key] = "Bearer [REDACTED]"
            }
            // Check for exact matches in sensitive keys
            else if sensitiveKeys.contains(lowerKey) {
                redactedHeaders[key] = "[REDACTED]"
            }
            // Check for substring matches (auth, token, pauth, etc.)
            else if lowerKey.contains("auth") || lowerKey.contains("token") {
                redactedHeaders[key] = "[REDACTED]"
            }
        }

        return redactedHeaders
    }
}
