//
//  Authentication.swift
//  BetterBlueKit
//
//  Authentication models
//

import Foundation

// MARK: - Authentication

public struct AuthToken: Codable, Sendable {
    public let accessToken: String, refreshToken: String
    public let expiresAt: Date, pin: String
    public let authCookie: String?

    public init(accessToken: String, refreshToken: String, expiresAt: Date, pin: String) {
        (self.accessToken, self.refreshToken, self.expiresAt, self.pin, self.authCookie) =
            (accessToken, refreshToken, expiresAt, pin, nil)
    }

    public init(
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        pin: String,
        authCookie: String?
    ) {
        (self.accessToken, self.refreshToken, self.expiresAt, self.pin, self.authCookie) =
            (accessToken, refreshToken, expiresAt, pin, authCookie)
    }

    enum CodingKeys: String, CodingKey {
        case accessToken, refreshToken, expiresAt, pin, authCookie
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        refreshToken = try container.decode(String.self, forKey: .refreshToken)
        expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        pin = try container.decode(String.self, forKey: .pin)
        authCookie = try container.decodeIfPresent(String.self, forKey: .authCookie)
    }

    public var isValid: Bool {
        Date() < expiresAt.addingTimeInterval(-300) // 5 minute buffer
    }
}
