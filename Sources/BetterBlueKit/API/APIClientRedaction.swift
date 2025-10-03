//
//  APIClientRedaction.swift
//  BetterBlueKit
//
//  Data redaction utilities for APIClient
//

import Foundation

// MARK: - Data Redaction Extensions

extension APIClient {
    func redactSensitiveData(in text: String?) -> String? {
        guard let text else { return nil }

        var redacted = text

        // Redact common password/PIN patterns in JSON
        redacted = redacted.replacingOccurrences(
            of: #"("password"|"pin"|"PIN")\s*:\s*"[^"]*""#,
            with: "$1\":\"[REDACTED]\"",
            options: .regularExpression,
        )

        // Redact Bearer tokens
        redacted = redacted.replacingOccurrences(
            of: #"Bearer\s+[A-Za-z0-9._-]+"#,
            with: "Bearer [REDACTED]",
            options: .regularExpression,
        )

        // Redact other token patterns
        redacted = redacted.replacingOccurrences(
            of: #"("access_token"|"refresh_token"|"accessToken"|"refreshToken")\s*:\s*"[^"]*""#,
            with: "$1\":\"[REDACTED]\"",
            options: .regularExpression,
        )

        // Redact latitude/longitude coordinates to protect user location privacy
        redacted = redacted.replacingOccurrences(
            of: #"("latitude"|"longitude"|"lat"|"lng"|"lon")\s*:\s*[-+]?\d+\.?\d*"#,
            with: "$1\":[REDACTED]",
            options: .regularExpression,
        )

        // Redact coordinate pairs in arrays or objects
        redacted = redacted.replacingOccurrences(
            of: #"[-+]?\d{1,3}\.\d{3,10}\s*,\s*[-+]?\d{1,3}\.\d{3,10}"#,
            with: "[LOCATION_REDACTED]",
            options: .regularExpression,
        )

        return redacted
    }

    func redactSensitiveHeaders(_ headers: [String: String]) -> [String: String] {
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
