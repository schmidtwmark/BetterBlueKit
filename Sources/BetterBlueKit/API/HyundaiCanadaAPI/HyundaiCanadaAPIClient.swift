//
//  HyundaiCanadaAPIClient.swift
//  BetterBlueKit
//
//  Hyundai Canada API Client
//

import Foundation

// MARK: - Hyundai Canada API Client

@MainActor
public final class HyundaiCanadaAPIClient: APIClientBase, APIClientProtocol {

    // MARK: - Constants

    let clientId = "HATAHSPACA0232141ED9722C67715A0B"
    let clientSecret = "CLISCR01AHSPA"
    let userAgent = "MyHyundai/2.0.25 (iPhone; iOS 18.3; Scale/3.00)"

    /// Stable per-account device ID. Hyundai Canada's anti-fraud
    /// challenge fires every time a "new device" logs in — using a
    /// fresh random UUID per session guarantees the user sees an OTP
    /// challenge (errorCode 7110) on every login. `BBAccount` already
    /// generates and persists a stable UUID per account; honor that
    /// when present, fall back to a random UUID only if the host
    /// didn't supply one (e.g. bbcli without a stored config).
    /// (Matches the hyundai_kia_connect_api Python reference, which
    /// derives a deterministic device ID from MAC + hostname for the
    /// same reason.)
    lazy var deviceId: String = configuration.deviceId ?? UUID().uuidString.uppercased()

    let hvacFahrenheitValues: [Double] = Array(62...82).map { Double($0) }
    let hvacCelsiusValues: [Double] = [
        17, 17.5, 18, 18.5, 19, 19.5, 20, 20.5, 21, 21.5, 22, 22.5,
        23, 23.5, 24, 24.5, 25, 25.5, 26, 26.5, 27
    ]
    let hvacEncodedValues: [String] = [
        "06H", "07H", "08H", "09H", "0AH", "0BH", "0CH", "0DH", "0EH", "0FH",
        "10H", "11H", "12H", "13H", "14H", "15H", "16H", "17H", "18H", "19H", "1AH"
    ]

    var cloudFlareCookie: String?

    // MARK: - MFA Flow State
    //
    // Hyundai Canada's MFA differs slightly from Kia USA's: the OTP key
    // is only issued AFTER the user picks email/SMS (Kia returns it in
    // the initial challenge). We stash everything we learn at each step
    // here so the protocol's three-method MFA contract still works.
    /// `userInfoUuid` returned by `mfa/selverifmeth`. Surfaced as `xid`
    /// in the `requiresMFA` error and threaded through every later call.
    var mfaUserInfoUuid: String?
    /// Email associated with the account, returned by `selverifmeth` and
    /// echoed back by `sendotp` / `genmfatkn`.
    var mfaEmail: String?
    /// `otpKey` returned by `mfa/sendotp`, consumed by `mfa/validateotp`.
    var mfaOtpKey: String?
    /// Last-4 (or full, depending on server) of the SMS number echoed
    /// by `selverifmeth`. Threaded back into `sendotp` for the SMS
    /// delivery path.
    var mfaPhone: String?
    /// Final auth token built from `mfa/genmfatkn`'s response. Returned
    /// from `completeMFALogin` so the caller never sees the multi-step
    /// dance under the hood.
    var mfaCompletedAuthToken: AuthToken?

    var baseURL: String { region.apiBaseURL(for: .hyundai) }
    var apiBaseURL: String { "\(baseURL)/tods/api" }
    var apiHost: String { "mybluelink.ca" }

    public override var apiName: String { "HyundaiCanada" }

    // MARK: - APIClientProtocol Implementation

    public func login() async throws -> AuthToken {
        BBLogger.info(.auth, "HyundaiCanada: starting login")

        let cookie = try await ensureCloudFlareCookie()

        var loginHeaders = headers()
        loginHeaders["Cookie"] = cookie

        let (data, _, _) = try await performJSONRequest(
            url: "\(apiBaseURL)/v2/login",
            method: .POST,
            headers: loginHeaders,
            body: [
                "loginId": username,
                "password": password
            ],
            requestType: .login
        )

        // Intercept the OTP-required response (errorCode 7110) before
        // the generic parser runs — it would otherwise throw a generic
        // "Canada login failed" error and the caller couldn't tell
        // that an MFA challenge is what's needed. `beginMFAFlow` always
        // throws `requiresMFA` on success; control only returns here on
        // a non-7110 response, which the regular parser handles.
        if isOTPRequiredResponse(data) {
            try await beginMFAFlow(cookie: cookie)
        }

        return try parseCanadaLoginResponse(data)
    }

    public func fetchVehicles(authToken: AuthToken) async throws -> [Vehicle] {
        _ = try await ensureCloudFlareCookie()

        let (data, _, _) = try await performJSONRequest(
            url: "\(apiBaseURL)/vhcllst",
            method: .POST,
            headers: authorizedHeaders(authToken: authToken),
            requestType: .fetchVehicles
        )

        return try parseCanadaVehiclesResponse(data)
    }

    // Cached (sltvhcl) vs real-time (rltmvhclsts) status. Real-time wakes
    // the vehicle modem; use sparingly.
    public func fetchVehicleStatus(
        for vehicle: Vehicle,
        authToken: AuthToken,
        cached: Bool
    ) async throws -> VehicleStatus {
        _ = try await ensureCloudFlareCookie()

        let statusEndpoint = cached ? "sltvhcl" : "rltmvhclsts"
        let (primaryData, _, _) = try await performJSONRequest(
            url: "\(apiBaseURL)/\(statusEndpoint)",
            method: .POST,
            headers: authorizedHeaders(authToken: authToken, vehicleId: vehicle.regId),
            body: ["vehicleId": vehicle.regId],
            requestType: .fetchVehicleStatus,
            vin: vehicle.vin
        )

        let statusData = cached ? primaryData : try await fetchRealtimeStatusData(
            primaryData: primaryData,
            vehicle: vehicle,
            authToken: authToken
        )
        let finalData = await injectLocationCoordinates(into: statusData, vehicle: vehicle, authToken: authToken)

        do {
            return try parseCanadaVehicleStatusResponse(finalData, for: vehicle)
        } catch {
            BBLogger.debug(.api, "HyundaiCanada: parsing final status payload failed: \(error)")
            return try parseCanadaVehicleStatusResponse(primaryData, for: vehicle)
        }
    }

    private func fetchRealtimeStatusData(
        primaryData: Data,
        vehicle: Vehicle,
        authToken: AuthToken
    ) async throws -> Data {
        // Fetch cached sltvhcl payload for complete vehicle metadata
        var finalData = primaryData
        do {
            let (cachedData, _, _) = try await performJSONRequest(
                url: "\(apiBaseURL)/sltvhcl",
                method: .POST,
                headers: authorizedHeaders(authToken: authToken, vehicleId: vehicle.regId),
                body: ["vehicleId": vehicle.regId],
                requestType: .fetchVehicleStatus,
                vin: vehicle.vin
            )
            finalData = cachedData
        } catch {
            BBLogger.debug(.api, "HyundaiCanada: failed fetching sltvhcl: \(error)")
        }

        return finalData
    }

    private func injectLocationCoordinates(into data: Data, vehicle: Vehicle, authToken: AuthToken) async -> Data {
        do {
            let pAuth = try await fetchCommandAuthCode(authToken: authToken)
            let (locationData, _, _) = try await performJSONRequest(
                url: "\(apiBaseURL)/fndmcr",
                method: .POST,
                headers: authorizedHeaders(authToken: authToken, vehicleId: vehicle.regId, pAuth: pAuth),
                body: ["pin": pin],
                requestType: .fetchVehicleStatus,
                vin: vehicle.vin
            )
            let location = try parseCanadaLocationResponse(locationData)

            guard var finalJson = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return data
            }

            let coord: [String: Any] = [
                "lat": location.latitude,
                "lon": location.longitude
            ]
            var result = finalJson["result"] as? [String: Any] ?? [:]
            var status = result["status"] as? [String: Any]
                ?? result["vehicleStatus"] as? [String: Any] ?? [:]
            status["coord"] = coord
            status["vehicleLocation"] = ["coord": coord]
            result["status"] = status
            finalJson["result"] = result
            return try JSONSerialization.data(withJSONObject: finalJson)
        } catch {
            BBLogger.debug(.api, "HyundaiCanada: failed injecting location: \(error)")
            return data
        }
    }

    public func sendCommand(for vehicle: Vehicle, command: VehicleCommand, authToken: AuthToken) async throws {
        _ = try await ensureCloudFlareCookie()

        let authCode = try await fetchCommandAuthCode(authToken: authToken)

        try await sendCommandRequest(
            for: vehicle,
            command: command,
            authToken: authToken,
            authCode: authCode
        )
    }

    public func fetchEVTripDetails(for vehicle: Vehicle, authToken: AuthToken) async throws -> [EVTripDetail]? {
        nil
    }

    // MARK: - Command Flow

    private func fetchCommandAuthCode(authToken: AuthToken) async throws -> String {
        let (data, _, _) = try await performJSONRequest(
            url: "\(apiBaseURL)/vrfypin",
            method: .POST,
            headers: authorizedHeaders(authToken: authToken),
            body: ["pin": pin],
            requestType: .sendCommand
        )

        return try parseCommandAuthResponse(data)
    }

    private func sendCommandRequest(
        for vehicle: Vehicle,
        command: VehicleCommand,
        authToken: AuthToken,
        authCode: String
    ) async throws {
        if case .startClimate = command {
            do {
                try await sendCommandRequest(
                    for: vehicle,
                    command: command,
                    authToken: authToken,
                    authCode: authCode,
                    useRemoteControl: false
                )
                return
            } catch {
                try await sendCommandRequest(
                    for: vehicle,
                    command: command,
                    authToken: authToken,
                    authCode: authCode,
                    useRemoteControl: true
                )
                return
            }
        }

        try await sendCommandRequest(
            for: vehicle,
            command: command,
            authToken: authToken,
            authCode: authCode,
            useRemoteControl: false
        )
    }

    private func sendCommandRequest(
        for vehicle: Vehicle,
        command: VehicleCommand,
        authToken: AuthToken,
        authCode: String,
        useRemoteControl: Bool
    ) async throws {
        let (data, _, _) = try await performJSONRequest(
            url: "\(apiBaseURL)/\(commandPath(for: command))",
            method: .POST,
            headers: authorizedHeaders(authToken: authToken, vehicleId: vehicle.regId, pAuth: authCode),
            body: makeCommandBody(command: command, useRemoteControl: useRemoteControl),
            requestType: .sendCommand,
            vin: vehicle.vin
        )

        try validateCommandResponse(data, context: "command")
    }

    private func ensureCloudFlareCookie() async throws -> String {
        if let cloudFlareCookie, !cloudFlareCookie.isEmpty {
            return cloudFlareCookie
        }

        let cookie = try await fetchCloudFlareCookie()
        cloudFlareCookie = cookie
        return cookie
    }
}
