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

    public init(accessToken: String, refreshToken: String, expiresAt: Date, pin: String) {
        (self.accessToken, self.refreshToken, self.expiresAt, self.pin) = (accessToken, refreshToken, expiresAt, pin)
    }

    public var isValid: Bool {
        Date() < expiresAt.addingTimeInterval(-300) // 5 minute buffer
    }
}
