//
//  APIClient.swift
//  BetterBlueKit
//
//  Core API Client Types and Protocols
//

import Foundation

// MARK: - Hyundai Canada API Variant

/// Which way the Hyundai Canada client presents itself to the backend.
/// Hyundai Canada's Cloudflare + endpoint behavior varies per user/IP, so
/// no single identity works for everyone — this lets a user pick the one
/// that connects for them (surfaced in the app as "Connection").
public enum HyundaiCanadaVariant: String, Codable, CaseIterable, Sendable {
    /// Web-portal login (`from: CWP` + a browser User-Agent) — clears
    /// Cloudflare for most users — paired with native-app headers on the
    /// `evc/fme` location endpoint (the combination a CA owner verified
    /// in BetterBlueKit#36).
    case webPortal
    /// Native-app identity everywhere (`from: SPA` + the MyHyundai iOS
    /// User-Agent) with the legacy `fndmcr` location endpoint — for users
    /// where Cloudflare blocks the web-portal identity but the app one
    /// works.
    case nativeApp

    public static var `default`: HyundaiCanadaVariant { .webPortal }

    public var displayName: String {
        switch self {
        case .webPortal: "Web Portal"
        case .nativeApp: "Native App"
        }
    }

    public var summary: String {
        switch self {
        case .webPortal: "Browser-style login (recommended). Best for clearing Cloudflare."
        case .nativeApp: "MyHyundai app-style login. Try this if Web Portal won't connect."
        }
    }
}

// MARK: - API Client Configuration

public struct APIClientConfiguration {
    public let region: Region
    public let brand: Brand
    public let username: String
    public let password: String
    public let refreshToken: String?
    public let pin: String
    public let accountId: UUID
    public let logSink: HTTPLogSink?
    public let rememberMeToken: String?
    public let redactPII: Bool
    public let deviceId: String?
    /// Hyundai Canada connection variant (ignored by other brands/regions).
    public let hyundaiCanadaVariant: HyundaiCanadaVariant
    /// Invoked when the API client observes that the server returned a
    /// rotated `rmToken` (or equivalent long-lived "remember-me" credential)
    /// in a login response. The caller is expected to persist the new
    /// value so subsequent `login()` calls present the latest token.
    /// Currently used only by `KiaUSAAPIClient`; other implementations
    /// may opt in by capturing their respective rotated tokens.
    public let onRememberMeTokenRotated: (@MainActor @Sendable (String) -> Void)?

    public init(
        region: Region,
        brand: Brand,
        username: String,
        password: String,
        refreshToken: String? = nil,
        pin: String,
        accountId: UUID,
        logSink: HTTPLogSink? = nil,
        rememberMeToken: String? = nil,
        redactPII: Bool = true,
        deviceId: String? = nil,
        hyundaiCanadaVariant: HyundaiCanadaVariant = .default,
        onRememberMeTokenRotated: (@MainActor @Sendable (String) -> Void)? = nil
    ) {
        self.region = region
        self.brand = brand
        self.username = username
        self.password = password
        self.refreshToken = refreshToken
        self.pin = pin
        self.accountId = accountId
        self.logSink = logSink
        self.rememberMeToken = rememberMeToken
        self.redactPII = redactPII
        self.deviceId = deviceId
        self.hyundaiCanadaVariant = hyundaiCanadaVariant
        self.onRememberMeTokenRotated = onRememberMeTokenRotated
    }

    public func with(deviceId: String? = nil, refreshToken: String? = nil) -> Self {
        .init(
            region: region,
            brand: brand,
            username: username,
            password: password,
            refreshToken: refreshToken ?? self.refreshToken,
            pin: pin,
            accountId: accountId,
            logSink: logSink,
            rememberMeToken: rememberMeToken,
            redactPII: redactPII,
            deviceId: deviceId ?? self.deviceId,
            hyundaiCanadaVariant: hyundaiCanadaVariant,
            onRememberMeTokenRotated: onRememberMeTokenRotated
        )
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

    /// Optional: Fetch specific EV trip info summary for a given date (not all brands/APIs support this)
    func fetchEVTripInfo(for vehicle: Vehicle, authToken: AuthToken, dateString: String) async throws -> [EVTripInfo]?

    /// Returns true if this API client implements `fetchEVTripDetails`
    func supportsEVTripDetails() -> Bool

    // MARK: - MFA Support (Optional)

    /// Returns true if this API client supports MFA (Multi-Factor Authentication)
    func supportsMFA() -> Bool

    /// Send MFA code via the specified method
    func sendMFACode(xid: String, otpKey: String, method: MFAMethod) async throws

    /// Verify the MFA code and get tokens for completing login
    func verifyMFACode(xid: String, otpKey: String, code: String) async throws -> (rememberMeToken: String, sid: String)

    /// Complete login after MFA verification
    func completeMFALogin(sid: String, rmToken: String) async throws -> AuthToken

    /// Register device
    func registerDevice() async throws -> String?
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

    public func fetchEVTripInfo(for vehicle: Vehicle, authToken: AuthToken, dateString: String) async throws -> [EVTripInfo]? {
        nil
    }

    public func supportsEVTripDetails() -> Bool {
        false
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

    /// default because otherwise FakeAPIClient throws error when calling this func in Account
    public func registerDevice() async throws -> String? {
        UUID().uuidString.uppercased()
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
