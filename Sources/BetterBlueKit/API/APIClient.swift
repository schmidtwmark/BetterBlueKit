//
//  APIClient.swift
//  BetterBlueKit
//
//  Core API Client Types and Protocols
//

import Foundation

// MARK: - API Client Configuration

public struct APIClientConfiguration {
    public let region: Region
    public let brand: Brand
    public let username: String
    public let password: String
    public let pin: String
    public let accountId: UUID
    public let logSink: HTTPLogSink?
    public let rememberMeToken: String?
    public let redactPII: Bool
    public let deviceId: String?

    public init(
        region: Region,
        brand: Brand,
        username: String,
        password: String,
        pin: String,
        accountId: UUID,
        logSink: HTTPLogSink? = nil,
        rememberMeToken: String? = nil,
        redactPII: Bool = true,
        deviceId: String? = nil
    ) {
        self.region = region
        self.brand = brand
        self.username = username
        self.password = password
        self.pin = pin
        self.accountId = accountId
        self.logSink = logSink
        self.rememberMeToken = rememberMeToken
        self.redactPII = redactPII
        self.deviceId = deviceId
    }
}

// MARK: - API Client Protocol

/// Protocol for communicating with Kia/Hyundai API
@MainActor
public protocol APIClientProtocol {
    func login() async throws -> AuthToken
    func fetchVehicles(authToken: AuthToken) async throws -> [Vehicle]
    /// Fetch the latest status for a vehicle.
    /// - Parameter cached: When true, return the server-cached snapshot (cheap, instant).
    ///   When false, request a real-time poll from the vehicle (slow, wakes the modem,
    ///   may be rate-limited). Manual user-initiated refreshes and post-command
    ///   verification should pass `false`; widget timelines and background refreshes
    ///   should pass `true`. Brands that don't expose a real-time endpoint may treat
    ///   both modes identically.
    func fetchVehicleStatus(for vehicle: Vehicle, authToken: AuthToken, cached: Bool) async throws -> VehicleStatus
    func sendCommand(for vehicle: Vehicle, command: VehicleCommand, authToken: AuthToken) async throws

    /// Optional: Fetch EV trip details for a vehicle (not all brands/APIs support this)
    func fetchEVTripDetails(for vehicle: Vehicle, authToken: AuthToken) async throws -> [EVTripDetail]?

    // MARK: - MFA Support (Optional)

    /// Returns true if this API client supports MFA (Multi-Factor Authentication)
    func supportsMFA() -> Bool

    /// Send MFA code via the specified method
    func sendMFACode(xid: String, otpKey: String, method: MFAMethod) async throws

    /// Verify the MFA code and get tokens for completing login
    func verifyMFACode(xid: String, otpKey: String, code: String) async throws -> (rememberMeToken: String, sid: String)

    /// Complete login after MFA verification
    func completeMFALogin(sid: String, rmToken: String) async throws -> AuthToken
}

// MARK: - MFA Method

public enum MFAMethod: String, Sendable {
    case email
    case sms
}

// MARK: - Default Implementations

extension APIClientProtocol {
    public func fetchEVTripDetails(for vehicle: Vehicle, authToken: AuthToken) async throws -> [EVTripDetail]? {
        nil
    }

    public func supportsMFA() -> Bool {
        false
    }

    public func sendMFACode(xid: String, otpKey: String, method: MFAMethod) async throws {
        throw APIError(message: "MFA not supported for this API", apiName: "APIClient")
    }

    public func verifyMFACode(
        xid: String,
        otpKey: String,
        code: String
    ) async throws -> (rememberMeToken: String, sid: String) {
        throw APIError(message: "MFA not supported for this API", apiName: "APIClient")
    }

    public func completeMFALogin(sid: String, rmToken: String) async throws -> AuthToken {
        throw APIError(message: "MFA not supported for this API", apiName: "APIClient")
    }

    /// Convenience overload — defaults to cached fetch.
    public func fetchVehicleStatus(
        for vehicle: Vehicle,
        authToken: AuthToken
    ) async throws -> VehicleStatus {
        try await fetchVehicleStatus(for: vehicle, authToken: authToken, cached: true)
    }
}

// MARK: - HTTP Method

public enum HTTPMethod: String, Sendable {
    case GET
    case POST
    case PUT
    case DELETE
}

// MARK: - Helper Functions

func extractNumber<T: LosslessStringConvertible>(from value: Any?) -> T? {
    guard let value = value else { return nil }
    if let num = value as? T { return num }
    if let numString = value as? String { return T(numString) }
    return nil
}
