//
//  APIClientRedaction.swift
//  BetterBlueKit
//
//  Data redaction utilities for sensitive data
//

import Foundation

// MARK: - Public Redaction Utility

/// Public utility for redacting sensitive data from JSON strings
public enum SensitiveDataRedactor {
    /// Redacts sensitive data from a JSON string including passwords, tokens, locations, emails, and VINs
    public static func redact(_ text: String?) -> String? {
        guard let text else { return nil }

        var redacted = text

        // Redact common password/PIN patterns in JSON
        // Pattern matches the key and value, replacement preserves proper JSON format
        redacted = redacted.replacingOccurrences(
            of: #""(password|pin|PIN)"\s*:\s*"[^"]*""#,
            with: "\"$1\" : \"[REDACTED]\"",
            options: .regularExpression
        )

        // Redact Bearer tokens
        redacted = redacted.replacingOccurrences(
            of: #"Bearer\s+[A-Za-z0-9._-]+"#,
            with: "Bearer [REDACTED]",
            options: .regularExpression
        )

        // Redact token patterns (handles escaped quotes in values with (?:[^"\\]|\\.)*)
        let tokenKeys = "access_token|refresh_token|accessToken|refreshToken|serializedAuthToken|rememberMeToken"
        redacted = redacted.replacingOccurrences(
            of: #""(\#(tokenKeys))"\s*:\s*"(?:[^"\\]|\\.)*""#,
            with: "\"$1\" : \"[REDACTED]\"",
            options: .regularExpression
        )

        // Redact latitude/longitude coordinates to protect user location privacy
        redacted = redacted.replacingOccurrences(
            of: #""(latitude|longitude|lat|lng|lon)"\s*:\s*[-+]?\d+\.?\d*"#,
            with: "\"$1\" : \"[REDACTED]\"",
            options: .regularExpression
        )

        // Redact coordinate pairs in arrays or objects
        redacted = redacted.replacingOccurrences(
            of: #"[-+]?\d{1,3}\.\d{3,10}\s*,\s*[-+]?\d{1,3}\.\d{3,10}"#,
            with: "[LOCATION_REDACTED]",
            options: .regularExpression
        )

        // Redact email addresses (keep first char, domain TLD)
        redacted = redacted.replacingOccurrences(
            of: #""(username|email)"\s*:\s*"([^"@])[^"@]*@[^".]*(\.[^"]+)""#,
            with: "\"$1\" : \"$2***@***$3\"",
            options: .regularExpression
        )

        // Redact VIN numbers (17 characters, keep first 3 and last 4)
        redacted = redacted.replacingOccurrences(
            of: #""(vin|VIN)"\s*:\s*"([A-HJ-NPR-Z0-9]{3})[A-HJ-NPR-Z0-9]{10}([A-HJ-NPR-Z0-9]{4})""#,
            with: "\"$1\" : \"$2**********$3\"",
            options: .regularExpression
        )

        // Redact regId (vehicle registration ID)
        redacted = redacted.replacingOccurrences(
            of: #""(regId|regID)"\s*:\s*"[^"]*""#,
            with: "\"$1\" : \"[REDACTED]\"",
            options: .regularExpression
        )

        return redacted
    }

    /// Redacts sensitive HTTP headers
    public static func redactHeaders(_ headers: [String: String]) -> [String: String] {
        var redactedHeaders = headers

        // Redact Authorization headers
        if redactedHeaders["Authorization"] != nil {
            redactedHeaders["Authorization"] = "Bearer [REDACTED]"
        }
        if redactedHeaders["authorization"] != nil {
            redactedHeaders["authorization"] = "Bearer [REDACTED]"
        }

        // Redact any other authentication headers
        for (key, _) in redactedHeaders {
            if key.lowercased().contains("auth") ||
                key.lowercased().contains("token") {
                redactedHeaders[key] = "[REDACTED]"
            }
        }

        return redactedHeaders
    }
}

// MARK: - APIClient Extension (for backward compatibility)

extension APIClient {
    func redactSensitiveData(in text: String?) -> String? {
        SensitiveDataRedactor.redact(text)
    }

    func redactSensitiveHeaders(_ headers: [String: String]) -> [String: String] {
        SensitiveDataRedactor.redactHeaders(headers)
    }
}
