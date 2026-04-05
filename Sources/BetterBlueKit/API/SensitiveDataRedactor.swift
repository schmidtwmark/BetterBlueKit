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
            "TransactionId", "Cookie", "__cf_bm", "otpKey"
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
            "billingAccountNumber", "enrollmentId", "enrollmentCode",
            "deviceKey", "deviceid", "clientuuid"
        ].joined(separator: "|")

        return [
            // Passwords and PINs
            (#""(password|pin|PIN)"\s*:\s*"[^"]*""#,
             "\"$1\":\"[REDACTED]\""),
            // Bearer tokens
            (#"Bearer\s+[A-Za-z0-9._-]+"#,
             "Bearer [REDACTED]"),
            // Token/secret fields (handles escaped quotes)
            (#""(\#(tokenKeys))"\s*:\s*"(?:[^"\\]|\\.)*""#,
             "\"$1\":\"[REDACTED]\""),
            // Latitude/longitude coordinates
            (#""(latitude|longitude|lat|lng|lon)"\s*:\s*[-+]?\d+\.?\d*"#,
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
            // Account/user/device IDs
            (#""(\#(idKeys))"\s*:\s*"[^"]*""#,
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

    /// Redacts sensitive HTTP headers
    public static func redactHeaders(_ headers: [String: String]) -> [String: String] {
        // Keys that should always be fully redacted (case-insensitive match)
        let sensitiveKeys: Set<String> = [
            "cookie", "set-cookie", "__cf_bm", "transactionid",
            "password", "pin", "bluelinkservicepin",
            "clientsecret", "client_secret", "secretkey"
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
