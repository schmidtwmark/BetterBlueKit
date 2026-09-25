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
    public let refreshToken: String?
    public let pin: String
    public let accountId: UUID
    public let logSink: HTTPLogSink?
    public let rememberMeToken: String?
    public let redactPII: Bool
    public let deviceId: String?
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

    /// Optional: Fetch EV trip summary for a vehicle (not all brands/APIs support this)
    func fetchEVTripSummary(for vehicle: Vehicle, authToken: AuthToken) async throws -> [EVTripSummary]?

    /// Optional: Fetch specific EV trip info summary for a given date (not all brands/APIs support this)
    func fetchEVTripInfo(for vehicle: Vehicle, authToken: AuthToken, date: Date) async throws -> [EVTripInfo]?

    /// Optional: Ask the vehicle to take a fresh surround-view capture.
    /// Returns as soon as the request is accepted — the vehicle then
    /// wakes its cameras, shoots, and uploads, which takes minutes.
    /// Poll `fetchSurroundViewCaptures` for the result.
    func requestSurroundViewCapture(for vehicle: Vehicle, authToken: AuthToken) async throws

    /// Optional: Fetch the surround-view captures the server currently
    /// holds for a vehicle, newest first. Never triggers a new capture.
    ///
    /// Captures may come back WITHOUT imagery (`isLoaded == false`) where
    /// a region bills for it per capture — see `fetchSurroundViewImagery`.
    func fetchSurroundViewCaptures(for vehicle: Vehicle, authToken: AuthToken) async throws -> [SurroundViewCapture]

    /// Optional: Fill in one capture's imagery.
    ///
    /// Exists because regions differ in what a listing costs. Hyundai
    /// returns every image inline, so its captures arrive loaded and this
    /// is a no-op. Kia lists captures cheaply and bills a separate
    /// request plus a few hundred KB per image, so it returns all but the
    /// newest as metadata only and loads the rest on demand — which is
    /// what lets the monitor screen open on one image instead of ten.
    ///
    /// Returns the capture unchanged when it is already loaded or the
    /// region has nothing more to fetch, so callers can call it freely.
    func fetchSurroundViewImagery(
        for capture: SurroundViewCapture,
        vehicle: Vehicle,
        authToken: AuthToken
    ) async throws -> SurroundViewCapture

    /// The optional capabilities this client implements, beyond the required
    /// protocol surface. Clients override this single method; callers use the
    /// convenience helpers (`supportsMFA()`, `supportedEVTripTypes()`) instead
    /// of inspecting the list directly.
    func optionalFeaturesSupported() -> [OptionalAPIFeature]

    // MARK: - MFA Support (Optional)

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

// MARK: - EV Trip Type

public enum EVTripType: String, Codable, Sendable {
    case summary
    case info
}

// MARK: - Optional Features

/// The optional capabilities an API client can declare via
/// `optionalFeaturesSupported()`. One list covers everything so adding a
/// capability means adding a case here plus a helper below — client
/// conformances and app code keep working unchanged.
public enum OptionalAPIFeature: String, Codable, Sendable, CaseIterable {
    /// Multi-factor authentication (send/verify/complete MFA login).
    case mfa
    /// Day- or trip-level driving history (`fetchEVTripSummary`).
    case evTripSummary
    /// Per-trip drill-down for a specific date (`fetchEVTripInfo`).
    case evTripInfo
    /// Can show the 360° camera stills the server is holding
    /// (`fetchSurroundViewCaptures`). This is what puts the Surround View
    /// item in the vehicle menu.
    case surroundView
    /// Can ask the vehicle to take a NEW 360° capture
    /// (`requestSurroundViewCapture`).
    ///
    /// Separate from `.surroundView` because the two do not always come
    /// together: Kia US can list and show captures the vehicle has
    /// already uploaded, but its capture trigger is not known, so it
    /// declares the gallery without the trigger and the app hides the
    /// "New Capture" affordance. A client that can trigger must also be
    /// able to fetch, so declare both.
    case surroundViewCapture
}

// MARK: - Default Implementations

extension APIClientProtocol {
    public func fetchEVTripSummary(for vehicle: Vehicle, authToken: AuthToken) async throws -> [EVTripSummary]? {
        nil
    }

    public func fetchEVTripInfo(for vehicle: Vehicle, authToken: AuthToken, date: Date) async throws -> [EVTripInfo]? {
        nil
    }

    public func requestSurroundViewCapture(for vehicle: Vehicle, authToken: AuthToken) async throws {
        throw APIError(message: "Surround view not supported for this API", apiName: "APIClient")
    }

    public func fetchSurroundViewCaptures(
        for vehicle: Vehicle,
        authToken: AuthToken
    ) async throws -> [SurroundViewCapture] {
        []
    }

    /// Default: nothing more to fetch. Correct for every region that
    /// returns imagery inline with the listing.
    public func fetchSurroundViewImagery(
        for capture: SurroundViewCapture,
        vehicle _: Vehicle,
        authToken _: AuthToken
    ) async throws -> SurroundViewCapture {
        capture
    }

    public func optionalFeaturesSupported() -> [OptionalAPIFeature] {
        []
    }

    /// Returns true if this API client supports MFA (Multi-Factor Authentication)
    public func supportsMFA() -> Bool {
        optionalFeaturesSupported().contains(.mfa)
    }

    /// Returns true if this API client can retrieve the surround-view
    /// captures the server is holding.
    public func supportsSurroundView() -> Bool {
        optionalFeaturesSupported().contains(.surroundView)
    }

    /// Returns true if this API client can ask the vehicle for a NEW
    /// surround-view capture. Always a subset of `supportsSurroundView()`.
    public func supportsSurroundViewCapture() -> Bool {
        optionalFeaturesSupported().contains(.surroundViewCapture)
    }

    /// Returns the types of EV trip details this API client supports
    public func supportedEVTripTypes() -> [EVTripType] {
        var types: [EVTripType] = []
        let features = optionalFeaturesSupported()
        if features.contains(.evTripSummary) { types.append(.summary) }
        if features.contains(.evTripInfo) { types.append(.info) }
        return types
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

/// Minutes left in the active charge session, from a Kia USA-style
/// `remainChargeTime` array of
/// `{remainChargeType, timeInterval: {value, unit}}` entries
/// (unit 4 = minutes).
///
/// Unplugged, the array is a set of what-if estimates in no fixed
/// order — types 1 / 2 / 3 appear to be DC fast, portable (L1) and
/// L2 station. Plugged in, it collapses to a single entry: type 3
/// on a charging Niro EV (and an idle, plugged-in EV6), type 4 on a
/// charging ccNC EV9. So use the sole entry, or a type-4 entry if
/// one turns up alongside estimates. Never guess by index:
/// unplugged, index 0 is often the DC estimate.
func remainingChargeMinutes(in rawEntries: Any?) -> Double {
    let entries: [(type: Int?, minutes: Double)] = (rawEntries as? [[String: Any]] ?? [])
        .compactMap { entry in
            let interval = entry["timeInterval"] as? [String: Any]
            guard let minutes: Double = extractNumber(from: interval?["value"]) else { return nil }
            return (extractNumber(from: entry["remainChargeType"]), minutes)
        }
    let session = entries.count == 1 ? entries.first : entries.first { $0.type == 4 }
    return max(0, session?.minutes ?? 0)
}
