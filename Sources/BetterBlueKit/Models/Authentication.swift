//
//  Authentication.swift
//  BetterBlueKit
//
//  Authentication models
//

import Foundation

// MARK: - Authentication

public struct AuthToken: Codable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date

    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    public var isValid: Bool {
        Date() < expiresAt.addingTimeInterval(-300) // 5 minute buffer
    }
}
