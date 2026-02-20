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
    public let expiresAt: Date

    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        (self.accessToken, self.refreshToken, self.expiresAt) = (accessToken, refreshToken, expiresAt)
    }

    public var isValid: Bool {
        Date() < expiresAt.addingTimeInterval(-300) // 5 minute buffer
    }
}
