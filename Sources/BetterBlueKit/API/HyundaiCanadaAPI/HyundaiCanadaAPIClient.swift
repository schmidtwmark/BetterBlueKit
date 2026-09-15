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

    // One identity, matching hyundai_kia_connect_api's KiaUvoApiCA:
    // `from: SPA` with a browser User-Agent on every request — upstream's
    // API_HEADERS carry `from: SPA` for login, status, and commands alike,
    // and the "remote function" family (`fndmcr`, SVM) outright rejects
    // any other identity with errorCode 6459. The web-portal/native-app
    // variant picker and the manual `__cf_bm` cookie dance this client
    // used to carry are gone — URLSession's shared cookie storage already
    // accumulates whatever Cloudflare sets, the same way `requests.Session`
    // does for the Python reference, and hard-requiring the cookie was
    // itself a failure mode (#35).
    static let userAgent =
        "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 "
        + "(KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36"

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

    // Note: temperature lookup tables removed in the EU temperature
    // cleanup — the canonical tables now live on `Temperature` (see
    // `Models/Measurements.swift`), and Canada's HEX codec goes through
    // the model-year-aware `Temperature.encodeCanadaAirTempToHEX` /
    // `decodeCanadaAirTempHEX` pair.

    // MARK: - Location Gate State
    //
    // Per-client-instance memory for the fndmcr gate (see
    // `injectLocationCoordinates`): the last coordinates served per VIN,
    // the odometer at the last fetch attempt, and when the last fetch
    // attempt ran (successful or not) so retries are rate-limited rather
    // than per-poll or never.
    var lastLocationByVin: [String: VehicleStatus.Location] = [:]
    var lastLocationOdometerByVin: [String: Double] = [:]
    var lastLocationAttemptByVin: [String: Date] = [:]
    /// Minimum spacing between location fetches that aren't justified by
    /// vehicle movement (unknown odometer, or no location cached yet).
    static let locationRetryInterval: TimeInterval = 30 * 60

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

    // Declared here rather than in `+MFA` so one list covers every
    // optional capability the Canada client implements.
    public func optionalFeaturesSupported() -> [OptionalAPIFeature] {
        [.mfa, .surroundView, .surroundViewCapture]
    }

    public func login() async throws -> AuthToken {
        BBLogger.info(.auth, "HyundaiCanada: starting login")

        let (data, _, _) = try await performJSONRequest(
            url: "\(apiBaseURL)/v2/login",
            method: .POST,
            headers: headers(),
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
            try await beginMFAFlow()
        }

        return try parseCanadaLoginResponse(data)
    }

    public func fetchVehicles(authToken: AuthToken) async throws -> [Vehicle] {
        let (data, _, _) = try await performJSONRequest(
            url: "\(apiBaseURL)/vhcllst",
            method: .POST,
            headers: authorizedHeaders(authToken: authToken),
            requestType: .fetchVehicles
        )

        return try parseCanadaVehiclesResponse(data)
    }

    // Cached (lstvhclsts) vs real-time (rltmvhclsts) status — upstream's
    // endpoint pair. Real-time wakes the vehicle modem; use sparingly.
    // Both are POSTs with no body; the vehicle rides in the header.
    public func fetchVehicleStatus(
        for vehicle: Vehicle,
        authToken: AuthToken,
        cached: Bool
    ) async throws -> VehicleStatus {
        let statusEndpoint = cached ? "lstvhclsts" : "rltmvhclsts"
        let (primaryData, _, _) = try await performJSONRequest(
            url: "\(apiBaseURL)/\(statusEndpoint)",
            method: .POST,
            headers: authorizedHeaders(authToken: authToken, vehicleId: vehicle.regId),
            requestType: .fetchVehicleStatus,
            vin: vehicle.vin
        )

        // Neither status endpoint carries the odometer; upstream reads it
        // from the next-service call. Fold it into the payload before the
        // location gate runs so "has the car moved" can see it.
        let serviceOdometer = await fetchNextServiceOdometer(vehicle: vehicle, authToken: authToken)
        let statusData = injectOdometer(serviceOdometer, into: primaryData)
        let finalData = await injectLocationCoordinates(into: statusData, vehicle: vehicle, authToken: authToken)

        do {
            return try parseCanadaVehicleStatusResponse(finalData, for: vehicle)
        } catch {
            BBLogger.debug(.api, "HyundaiCanada: parsing status payload failed: \(error)")
            if cached { throw error }
            // The forced (rltmvhclsts) payload didn't parse — fall back
            // to the server cache rather than failing the refresh.
            let (cachedData, _, _) = try await performJSONRequest(
                url: "\(apiBaseURL)/lstvhclsts",
                method: .POST,
                headers: authorizedHeaders(authToken: authToken, vehicleId: vehicle.regId),
                requestType: .fetchVehicleStatus,
                vin: vehicle.vin
            )
            return try parseCanadaVehicleStatusResponse(
                injectOdometer(serviceOdometer, into: cachedData),
                for: vehicle
            )
        }
    }

    /// Injects `fndmcr` coordinates into the status payload, but only
    /// fetches when the car has moved (odometer increased since the last
    /// fetch) or on a rate-limited retry (at most one attempt per
    /// `locationRetryInterval` when the odometer is unreadable or no
    /// location is cached yet). Ports upstream's location gate
    /// (kia_uvo#1844); `fndmcr` costs a `vrfypin` + a remote-function
    /// call against an API that rate-limits, so it must not run on
    /// every poll — and a payload without a parseable odometer must not
    /// degrade back into per-poll fetching, while a single transient
    /// failure must not disable location for the client's lifetime.
    /// Skipped polls re-inject the last known coordinates so the host
    /// keeps showing a location.
    private func injectLocationCoordinates(into data: Data, vehicle: Vehicle, authToken: AuthToken) async -> Data {
        let vin = vehicle.vin
        let freshOdometer = extractOdometerValue(from: data)

        // Only a readable, increased odometer counts as movement; an
        // unreadable one falls to the rate-limited retry path instead of
        // being treated as "moved" on every poll.
        let movedSinceLastFetch: Bool = {
            guard let freshOdometer, let lastOdo = lastLocationOdometerByVin[vin] else { return false }
            return freshOdometer > lastOdo
        }()
        let cachedLocation = lastLocationByVin[vin]
        let attemptDue: Bool = {
            guard let lastAttempt = lastLocationAttemptByVin[vin] else { return true }
            return Date().timeIntervalSince(lastAttempt) >= Self.locationRetryInterval
        }()
        let shouldFetch = movedSinceLastFetch
            || ((cachedLocation == nil || freshOdometer == nil) && attemptDue)

        guard shouldFetch else {
            guard let cachedLocation else { return data }
            return injectCoordinates(cachedLocation, into: data)
        }

        // Stamp the attempt regardless of outcome so a persistently
        // failing Find-My-Car response backs off instead of re-running
        // on every poll.
        lastLocationAttemptByVin[vin] = Date()
        if let freshOdometer { lastLocationOdometerByVin[vin] = freshOdometer }

        do {
            let pAuth = try await fetchCommandAuthCode(authToken: authToken, vehicle: vehicle)
            let locationData = try await fetchLocationData(vehicle: vehicle, authToken: authToken, pAuth: pAuth)
            let location = try parseCanadaLocationResponse(locationData)
            if location.latitude != 0 || location.longitude != 0 {
                lastLocationByVin[vin] = location
            }
            return injectCoordinates(location, into: data)
        } catch {
            BBLogger.debug(.api, "HyundaiCanada: failed injecting location: \(error)")
            guard let cachedLocation else { return data }
            return injectCoordinates(cachedLocation, into: data)
        }
    }

    private func injectCoordinates(_ location: VehicleStatus.Location, into data: Data) -> Data {
        guard var finalJson = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
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
        return (try? JSONSerialization.data(withJSONObject: finalJson)) ?? data
    }

    /// Best-effort odometer read straight off the raw status payload,
    /// for the location-fetch gate.
    private func extractOdometerValue(from data: Data) -> Double? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let result = json["result"] as? [String: Any] else {
            return nil
        }
        for block in [result["vehicle"], result["status"], result["vehicleStatus"]] {
            guard let dict = block as? [String: Any] else { continue }
            if let value: Double = extractNumber(from: dict["odometer"]) { return value }
            if let odo = dict["odometer"] as? [String: Any],
               let value: Double = extractNumber(from: odo["value"]) {
                return value
            }
        }
        return nil
    }

    public func sendCommand(for vehicle: Vehicle, command: VehicleCommand, authToken: AuthToken) async throws {
        let authCode = try await fetchCommandAuthCode(authToken: authToken, vehicle: vehicle)

        try await sendCommandRequest(
            for: vehicle,
            command: command,
            authToken: authToken,
            authCode: authCode
        )
    }

    public func fetchEVTripSummary(for vehicle: Vehicle, authToken: AuthToken) async throws -> [EVTripSummary]? {
        nil
    }

    // MARK: - Command Flow

    func fetchCommandAuthCode(authToken: AuthToken, vehicle: Vehicle) async throws -> String {
        // Upstream sends the vehicleId header on `vrfypin` too.
        let (data, _, _) = try await performJSONRequest(
            url: "\(apiBaseURL)/vrfypin",
            method: .POST,
            headers: authorizedHeaders(authToken: authToken, vehicleId: vehicle.regId),
            body: ["pin": pin],
            requestType: .sendCommand,
            vin: vehicle.vin
        )

        return try parseCommandAuthResponse(data)
    }

    private func sendCommandRequest(
        for vehicle: Vehicle,
        command: VehicleCommand,
        authToken: AuthToken,
        authCode: String
    ) async throws {
        // The hvacInfo → remoteControl fallback only applies to the EV
        // payload (upstream's EV9 / IONIQ 9 use the remoteControl
        // wrapper); the ICE `setting` body has no wrapper choice, and
        // retrying it would just double the command.
        if case .startClimate = command, vehicle.fuelType == .electric {
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
        // `evc/setsoc` takes the remote-function identity (`from: SPA`)
        // like the rest of the `fndmcr`/SVM family — upstream sets it
        // explicitly for this call.
        let headers: [String: String]
        if case .setTargetSOC = command {
            headers = remoteFunctionHeaders(authToken: authToken, vehicleId: vehicle.regId, pAuth: authCode)
        } else {
            headers = authorizedHeaders(authToken: authToken, vehicleId: vehicle.regId, pAuth: authCode)
        }

        let (data, _, _) = try await performJSONRequest(
            url: "\(apiBaseURL)/\(commandPath(for: command, vehicle: vehicle))",
            method: .POST,
            headers: headers,
            body: makeCommandBody(command: command, vehicle: vehicle, useRemoteControl: useRemoteControl),
            requestType: .sendCommand,
            vin: vehicle.vin
        )

        try validateCommandResponse(data, context: "command")
    }
}
